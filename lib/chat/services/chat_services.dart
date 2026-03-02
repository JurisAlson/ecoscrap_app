import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ChatService {
  final _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  Future<void> deleteChatImages(String chatId) async {
    final folderRef =
        FirebaseStorage.instance.ref().child('chat_images').child(chatId);

    String? pageToken;

    do {
      final result = await folderRef.list(
        ListOptions(maxResults: 1000, pageToken: pageToken),
      );

      for (final item in result.items) {
        try {
          await item.delete();
        } catch (_) {}
      }

      pageToken = result.nextPageToken;
    } while (pageToken != null);
  }

  // ==========================================================
  // ✅ IMPORTANT: your rules do NOT allow deleting messages
  // match /messages/{id} { allow update, delete: if false; }
  //
  // So this will FAIL from client unless you change rules
  // or do deletion via Cloud Function / Admin SDK.
  // ==========================================================
  Future<void> deleteChat(String chatId) async {
  // ✅ 1) delete storage images first
  await deleteChatImages(chatId);

  // ✅ 2) delete messages
  final chatRef = _db.collection('chats').doc(chatId);
  final messagesRef = chatRef.collection('messages');

  while (true) {
    final snap = await messagesRef.limit(400).get();
    if (snap.docs.isEmpty) break;

    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  // ✅ 3) delete chat doc last
  await chatRef.delete();
}

Future<void> cleanupPickupChats(String requestId) async {
  // pickup chat
  await deleteChat("pickup_$requestId");

  // junkshop chat (safe even if it doesn't exist)
  try {
    await deleteChat("junkshop_pickup_$requestId");
  } catch (_) {
    // ignore if junkshop chat never existed or already deleted
  }
}

  // ==========================================================
  // ✅ SEND IMAGE
  // - rules require createdAt is timestamp
  // - rules allow chat doc update only for lastMessage + lastMessageAt
  // ==========================================================
  Future<void> sendImage({
    required String chatId,
    required File file,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Not logged in");

    final msgRef =
        _db.collection('chats').doc(chatId).collection('messages').doc();
    final msgId = msgRef.id;

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chat_images')
        .child(chatId)
        .child('$msgId.jpg');

    await storageRef.putFile(file);
    final imageUrl = await storageRef.getDownloadURL();

    // ✅ Use Timestamp.now() (rules want timestamp, not serverTimestamp sentinel)
    await msgRef.set({
      'senderId': uid,
      'type': 'image',
      'imageUrl': imageUrl,
      'text': '',
      'createdAt': Timestamp.now(),
    });

    // ✅ Update ONLY allowed fields
    await _db.collection('chats').doc(chatId).update({
      'lastMessage': '📷 Photo',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  // ==========================================================
  // ✅ SEND TEXT
  // ==========================================================
  Future<void> sendText({
    required String chatId,
    required String text,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Not logged in");
    if (text.trim().isEmpty) return;

    final msgRef =
        _db.collection('chats').doc(chatId).collection('messages').doc();

    await msgRef.set({
      'senderId': uid,
      'type': 'text',
      'text': text.trim(),
      'createdAt': Timestamp.now(), // ✅ timestamp
    });

    // ✅ Update ONLY allowed fields
    await _db.collection('chats').doc(chatId).update({
      'lastMessage': text.trim(),
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  // ==========================================================
  // ✅ ENSURE PICKUP CHAT
  //
  // RULES LIMITATION:
  // - create is allowed only if reqAllowsChat(requestId) is true
  // - update is NOT allowed for participants/names/uids
  //
  // So:
  // ✅ If chat exists → return chatId (no backfill writes)
  // ✅ If not → create it with names/uids immediately
  // ==========================================================
  Future<String> ensurePickupChat({
    required String requestId,
    required String householdUid,
    required String collectorUid,
  }) async {
    final chatId = "pickup_$requestId";
    final ref = _db.collection('chats').doc(chatId);
    final snap = await ref.get();

    if (snap.exists) {
      // ✅ Cannot merge-update extra fields due to your rules
      return chatId;
    }

    // fetch names (safe: read depends on your Users rules; if blocked, fallback)
    String householdName = "Household";
    String collectorName = "Collector";

    try {
      final householdDoc = await _db.collection("Users").doc(householdUid).get();
      final collectorDoc = await _db.collection("Users").doc(collectorUid).get();

      final h = householdDoc.data() ?? {};
      final c = collectorDoc.data() ?? {};

      householdName =
          (h["name"] ?? h["Name"] ?? h["publicName"] ?? "Household").toString();
      collectorName =
          (c["name"] ?? c["Name"] ?? c["publicName"] ?? "Collector").toString();
    } catch (_) {
      // ignore; keep fallbacks
    }

    await ref.set({
      'type': 'pickup',
      'requestId': requestId,
      'participants': [householdUid, collectorUid],
      'householdUid': householdUid,
      'collectorUid': collectorUid,
      'householdName': householdName,
      'collectorName': collectorName,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    return chatId;
  }

  // ==========================================================
  // ✅ ENSURE JUNKSHOP CHAT FOR ACTIVE PICKUP
  //
  // Same rule limitation:
  // - if exists → return chatId (no backfill update)
  // - if create → include names at create time
  // ==========================================================
  Future<String?> ensureJunkshopChatForActivePickup({
  required String junkshopUid,
  required String collectorUid,
}) async {
  final q = await _db
      .collection('requests')
      .where('type', isEqualTo: 'pickup')
      .where('collectorId', isEqualTo: collectorUid)
      .where('active', isEqualTo: true)
      .where('status', whereIn: ['accepted', 'arrived', 'scheduled'])
      .orderBy('updatedAt', descending: true)
      .limit(1)
      .get();

  if (q.docs.isEmpty) return null;

  final requestId = q.docs.first.id;

  final chatId = "junkshop_pickup_$requestId";
  final ref = _db.collection('chats').doc(chatId);
  final snap = await ref.get();

  if (snap.exists) {
    // ✅ optional: ensure requestId exists for old docs (won't work with your chat update rules)
    // so just return
    return chatId;
  }

  String collectorName = "Collector";
  String junkshopName = "Junkshop";

  try {
    final collectorDoc = await _db.collection("Users").doc(collectorUid).get();
    final junkshopDoc = await _db.collection("Users").doc(junkshopUid).get();

    final c = collectorDoc.data() ?? {};
    final j = junkshopDoc.data() ?? {};

    collectorName =
        (c["name"] ?? c["Name"] ?? c["publicName"] ?? "Collector").toString();
    junkshopName =
        (j["shopName"] ?? j["name"] ?? j["Name"] ?? "Junkshop").toString();
  } catch (_) {}

  await ref.set({
    'type': "junkshop",
    'requestId': requestId, // ✅ THIS is required for Storage rules
    'participants': [junkshopUid, collectorUid],
    'junkshopUid': junkshopUid,
    'collectorUid': collectorUid,
    'junkshopName': junkshopName,
    'collectorName': collectorName,
    'createdAt': FieldValue.serverTimestamp(),
    'lastMessage': '',
    'lastMessageAt': FieldValue.serverTimestamp(),
  });

  return chatId;
}

  // ==========================================================
  // ⚠️ BACKFILL METHOD (NOT POSSIBLE WITH CURRENT RULES)
  //
  // Your rules only allow chat update for:
  //   ["lastMessage","lastMessageAt"]
  //
  // So updating collectorName/junkshopName will FAIL.
  // Keep this method as NO-OP to avoid confusion.
  // ==========================================================
  Future<void> backfillJunkshopChatIfMissing({
    required String chatId,
    required String collectorUid,
    required String junkshopUid,
  }) async {
    // NO-OP under current rules
    return;
  }
}

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../constants/app_constants.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

  Future<void> deleteChat(String chatId) async {
    await deleteChatImages(chatId);

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

    await chatRef.delete();
  }

  Future<void> cleanupPickupChats(String requestId) async {
    await deleteChat("pickup_$requestId");

    try {
      await deleteChat("junkshop_pickup_$requestId");
    } catch (_) {}
  }

  // ==========================================================
  // ✅ SEND IMAGE (legacy simple send)
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

    final ext = _safeExtension(file.path);
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chat_images')
        .child(chatId)
        .child('$msgId.$ext');

    await storageRef.putFile(file);
    final imageUrl = await storageRef.getDownloadURL();

    await msgRef.set({
      'senderId': uid,
      'type': 'image',
      'imageUrl': imageUrl,
      'text': '',
      'createdAt': Timestamp.now(),
      'deliveredAt': FieldValue.serverTimestamp(), // ✅ ADD
      'seenAt': null, // ✅ ADD
    });

    await _db.collection('chats').doc(chatId).update({
      'lastMessage': '📷 Photo',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': uid,
    });
  }

Future<String?> ensureSellChat({
  required String collectorId,
  required String junkshopId,
  required String sellRequestId,
}) async {
  final db = FirebaseFirestore.instance;

  final query = await db
      .collection('chats')
      .where('sellRequestId', isEqualTo: sellRequestId)
      .limit(1)
      .get();

  if (query.docs.isNotEmpty) {
    return query.docs.first.id;
  }

  final doc = await db.collection('chats').add({
    'type': 'collector_junkshop_sell',
    'participants': [collectorId, junkshopId],
    'collectorId': collectorId,
    'junkshopId': junkshopId,
    'sellRequestId': sellRequestId,
    'createdAt': FieldValue.serverTimestamp(),
    'lastMessage': '',
    'lastMessageAt': FieldValue.serverTimestamp(),
  });

  return doc.id;
}

Future<String> ensureDropoffChat({
  required String requestId,
  required String householdUid,
  required String junkshopUid,
}) async {
  final chatId = "dropoff_$requestId";
  final ref = _db.collection('chats').doc(chatId);
  final snap = await ref.get();

  if (snap.exists) return chatId;

  String householdName = "Household";
  String junkshopName = "Junkshop";

  try {
    final householdDoc = await _db.collection("Users").doc(householdUid).get();
    final junkshopDoc = await _db.collection("Users").doc(junkshopUid).get();

    final h = householdDoc.data() ?? {};
    final j = junkshopDoc.data() ?? {};

    householdName =
        (h["name"] ?? h["Name"] ?? h["publicName"] ?? "Household").toString();

    junkshopName =
        (j["shopName"] ?? j["name"] ?? j["Name"] ?? "Junkshop").toString();
  } catch (_) {}

  await ref.set({
    'type': 'dropoff',
    'requestId': requestId,
    'participants': [householdUid, junkshopUid],
    'householdUid': householdUid,
    'junkshopUid': junkshopUid,
    'householdName': householdName,
    'junkshopName': junkshopName,
    'createdAt': FieldValue.serverTimestamp(),
    'lastMessage': '',
    'lastMessageAt': FieldValue.serverTimestamp(),
  });

  return chatId;
}

  // ==========================================================
  // ✅ SEND IMAGE WITH PROGRESS
  // ==========================================================
  Future<void> sendImageWithProgress({
    required String chatId,
    required File file,
    required void Function(double progress) onProgress,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Not logged in");

    final msgRef =
        _db.collection('chats').doc(chatId).collection('messages').doc();
    final msgId = msgRef.id;

    final ext = _safeExtension(file.path);
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chat_images')
        .child(chatId)
        .child('$msgId.$ext');

    final uploadTask = storageRef.putFile(file);

    final sub = uploadTask.snapshotEvents.listen((snapshot) {
      final total = snapshot.totalBytes;
      final sent = snapshot.bytesTransferred;

      if (total > 0) {
        onProgress(sent / total);
      }
    });

    try {
      final snap = await uploadTask;
      final imageUrl = await snap.ref.getDownloadURL();

      await msgRef.set({
        'senderId': uid,
        'type': 'image',
        'imageUrl': imageUrl,
        'text': '',
        'createdAt': Timestamp.now(),
        'deliveredAt': FieldValue.serverTimestamp(), // ✅ ADD
        'seenAt': null, // ✅ ADD
      });

      await _db.collection('chats').doc(chatId).update({
        'lastMessage': '📷 Photo',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': uid,
      });

      onProgress(1.0);
    } finally {
      await sub.cancel();
    }
  }

  String _safeExtension(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'png';
    if (lower.endsWith('.webp')) return 'webp';
    if (lower.endsWith('.heic')) return 'heic';
    if (lower.endsWith('.jpeg')) return 'jpeg';
    if (lower.endsWith('.gif')) return 'gif';
    return 'jpg';
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

  final now = FieldValue.serverTimestamp();

  await msgRef.set({
    'senderId': uid,
    'type': 'text',
    'text': text.trim(),
    'createdAt': now,
    'deliveredAt': now, // ✅ ADD THIS
    'seenAt': null,     // ✅ ADD THIS
  });

  await _db.collection('chats').doc(chatId).update({
    'lastMessage': text.trim(),
    'lastMessageAt': now,
    'lastMessageSenderId': uid,
  });
}

Future<void> markMessagesAsSeen({
  required String chatId,
  required String currentUserId,
}) async {
  final messagesRef = _db
      .collection('chats')
      .doc(chatId)
      .collection('messages');

  final unreadSnap = await messagesRef
      .where('seenAt', isNull: true)
      .get();

  if (unreadSnap.docs.isEmpty) return;

  final batch = _db.batch();
  bool hasUpdates = false;

  for (final doc in unreadSnap.docs) {
    final data = doc.data();
    final senderId = (data['senderId'] ?? '').toString();

    // ❗ Only mark messages from OTHER USER
    if (senderId == currentUserId) continue;

    batch.update(doc.reference, {
      'seenAt': FieldValue.serverTimestamp(),
    });

    hasUpdates = true;
  }

  if (hasUpdates) {
    await batch.commit();
  }
}

  // ==========================================================
  // ✅ ENSURE PICKUP CHAT
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
      return chatId;
    }

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
    } catch (_) {}

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
        .where(
          'status',
          whereIn: ['pending', 'accepted', 'arrived', 'scheduled'],
        )
        .orderBy('updatedAt', descending: true)
        .limit(1)
        .get();

    if (q.docs.isEmpty) return null;

    final requestId = q.docs.first.id;

    final chatId = "junkshop_pickup_$requestId";
    final ref = _db.collection('chats').doc(chatId);
    final snap = await ref.get();

    if (snap.exists) {
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
      'requestId': requestId,
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

  Future<void> sendImageMessage({
  required String chatId,
  required File file,
  required String senderId,
}) async {
  final firestore = FirebaseFirestore.instance;
  final storage = FirebaseStorage.instance;

  final msgRef = firestore
      .collection('chats')
      .doc(chatId)
      .collection('messages')
      .doc();

  final fileName = "${msgRef.id}.jpg";

  final storageRef = storage
      .ref()
      .child('chat_images')
      .child(chatId)
      .child(fileName);

  // upload file
  await storageRef.putFile(file);

  final imageUrl = await storageRef.getDownloadURL();

  // save message
  await msgRef.set({
    "senderId": senderId,
    "type": "image",
    "imageUrl": imageUrl,
    "text": "",
    "createdAt": FieldValue.serverTimestamp(),
    "deliveredAt": FieldValue.serverTimestamp(),
    "seenAt": null,
  });
}

  Future<void> ensureJunkshopChatForRequest({
    required String requestId,
    required String junkshopUid,
    required String collectorUid,
  }) async {
    final chatId = "junkshop_pickup_$requestId";
    final ref = _db.collection('chats').doc(chatId);

    final existing = await ref.get();
    if (existing.exists) return;

    await ref.set({
      'type': "junkshop",
      'requestId': requestId,
      'participants': [junkshopUid, collectorUid],
      'junkshopUid': junkshopUid,
      'collectorUid': collectorUid,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': "",
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String?> ensureJunkshopSupportChatForCollector({
    required String collectorUid,
  }) async {
    final junkshopUid = AppConstants.primaryJunkshopUid;
    if (junkshopUid.isEmpty) return null;

    final chatId = "junkshop_support_$collectorUid";
    final ref = _db.collection('chats').doc(chatId);
    final snap = await ref.get();

    if (snap.exists) return chatId;

    String collectorName = "Collector";
    String junkshopName = "Junkshop";
    try {
      final cDoc = await _db.collection("Users").doc(collectorUid).get();
      final jDoc = await _db.collection("Users").doc(junkshopUid).get();
      final c = cDoc.data() ?? {};
      final j = jDoc.data() ?? {};
      collectorName =
          (c["name"] ?? c["publicName"] ?? "Collector").toString();
      junkshopName =
          (j["shopName"] ?? j["name"] ?? "Junkshop").toString();
    } catch (_) {}

    await ref.set({
      'type': 'junkshop_support',
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

  Future<void> backfillJunkshopChatIfMissing({
    required String chatId,
    required String collectorUid,
    required String junkshopUid,
  }) async {
    return;
  }
}
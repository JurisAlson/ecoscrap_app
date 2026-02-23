import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
      'text': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('chats').doc(chatId).set({
      'lastMessage': text.trim(),
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> ensurePickupChat({
    required String requestId,
    required String householdUid,
    required String collectorUid,
  }) async {
    final chatId = "pickup_$requestId";
    final ref = _db.collection('chats').doc(chatId);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'type': 'pickup',
        'requestId': requestId,
        'participants': [householdUid, collectorUid],
        'householdUid': householdUid,
        'collectorUid': collectorUid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    }

    return chatId;
  }

  /// ✅ Always available chat between collector and junkshop
  /// deterministic chatId
  Future<String> ensureJunkshopChat({
  required String junkshopUid,
  required String collectorUid,
}) async {
  final ids = [collectorUid, junkshopUid]..sort();
  final chatId = "junkshop_${ids[0]}_${ids[1]}";

  final ref = _db.collection('chats').doc(chatId);
  final snap = await ref.get();

  if (!snap.exists) {
    // ✅ fetch names once (safe + simple)
    final collectorDoc = await _db.collection("Users").doc(collectorUid).get();
    final junkshopDoc = await _db.collection("Users").doc(junkshopUid).get();

    final c = collectorDoc.data() ?? {};
    final j = junkshopDoc.data() ?? {};

    final collectorName =
        (c["name"] ?? c["Name"] ?? c["publicName"] ?? "Collector").toString();

    final junkshopName =
        (j["shopName"] ?? j["name"] ?? j["Name"] ?? "Junkshop").toString();

    await ref.set({
      'type': 'junkshop',
      'participants': ids,
      'collectorUid': collectorUid,
      'junkshopUid': junkshopUid,

      // ✅ store names
      'collectorName': collectorName,
      'junkshopName': junkshopName,

      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  return chatId;
}
  /// ✅ Backfill for old chat docs that were created without names/uid fields
  /// Works now because you allowed update collectorName/junkshopName
  Future<void> backfillJunkshopChatIfMissing({
    required String chatId,
    required String collectorUid,
    required String junkshopUid,
  }) async {
    final ref = _db.collection('chats').doc(chatId);
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = (snap.data() as Map<String, dynamic>?) ?? {};

    final hasCollectorUid = (data['collectorUid'] ?? '').toString().trim().isNotEmpty;
    final hasJunkshopUid = (data['junkshopUid'] ?? '').toString().trim().isNotEmpty;

    final hasCollectorName = (data['collectorName'] ?? '').toString().trim().isNotEmpty;
    final hasJunkshopName = (data['junkshopName'] ?? '').toString().trim().isNotEmpty;

    // nothing to do
    if (hasCollectorUid && hasJunkshopUid && hasCollectorName && hasJunkshopName) return;

    final collectorDoc = await _db.collection("Users").doc(collectorUid).get();
    final junkshopDoc = await _db.collection("Users").doc(junkshopUid).get();

    final c = collectorDoc.data() ?? {};
    final j = junkshopDoc.data() ?? {};

    final collectorName =
        (c["name"] ?? c["Name"] ?? c["publicName"] ?? "Collector").toString();

    final junkshopName =
        (j["name"] ?? j["shopName"] ?? j["Name"] ?? "Junkshop").toString();

    // IMPORTANT: your rules currently allow updating ONLY lastMessage/lastMessageAt + names.
    // So we update ONLY the allowed keys here:
    await ref.update({
      if (!hasCollectorName) 'collectorName': collectorName,
      if (!hasJunkshopName) 'junkshopName': junkshopName,
    });
  }
}
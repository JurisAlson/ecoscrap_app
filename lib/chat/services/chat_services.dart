import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
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

  /// ✅ Deletes chat doc + messages subcollection
  Future<void> deleteChat(String chatId) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final messagesRef = chatRef.collection('messages');

    // Delete messages in batches
    while (true) {
      final snap = await messagesRef.limit(400).get();
      if (snap.docs.isEmpty) break;

      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }

    // Delete chat doc
    await chatRef.delete();
  }

  Future<void> sendImage({
    required String chatId,
    required File file,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Not logged in");

    // create message doc id first so we can use it in the filename
    final msgRef = _db.collection('chats').doc(chatId).collection('messages').doc();
    final msgId = msgRef.id;

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chat_images')
        .child(chatId)
        .child('$msgId.jpg');

    // upload
    await storageRef.putFile(file);
    final imageUrl = await storageRef.getDownloadURL();

    // write message
    await msgRef.set({
      'senderId': uid,
      'type': 'image',
      'imageUrl': imageUrl,
      'text': '', // keep for compatibility
      'createdAt': FieldValue.serverTimestamp(),
    });

    // update chat preview
    await _db.collection('chats').doc(chatId).set({
      'lastMessage': '📷 Photo',
      'lastMessageAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> sendText({
    required String chatId,
    required String text,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception("Not logged in");
    if (text.trim().isEmpty) return;

    final msgRef = _db.collection('chats').doc(chatId).collection('messages').doc();

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

  /// ✅ Junkshop chat is ONLY allowed if collector has an active pickup
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

    if (!snap.exists) {
      await ref.set({
        'type': 'junkshop',
        'requestId': requestId,
        'participants': [junkshopUid, collectorUid],
        'junkshopUid': junkshopUid,
        'collectorUid': collectorUid,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    }

    return chatId;
  }

  /// ✅ Backfill for old chat docs that were created without names/uid fields
  Future<void> backfillJunkshopChatIfMissing({
    required String chatId,
    required String collectorUid,
    required String junkshopUid,
  }) async {
    final ref = _db.collection('chats').doc(chatId);
    final snap = await ref.get();
    if (!snap.exists) return;

    final data = snap.data() ?? {};

    final hasCollectorName = (data['collectorName'] ?? '').toString().trim().isNotEmpty;
    final hasJunkshopName = (data['junkshopName'] ?? '').toString().trim().isNotEmpty;

    if (hasCollectorName && hasJunkshopName) return;

    final collectorDoc = await _db.collection("Users").doc(collectorUid).get();
    final junkshopDoc = await _db.collection("Users").doc(junkshopUid).get();

    final c = collectorDoc.data() ?? {};
    final j = junkshopDoc.data() ?? {};

    final collectorName = (c["name"] ?? c["Name"] ?? c["publicName"] ?? "Collector").toString();
    final junkshopName = (j["name"] ?? j["shopName"] ?? j["Name"] ?? "Junkshop").toString();

    await ref.update({
      if (!hasCollectorName) 'collectorName': collectorName,
      if (!hasJunkshopName) 'junkshopName': junkshopName,
    });
  }
}
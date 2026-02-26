import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_profile_cyrpto.dart';

Future<void> upsertAdminEncryptedProfile({
  required String uid,
  required String email,
  required String name,
}) async {
  final emailEnc = await AdminProfileCrypto.encryptString(email);
  final nameEnc = await AdminProfileCrypto.encryptString(name);

  // IMPORTANT: write to the correct doc id if yours is not uid
  final q = await FirebaseFirestore.instance
      .collection('Users')
      .where('uid', isEqualTo: uid)
      .limit(1)
      .get();

  if (q.docs.isEmpty) {
    throw Exception("Admin document not found for uid $uid");
  }

  final docRef = q.docs.first.reference;

  await docRef.set({
    "uid": uid,
    "role": "admin",
    "profile": {
      "email": emailEnc,
      "name": nameEnc,
    },
    "updatedAt": FieldValue.serverTimestamp(),

    // delete plaintext
    "Email": FieldValue.delete(),
    "Name": FieldValue.delete(),
    "emailDisplay": FieldValue.delete(),
  }, SetOptions(merge: true));
}
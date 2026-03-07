import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static Future<void> init() async {
    final messaging = FirebaseMessaging.instance;

    try {
      await messaging.requestPermission();
    } catch (e) {
      print('requestPermission failed: $e');
    }

    String? token;
    try {
      token = await messaging.getToken();
      print('FCM token: $token');
    } catch (e, st) {
      print('getToken failed: $e');
      print(st);
      return;
    }

    if (token == null) return;

    try {
      await _saveToken(token);
    } catch (e) {
      print('saveToken failed: $e');
    }

    messaging.onTokenRefresh.listen((newToken) async {
      try {
        await _saveToken(newToken);
      } catch (e) {
        print('token refresh save failed: $e');
      }
    });
  }

  static Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance.collection('Users').doc(uid).set({
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
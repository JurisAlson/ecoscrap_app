// lib/security/kyc_crypto.dart
// AES-GCM encrypt/decrypt helpers (bytes)
// Collector: encrypt before upload
// Admin: decrypt after download

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class KycCrypto {
  static final _algo = AesGcm.with256bits();

  static SecretKey keyFromB64(String b64) {
    final bytes = base64Decode(b64);
    if (bytes.length != 32) {
      throw StateError("AES key must be 32 bytes. Got ${bytes.length} bytes.");
    }
    return SecretKey(bytes);
  }

  // ✅ Works in all versions: Random.secure()
  static Uint8List randomNonce12() {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(12, (_) => r.nextInt(256)));
  }

  static Future<KycEncrypted> encryptBytes({
    required Uint8List plain,
    required SecretKey key,
    required Uint8List nonce12,
    List<int> aad = const [],
  }) async {
    final box = await _algo.encrypt(
      plain,
      secretKey: key,
      nonce: nonce12,
      aad: aad,
    );

    return KycEncrypted(
      cipherText: Uint8List.fromList(box.cipherText),
      macBytes: Uint8List.fromList(box.mac.bytes),
      nonce: Uint8List.fromList(box.nonce),
    );
  }

  static Future<Uint8List> decryptBytes({
    required Uint8List cipherText,
    required Uint8List macBytes,
    required Uint8List nonce,
    required SecretKey key,
    List<int> aad = const [],
  }) async {
    final box = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final plain = await _algo.decrypt(
      box,
      secretKey: key,
      aad: aad,
    );

    return Uint8List.fromList(plain);
  }
}

class KycEncrypted {
  final Uint8List cipherText;
  final Uint8List macBytes; // 16 bytes
  final Uint8List nonce; // 12 bytes
  KycEncrypted({
    required this.cipherText,
    required this.macBytes,
    required this.nonce,
  });
}
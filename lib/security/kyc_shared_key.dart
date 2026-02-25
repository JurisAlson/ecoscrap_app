// lib/security/kyc_shared_key.dart
// Derive AES-256 key from X25519 shared secret using HKDF-SHA256

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

class KycSharedKey {
  static final _x25519 = X25519();
  static final _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );

  // Collector: ephemeral keypair (new per upload)
  static Future<SimpleKeyPair> newEphemeral() => _x25519.newKeyPair();

  static Future<Uint8List> publicKeyBytes(SimpleKeyPair kp) async {
    final pub = await kp.extractPublicKey();
    return Uint8List.fromList(pub.bytes);
  }

  // ✅ Salt generator (store in Firestore)
  static List<int> randomSalt16() {
    final r = Random.secure();
    return List<int>.generate(16, (_) => r.nextInt(256));
  }

  // Collector: eph private + admin public => AES key
  static Future<SecretKey> deriveForCollector({
    required SimpleKeyPair ephKeyPair,
    required String adminPublicKeyB64,
    required List<int> salt,
  }) async {
    final adminPub = SimplePublicKey(
      base64Decode(adminPublicKeyB64),
      type: KeyPairType.x25519,
    );

    final shared = await _x25519.sharedSecretKey(
      keyPair: ephKeyPair,
      remotePublicKey: adminPub,
    );

    final sharedBytes = await shared.extractBytes();

    return _hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: salt,
      info: utf8.encode("ecoscrap-kyc-v1"),
    );
  }

  // Admin: admin private + collector eph public => AES key
  static Future<SecretKey> deriveForAdmin({
    required String adminPrivateKeyB64,
    required Uint8List collectorEphemeralPubKeyBytes,
    required List<int> salt,
  }) async {
    final adminPrivBytes = base64Decode(adminPrivateKeyB64);

    // IMPORTANT: some cryptography versions require "publicKey" param.
    // We'll rebuild the full keypair using the derived public key bytes.
    final adminKp = await _x25519.newKeyPairFromSeed(adminPrivBytes);
    final adminPub = await adminKp.extractPublicKey();

    final adminKeyPair = SimpleKeyPairData(
      adminPrivBytes,
      publicKey: adminPub, // ✅ fixes "publicKey required"
      type: KeyPairType.x25519,
    );

    final collectorPub = SimplePublicKey(
      collectorEphemeralPubKeyBytes,
      type: KeyPairType.x25519,
    );

    final shared = await _x25519.sharedSecretKey(
      keyPair: adminKeyPair,
      remotePublicKey: collectorPub,
    );

    final sharedBytes = await shared.extractBytes();

    return _hkdf.deriveKey(
      secretKey: SecretKey(sharedBytes),
      nonce: salt,
      info: utf8.encode("ecoscrap-kyc-v1"),
    );
  }
}
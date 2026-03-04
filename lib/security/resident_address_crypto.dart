// lib/security/resident_address_crypto.dart
// USER APP OK ✅
// Encrypts resident address so ONLY the Admin App (private key) can decrypt.
// Stores ONLY encrypted fields to Firestore (no plaintext).

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'kyc_shared_key.dart';
import '../security/kyc_cyrpto.dart';
import 'admin_public_key.dart';

class ResidentAddressCrypto {
  /// Encrypt address for admin review (admin private key required to decrypt).
  ///
  /// Returns a Firestore-ready payload:
  /// {
  ///   ctB64, nonceB64, macB64, ephPubKeyB64, saltB64, schema
  /// }
  static Future<Map<String, dynamic>> encryptForAdmin({
    required String uid,
    required String address,
  }) async {
    // 1) Ephemeral keypair (new per submission)
    final SimpleKeyPair eph = await KycSharedKey.newEphemeral();
    final Uint8List ephPubBytes = await KycSharedKey.publicKeyBytes(eph);

    // 2) Salt + nonce
    final List<int> salt = KycSharedKey.randomSalt16();
    final Uint8List nonce12 = KycCrypto.randomNonce12();

    // 3) Derive AES-256 key from (eph private + admin public) via HKDF
    final SecretKey aesKey = await KycSharedKey.deriveForCollector(
      ephKeyPair: eph,
      adminPublicKeyB64: AdminPublicKey.adminPublicKeyB64,
      salt: salt,
    );

    // 4) Encrypt UTF-8 bytes
    final Uint8List plain = Uint8List.fromList(utf8.encode(address.trim()));

    final enc = await KycCrypto.encryptBytes(
      plain: plain,
      key: aesKey,
      nonce12: nonce12, // ✅ encrypt uses nonce12
      // Bind ciphertext to user + purpose to prevent swapping/replay
      aad: utf8.encode("resident-address-v1:$uid"),
    );

    // 5) Return Firestore-safe base64 payload
    return {
      "ctB64": base64Encode(enc.cipherText),
      "nonceB64": base64Encode(enc.nonce),
      "macB64": base64Encode(enc.macBytes),
      "ephPubKeyB64": base64Encode(ephPubBytes),
      "saltB64": base64Encode(Uint8List.fromList(salt)),
      "schema": "resident-address-v1",
    };
  }
}
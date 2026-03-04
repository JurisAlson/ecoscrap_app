import 'dart:convert';
import 'dart:typed_data';

import 'kyc_shared_key.dart';
import '../security/kyc_cyrpto.dart';
import 'admin_keys.dart'; // ADMIN APP ONLY

class ResidentAddressDecrypt {
  static Future<String> decrypt({
    required String uid,
    required Map<String, dynamic> data,
  }) async {
    final ct = base64Decode(data["ctB64"] as String);
    final nonce = base64Decode(data["nonceB64"] as String);
    final macBytes = base64Decode(data["macB64"] as String);
    final ephPub = base64Decode(data["ephPubKeyB64"] as String);
    final salt = base64Decode(data["saltB64"] as String);

    final key = await KycSharedKey.deriveForAdmin(
      adminPrivateKeyB64: AdminKeys.adminPrivateKeyB64,
      collectorEphemeralPubKeyBytes: Uint8List.fromList(ephPub),
      salt: Uint8List.fromList(salt),
    );

    final plainBytes = await KycCrypto.decryptBytes(
      cipherText: Uint8List.fromList(ct),
      macBytes: Uint8List.fromList(macBytes),
      nonce: Uint8List.fromList(nonce),
      key: key,
      aad: utf8.encode("resident-address-v1:$uid"),
    );

    return utf8.decode(plainBytes);
  }
}
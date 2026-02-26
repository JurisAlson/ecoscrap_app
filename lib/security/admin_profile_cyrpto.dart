import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

import 'admin_profile_key.dart';
import '../security/kyc_cyrpto.dart';

class AdminProfileCrypto {
  static SecretKey _key() => KycCrypto.keyFromB64(AdminProfileKey.aesKeyB64);

  /// Encrypt UTF-8 string -> {ct, nonce, mac} (all base64)
  static Future<Map<String, String>> encryptString(String value) async {
    final plain = Uint8List.fromList(utf8.encode(value));
    final nonce = KycCrypto.randomNonce12();

    final enc = await KycCrypto.encryptBytes(
      plain: plain,
      key: _key(),
      nonce12: nonce,
      aad: utf8.encode("admin-profile-v1"),
    );

    return {
      "ct": base64Encode(enc.cipherText),
      "nonce": base64Encode(enc.nonce),
      "mac": base64Encode(enc.macBytes),
    };
  }
}
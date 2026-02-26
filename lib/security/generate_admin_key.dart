import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

String generateAes256KeyB64() {
  final r = Random.secure();
  final bytes = Uint8List.fromList(
    List<int>.generate(32, (_) => r.nextInt(256)),
  );
  return base64Encode(bytes);
}

void main() {
  final key = generateAes256KeyB64();
  print("\n=== ADMIN AES-256 KEY (BASE64) ===");
  print(key);
  print("=== SAVE THIS IN admin_profile_key.dart ===\n");
}
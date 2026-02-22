import 'package:firebase_storage/firebase_storage.dart';

class AdminStorageCache {
  static final Map<String, Future<String>> _cache = {};

  static Future<String> url(String path) {
    return _cache.putIfAbsent(path, () => FirebaseStorage.instance.ref(path).getDownloadURL());
  }
}
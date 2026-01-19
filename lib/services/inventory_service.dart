import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InventoryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception("No user logged in.");
    return uid;
  }

  /// Path: junkshops/{uid}/inventory/{itemId}
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('junkshops').doc(_uid).collection('inventory');

  Stream<QuerySnapshot<Map<String, dynamic>>> watchInventory() {
    return _col.orderBy('updatedAt', descending: true).snapshots();
  }

  Future<void> addItem({
    required String name,
    required String category,
    String? subCategory,
    required double quantityKg,
    required double pricePerKg,
    String? notes,
  }) async {
    await _col.add({
      'name': name.trim(),
      'category': category.trim(),
      'subCategory': (subCategory ?? '').trim(),
      'quantityKg': quantityKg,
      'pricePerKg': pricePerKg,
      'notes': (notes ?? '').trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateItem(
    String docId, {
    required String name,
    required String category,
    String? subCategory,
    required double quantityKg,
    required double pricePerKg,
    String? notes,
  }) async {
    await _col.doc(docId).update({
      'name': name.trim(),
      'category': category.trim(),
      'subCategory': (subCategory ?? '').trim(),
      'quantityKg': quantityKg,
      'pricePerKg': pricePerKg,
      'notes': (notes ?? '').trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteItem(String docId) async {
    await _col.doc(docId).delete();
  }
}

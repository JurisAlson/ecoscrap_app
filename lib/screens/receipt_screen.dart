import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum TransactionType { buy, sell }

// ---------------- FIXED TAXONOMY ----------------
const kCategories = <String>[
  "PP White",
  "HDPE",
  "Black",
  "PP Colored",
  "PET",
];

const kSubCategories = <String>[
  "Plastic Bottles",
  "Water Gallon",
  "Tupperware",
  "Containers",
  "Mixed Plastic",
];

// Deterministic inventory doc id so we never need to query
String inventoryDocIdFor(String category, String subCategory) {
  String norm(String s) => s
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return "${norm(category)}__${norm(subCategory)}";
}

class ReceiptScreen extends StatefulWidget {
  final String shopID;

  const ReceiptScreen({super.key, required this.shopID});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  final TextEditingController _customerCtrl = TextEditingController();
  final List<_ReceiptItem> _items = [];

  TransactionType _type = TransactionType.buy;
  bool _saving = false;

  double get _totalAmount {
    double total = 0;
    for (final i in _items) {
      total += i.subtotal;
    }
    return total;
  }

  void _addItem() => setState(() => _items.add(_ReceiptItem()));

  void _removeItem(int index) => setState(() {
        _items[index].dispose();
        _items.removeAt(index);
      });

  @override
  void dispose() {
    _customerCtrl.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  // ✅ Fixed picker for Category + Subcategory (no Firestore dependency)
  Future<void> _pickFixedItem(_ReceiptItem item) async {
    final picked = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _FixedItemPickerSheet(),
    );

    if (picked == null) return;

    setState(() {
      item.category = picked['category']!;
      item.subCategory = picked['subCategory']!;
      item.displayName = "${item.category} • ${item.subCategory}";
    });
  }

  Future<void> _saveReceipt() async {
    if (_saving) return;

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add at least 1 item.")),
      );
      return;
    }

    final itemsPayload = <Map<String, dynamic>>[];

    for (final it in _items) {
      if (it.category == null || it.subCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select Category + Subcategory for each line.")),
        );
        return;
      }

      // NOTE: must be numeric only (no ₱, no commas)
      final weightKg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;
      final subtotal = double.tryParse(it.subtotalCtrl.text.trim()) ?? 0.0;

      if (weightKg <= 0 || subtotal <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Weight and subtotal must be greater than 0.")),
        );
        return;
      }

      final category = it.category!;
      final subCategory = it.subCategory!;
      final invId = inventoryDocIdFor(category, subCategory);

      itemsPayload.add({
        'inventoryDocId': invId, // ✅ deterministic
        'itemName': it.displayName, // display label
        'category': category,
        'subCategory': subCategory,

        'weightKg': weightKg,
        'subtotal': subtotal,

        // ✅ display-safe duplicates (in case encryption overwrites plaintext)
        'weightKgDisplay': weightKg,
        'subtotalDisplay': subtotal,
      });
    }

    final customerName = _customerCtrl.text.trim();

    setState(() => _saving = true);

    try {
      final db = FirebaseFirestore.instance;
      final shopRef = db.collection('Junkshop').doc(widget.shopID);
      final txRef = shopRef.collection('transaction').doc();

      await db.runTransaction((trx) async {
        // 1) Update/create inventory
        for (final item in itemsPayload) {
          final invId = (item['inventoryDocId'] as String);
          final category = (item['category'] as String);
          final subCategory = (item['subCategory'] as String);
          final weightKg = (item['weightKg'] as num).toDouble();

          final delta = _type == TransactionType.buy ? weightKg : -weightKg;

          final invRef = shopRef.collection('inventory').doc(invId);
          final invSnap = await trx.get(invRef);

          if (!invSnap.exists) {
            if (_type == TransactionType.sell) {
              throw Exception("No stock yet for $category • $subCategory. Use BUY first.");
            }

            trx.set(invRef, {
              'name': "$category • $subCategory",
              'category': category,
              'subCategory': subCategory,
              'notes': '',
              'unitsKg': 0.0,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }

          final currentKg = invSnap.exists
              ? ((invSnap.data()?['unitsKg'] as num?)?.toDouble() ?? 0.0)
              : 0.0;

          final nextKg = currentKg + delta;

          if (nextKg < 0) {
            throw Exception("Not enough stock for $category • $subCategory (current: $currentKg kg)");
          }

          trx.set(invRef, {
            'unitsKg': nextKg,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        // 2) Write transaction
        trx.set(txRef, {
          'type': _type.name,
          'customerName': customerName,

          // ✅ display-safe duplicates
          'customerNameDisplay': customerName,
          'totalAmount': _totalAmount,
          'totalAmountDisplay': _totalAmount,

          'items': itemsPayload,
          'transactionDate': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'inventoryDeducted': true,
          'inventoryDeductedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Saved (${_type.name.toUpperCase()}) ✅")),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Save failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: const Text("New Receipt"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _glassCard(
              child: Row(
                children: [
                  Expanded(
                    child: _typeChip(
                      label: "BUY (adds stock)",
                      active: _type == TransactionType.buy,
                      onTap: () => setState(() => _type = TransactionType.buy),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _typeChip(
                      label: "SELL (minus stock)",
                      active: _type == TransactionType.sell,
                      onTap: () => setState(() => _type = TransactionType.sell),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            _glassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label("Customer Name"),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customerCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration("Enter customer name"),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Items",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add, color: Colors.green),
                  label: const Text("Add Item", style: TextStyle(color: Colors.green)),
                ),
              ],
            ),

            const SizedBox(height: 8),

            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;

              final pickedLabel = (item.category == null || item.subCategory == null)
                  ? "Select Item"
                  : item.displayName;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _glassCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label("Item"),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _pickFixedItem(item),
                                    icon: const Icon(Icons.inventory_2, color: Colors.white),
                                    label: Text(
                                      pickedLabel,
                                      style: const TextStyle(color: Colors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      backgroundColor: Colors.black.withOpacity(0.2),
                                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => _removeItem(index),
                            icon: const Icon(Icons.close, color: Colors.red),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _textField(
                              controller: item.weightCtrl,
                              label: "Weight (kg)",
                              hint: "10",
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              controller: item.subtotalCtrl,
                              label: "Subtotal (₱)",
                              hint: "200",
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 16),

            _glassCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Total Amount",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "₱${_totalAmount.toStringAsFixed(2)}",
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _saving ? null : _saveReceipt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  _saving ? "SAVING..." : "SAVE RECEIPT",
                  style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
              ),
            ),

            const SizedBox(height: 12),
            const Center(
              child: Text(
                "Transaction Date is saved automatically",
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== UI HELPERS =====
  Widget _typeChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: active ? primaryColor.withOpacity(0.22) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? primaryColor.withOpacity(0.65) : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B)),
      filled: true,
      fillColor: Colors.black.withOpacity(0.2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }
}

class _ReceiptItem {
  final TextEditingController weightCtrl = TextEditingController();
  final TextEditingController subtotalCtrl = TextEditingController();

  String? category;
  String? subCategory;
  String displayName = "";

  double get subtotal => double.tryParse(subtotalCtrl.text.trim()) ?? 0.0;

  void dispose() {
    weightCtrl.dispose();
    subtotalCtrl.dispose();
  }
}

class _FixedItemPickerSheet extends StatefulWidget {
  const _FixedItemPickerSheet();

  @override
  State<_FixedItemPickerSheet> createState() => _FixedItemPickerSheetState();
}

class _FixedItemPickerSheetState extends State<_FixedItemPickerSheet> {
  String _category = kCategories.first;
  String _sub = kSubCategories.first;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.55,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              "Select Category & Subcategory",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _category,
              dropdownColor: const Color(0xFF0F172A),
              items: kCategories
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, style: const TextStyle(color: Colors.white)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
              decoration: const InputDecoration(
                labelText: "Category",
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _sub,
              dropdownColor: const Color(0xFF0F172A),
              items: kSubCategories
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, style: const TextStyle(color: Colors.white)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _sub = v!),
              decoration: const InputDecoration(
                labelText: "Subcategory",
                labelStyle: TextStyle(color: Colors.white70),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context, {
                    'category': _category,
                    'subCategory': _sub,
                  });
                },
                child: const Text("SELECT"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
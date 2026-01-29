import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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

  Future<void> _pickInventoryItem(_ReceiptItem item) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _InventoryPickerSheet(shopID: widget.shopID),
    );

    if (picked == null) return;

    setState(() {
      item.inventoryDocId = picked['id'] as String;
      item.itemNameCtrl.text = (picked['name'] ?? '').toString();
      item.categorySnapshot = (picked['category'] ?? '').toString();
      item.subCategorySnapshot = (picked['subCategory'] ?? '').toString();
    });
  }

  Future<void> _saveReceipt() async {
  // Validate
  if (_items.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Add at least 1 item.")),
    );
    return;
  }

  final itemsPayload = <Map<String, dynamic>>[];

  for (final it in _items) {
    final name = it.itemNameCtrl.text.trim();
    final weightKg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;
    final subtotal = double.tryParse(it.subtotalCtrl.text.trim()) ?? 0.0;

    if (name.isEmpty || weightKg <= 0 || subtotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fill up item name, weight, and subtotal.")),
      );
      return;
    }

    itemsPayload.add({
      'itemName': name,
      'weightKg': weightKg,   // ✅ number
      'subtotal': subtotal,   // ✅ number
    });
  }

  final customerName = _customerCtrl.text.trim();

  try {
    await FirebaseFirestore.instance
        .collection('Junkshop')
        .doc(widget.shopID)
        .collection('transaction')
        .add({
      'customerName': customerName,
      'items': itemsPayload, // ✅ LIST, not MAP
      'totalAmount': _totalAmount, // ✅ number
      'transactionDate': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    Navigator.pop(context); // ✅ go back after saving
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Save failed: $e")),
    );
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
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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

              final pickedLabel = item.inventoryDocId == null
                  ? "Select Item"
                  : "${item.itemNameCtrl.text} • ${item.categorySnapshot ?? ''}";

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
                                    onPressed: () => _pickInventoryItem(item),
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
                              hint: "0.0",
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              controller: item.subtotalCtrl,
                              label: "Subtotal (₱)",
                              hint: "0.00",
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
                  const Text("Total Amount",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  Text(
                    "₱${_totalAmount.toStringAsFixed(2)}",
                    style: TextStyle(color: primaryColor, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _saveReceipt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text(
                  "SAVE RECEIPT",
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
                ),
              ),
            ),

            const SizedBox(height: 12),
            Center(
              child: Text(
                "Transaction Date is saved automatically",
                style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== UI HELPERS =====
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
      style: TextStyle(
        color: Colors.grey.shade400,
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
      hintStyle: TextStyle(color: Colors.grey.shade500),
      filled: true,
      fillColor: Colors.black.withOpacity(0.2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }
}

// ===== Receipt line item model =====
class _ReceiptItem {
  final TextEditingController itemNameCtrl = TextEditingController(); // display only
  final TextEditingController weightCtrl = TextEditingController();
  final TextEditingController subtotalCtrl = TextEditingController();

  String? inventoryDocId; // IMPORTANT: points to inventory doc
  String? categorySnapshot;
  String? subCategorySnapshot;

  double get weightKg => double.tryParse(weightCtrl.text.trim()) ?? 0.0;
  double get subtotal => double.tryParse(subtotalCtrl.text.trim()) ?? 0.0;

  void dispose() {
    itemNameCtrl.dispose();
    weightCtrl.dispose();
    subtotalCtrl.dispose();
  }
}

// ===== Bottom sheet inventory picker =====
class _InventoryPickerSheet extends StatefulWidget {
  final String shopID;
  const _InventoryPickerSheet({required this.shopID});

  @override
  State<_InventoryPickerSheet> createState() => _InventoryPickerSheetState();
}

class _InventoryPickerSheetState extends State<_InventoryPickerSheet> {
  String q = "";

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Search inventory...",
                hintStyle: TextStyle(color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Junkshop')
                  .doc(widget.shopID)
                  .collection('inventory')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data?.docs ?? [];

                final filtered = docs.where((d) {
                  if (q.isEmpty) return true;
                  final m = d.data() as Map<String, dynamic>;
                  final hay = [
                    (m['name'] ?? '').toString(),
                    (m['category'] ?? '').toString(),
                    (m['subCategory'] ?? '').toString(),
                  ].join(' ').toLowerCase();
                  return hay.contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text("No matching items", style: TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = filtered[i];
                    final m = d.data() as Map<String, dynamic>;

                    final name = (m['name'] ?? '').toString();
                    final category = (m['category'] ?? '').toString();
                    final subCategory = (m['subCategory'] ?? '').toString();
                    final unitsKg = (m['unitsKg'] as num?)?.toDouble() ?? 0.0;

                    return ListTile(
                      tileColor: Colors.white.withOpacity(0.06),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      title: Text(name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        "$category • $subCategory • ${unitsKg.toStringAsFixed(2)} kg",
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                      onTap: () {
                        Navigator.pop(context, {
                          'id': d.id,
                          'name': name,
                          'category': category,
                          'subCategory': subCategory,
                          'unitsKg': unitsKg,
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

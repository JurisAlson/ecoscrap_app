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

  String _txType = "sale"; // "sale" | "buy"

  final TextEditingController _customerCtrl = TextEditingController();
  final List<_ReceiptItem> _items = [];

  static const List<String> kBuyCategories = [
    "PP WHITE",
    "HDPE",
    "BLACK",
    "PP COLORED",
    "PET",
  ];

  static const List<String> kBuySubCategories = [
    "PLASTIC BOTTLE",
    "TUPPERWARE",
    "WATER GALLON",
    "MIXED PLASTICS",
    "CONTAINERS",
  ];

  double get _totalAmount {
    double total = 0;
    for (final i in _items) {
      total += i.subtotal;
    }
    return total;
  }

  void _addItem() => setState(() {
        final it = _ReceiptItem();
        if (_txType == "buy") {
          it.categoryValue = kBuyCategories.first;
          it.subCategoryValue = kBuySubCategories.first;
        }
        _items.add(it);
      });

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
      item.salePickedName = (picked['name'] ?? '').toString();
      item.categoryValue = (picked['category'] ?? '').toString();
      item.subCategoryValue = (picked['subCategory'] ?? '').toString();
    });
  }

  void _switchType(String next) {
    if (_txType == next) return;

    setState(() {
      _txType = next;

      for (final i in _items) {
        i.dispose();
      }
      _items.clear();
      _customerCtrl.clear();
    });
  }

  Widget _buildTypeButton(String type) {
    final isSelected = _txType == type.toLowerCase();

    return Expanded(
      child: GestureDetector(
        onTap: () => _switchType(type.toLowerCase()),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isSelected ? primaryColor.withOpacity(0.25) : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: Text(
            type,
            style: TextStyle(
              color: isSelected ? primaryColor : Colors.white70,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveReceipt() async {
    final isSale = _txType == "sale";

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add at least 1 item.")),
      );
      return;
    }

    final itemsPayload = <Map<String, dynamic>>[];

    for (final it in _items) {
      final weightKg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;
      final subtotal = double.tryParse(it.subtotalCtrl.text.trim()) ?? 0.0;

      if (weightKg <= 0 || subtotal <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Weight and amount must be greater than 0.")),
        );
        return;
      }

      if (isSale) {
        if (it.inventoryDocId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Please select an inventory item for each line.")),
          );
          return;
        }

        final name = (it.salePickedName ?? "").trim();

        itemsPayload.add({
          'inventoryDocId': it.inventoryDocId,
          'itemName': name,
          'category': it.categoryValue ?? '',
          'subCategory': it.subCategoryValue ?? '',
          'weightKg': weightKg,
          'subtotal': subtotal,
        });
      } else {
        // ✅ BUY payload (this is what you lost in your current code)
        final cat = (it.categoryValue ?? "").trim();
        final sub = (it.subCategoryValue ?? "").trim();

        if (cat.isEmpty || sub.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Select category and sub-category for BUY.")),
          );
          return;
        }

        final derivedName = "$cat • $sub";

        itemsPayload.add({
          'itemName': derivedName,
          'category': cat,
          'subCategory': sub,
          'weightKg': weightKg,
          'subtotal': subtotal,
        });
      }
    }

    final partyName = _customerCtrl.text.trim();

    try {
      await FirebaseFirestore.instance
          .collection('Junkshop')
          .doc(widget.shopID)
          .collection('transaction')
          .add({
        'transactionType': _txType,
        'customerName': partyName,
        'items': itemsPayload,
        'totalAmount': _totalAmount,
        'transactionDate': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Save failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSale = _txType == "sale";

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(isSale ? "New Sale Receipt" : "New Buy Receipt"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _glassCard(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.black.withOpacity(0.25),
                ),
                child: Row(
                  children: [
                    _buildTypeButton("SALE"),
                    _buildTypeButton("BUY"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            _glassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(isSale ? "Customer Name" : "Supplier / Source"),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customerCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                      isSale ? "Enter customer name" : "Enter supplier/source",
                    ),
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

              final pickedLabel = item.inventoryDocId == null
                  ? "Select Item"
                  : "${item.salePickedName ?? ''} • ${item.categoryValue ?? ''}";

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

                                if (isSale)
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

                                if (!isSale) ...[
                                  DropdownButtonFormField<String>(
                                    value: item.categoryValue ?? kBuyCategories.first,
                                    items: kBuyCategories
                                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                        .toList(),
                                    onChanged: (v) => setState(() => item.categoryValue = v),
                                    dropdownColor: const Color(0xFF0F172A),
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _dropdownDecoration("Category"),
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    value: item.subCategoryValue ?? kBuySubCategories.first,
                                    items: kBuySubCategories
                                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                        .toList(),
                                    onChanged: (v) => setState(() => item.subCategoryValue = v),
                                    dropdownColor: const Color(0xFF0F172A),
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _dropdownDecoration("Sub-category"),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => _removeItem(index),
                            icon: const Icon(Icons.close, color: Colors.red),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

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
                              label: isSale ? "Subtotal (₱)" : "Cost (₱)",
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
                  Text(
                    isSale ? "Total Amount" : "Total Cost",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                onPressed: _saveReceipt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  isSale ? "SAVE SALE RECEIPT" : "SAVE BUY RECEIPT",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
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

  InputDecoration _dropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
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

  String? inventoryDocId; // sale only
  String? salePickedName;

  String? categoryValue;
  String? subCategoryValue;

  double get subtotal => double.tryParse(subtotalCtrl.text.trim()) ?? 0.0;

  void dispose() {
    weightCtrl.dispose();
    subtotalCtrl.dispose();
  }
}

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
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
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
                        style: const TextStyle(color: Colors.grey),
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
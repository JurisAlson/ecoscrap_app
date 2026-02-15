import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum TransactionType { buy, sell }

// ---------------- FIXED TAXONOMY (BUY) ----------------
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

// Deterministic inventory doc id (BUY creates/updates same doc consistently)
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

  // ✅ BUY: fixed taxonomy picker
  Future<void> _pickBuyItem(_ReceiptItem item) async {
    final picked = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _FixedItemPickerSheet(),
    );

    if (picked == null) return;

    final category = picked['category']!;
    final subCategory = picked['subCategory']!;
    final invId = inventoryDocIdFor(category, subCategory);

    setState(() {
      item.inventoryDocId = invId;
      item.category = category;
      item.subCategory = subCategory;
      item.displayName = "$category • $subCategory";
      item.availableKg = 0.0; // not needed for BUY
    });
  }

  // ✅ SELL: pick from existing inventory docs, then ask kg + sold price
  Future<void> _pickSellItem(_ReceiptItem item) async {
    final selected = await showModalBottomSheet<_InventoryPick>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _InventoryPickerSheet(shopID: widget.shopID),
    );

    if (selected == null) return;

    final sellInputs = await _askSellInputs(
      title: selected.displayName,
      availableKg: selected.unitsKg,
    );
    if (sellInputs == null) return;

    setState(() {
      item.inventoryDocId = selected.docId;
      item.category = selected.category;
      item.subCategory = selected.subCategory;
      item.displayName = selected.displayName;
      item.availableKg = selected.unitsKg;

      item.weightCtrl.text = sellInputs.weightKg.toString();
      item.subtotalCtrl.text = sellInputs.subtotal.toString();
    });
  }

  // ✅ single entrypoint for the Select Item button
  Future<void> _pickItem(_ReceiptItem item) async {
    if (_type == TransactionType.buy) {
      await _pickBuyItem(item);
    } else {
      await _pickSellItem(item);
    }
  }

  Future<_SellInputs?> _askSellInputs({
    required String title,
    required double availableKg,
  }) async {
    final weightCtrl = TextEditingController();
    final subtotalCtrl = TextEditingController();

    _showError(String msg) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    return showDialog<_SellInputs>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Sell: $title"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Available: ${availableKg.toStringAsFixed(2)} kg"),
            const SizedBox(height: 12),
            TextField(
              controller: weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: "Weight to sell (kg)"),
            ),
            TextField(
              controller: subtotalCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: "Sold price (₱)"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final w = double.tryParse(weightCtrl.text.trim()) ?? 0.0;
              final s = double.tryParse(subtotalCtrl.text.trim()) ?? 0.0;

              if (w <= 0) {
                _showError("Weight must be greater than 0.");
                return;
              }
              if (s <= 0) {
                _showError("Sold price must be greater than 0.");
                return;
              }
              if (w > availableKg) {
                _showError("Not enough stock. Available: ${availableKg.toStringAsFixed(2)} kg");
                return;
              }

              Navigator.pop(context, _SellInputs(weightKg: w, subtotal: s));
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveReceipt() async {
    if (_saving) return;

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add at least 1 item.")),
      );
      return;
    }

    final customerName = _customerCtrl.text.trim();

    final itemsPayload = <Map<String, dynamic>>[];
    for (final it in _items) {
      if (it.inventoryDocId == null || it.category == null || it.subCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select an item for each line.")),
        );
        return;
      }

      final weightKg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;
      final subtotal = double.tryParse(it.subtotalCtrl.text.trim()) ?? 0.0;

      if (weightKg <= 0 || subtotal <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Weight and subtotal must be greater than 0.")),
        );
        return;
      }

      itemsPayload.add({
        // used for inventory write:
        'inventoryDocId': it.inventoryDocId,
        'category': it.category,
        'subCategory': it.subCategory,

        // receipt display:
        'itemName': it.displayName,
        'weightKg': weightKg,
        'subtotal': subtotal,

        // ✅ display-safe duplicates (survive encryption)
        'itemNameDisplay': it.displayName,
        'weightKgDisplay': weightKg,
        'subtotalDisplay': subtotal,
      });
    }

    setState(() => _saving = true);

    try {
      final db = FirebaseFirestore.instance;
      final shopRef = db.collection('Junkshop').doc(widget.shopID);
      final txRef = shopRef.collection('transaction').doc();

      await db.runTransaction((trx) async {
        // 1) Update inventory
        for (final item in itemsPayload) {
          final invId = (item['inventoryDocId'] as String);
          final category = (item['category'] as String);
          final subCategory = (item['subCategory'] as String);
          final weightKg = (item['weightKg'] as num).toDouble();

          final delta = _type == TransactionType.buy ? weightKg : -weightKg;

          final invRef = shopRef.collection('inventory').doc(invId);
          final invSnap = await trx.get(invRef);

          // If missing:
          // - BUY -> create
          // - SELL -> block (must exist)
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

          // SELL protection
          if (_type == TransactionType.sell) {
            final currentKg = invSnap.exists
                ? ((invSnap.data()?['unitsKg'] as num?)?.toDouble() ?? 0.0)
                : 0.0;
            if (currentKg + delta < 0) {
              throw Exception("Not enough stock for $category • $subCategory (current: $currentKg kg)");
            }
          }

          // ✅ safer inventory update
          trx.set(invRef, {
            'unitsKg': FieldValue.increment(delta),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        // 2) Write transaction
        trx.set(txRef, {
          'type': _type.name, // buy/sell

          'customerName': customerName,
          'totalAmount': _totalAmount,
          'items': itemsPayload,

          'transactionDate': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),

          // ✅ display-safe duplicates
          'customerNameDisplay': customerName,
          'totalAmountDisplay': _totalAmount,
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
                      label: "SELL (from inventory)",
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

              final pickedLabel = (item.inventoryDocId == null)
                  ? (_type == TransactionType.buy ? "Select item (BUY list)" : "Select item from Inventory")
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
                                    onPressed: () => _pickItem(item),
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
                                if (_type == TransactionType.sell && item.inventoryDocId != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      "Available: ${item.availableKg.toStringAsFixed(2)} kg",
                                      style: const TextStyle(color: Colors.white54, fontSize: 12),
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

// ===== Receipt line item model =====
class _ReceiptItem {
  final TextEditingController weightCtrl = TextEditingController();
  final TextEditingController subtotalCtrl = TextEditingController();

  String? inventoryDocId;
  String? category;
  String? subCategory;
  String displayName = "";
  double availableKg = 0.0;

  double get subtotal => double.tryParse(subtotalCtrl.text.trim()) ?? 0.0;

  void dispose() {
    weightCtrl.dispose();
    subtotalCtrl.dispose();
  }
}

class _SellInputs {
  final double weightKg;
  final double subtotal;
  _SellInputs({required this.weightKg, required this.subtotal});
}

// ===== Fixed picker sheet (BUY) =====
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

// ===== Inventory picker (SELL) =====
class _InventoryPick {
  final String docId;
  final String category;
  final String subCategory;
  final String displayName;
  final double unitsKg;

  _InventoryPick({
    required this.docId,
    required this.category,
    required this.subCategory,
    required this.displayName,
    required this.unitsKg,
  });
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
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Search inventory...",
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('Junkshop')
                    .doc(widget.shopID)
                    .collection('inventory')
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snap.data!.docs;

                  final filtered = docs.where((d) {
                    final data = d.data();
                    final name = (data['name'] ?? '').toString().toLowerCase();
                    final cat = (data['category'] ?? '').toString().toLowerCase();
                    final sub = (data['subCategory'] ?? '').toString().toLowerCase();
                    final units = (data['unitsKg'] as num?)?.toDouble() ?? 0.0;

                    // ✅ only show in-stock items for SELL
                    if (units <= 0) return false;

                    final hay = "$name $cat $sub $units";
                    return q.isEmpty || hay.contains(q);
                  }).toList();

                  if (filtered.isEmpty) {
                    return const Center(
                      child: Text("No items in stock", style: TextStyle(color: Colors.white54)),
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final doc = filtered[i];
                      final data = doc.data();

                      final category = (data['category'] ?? '').toString();
                      final subCategory = (data['subCategory'] ?? '').toString();
                      final name = (data['name'] ?? "$category • $subCategory").toString();
                      final unitsKg = (data['unitsKg'] as num?)?.toDouble() ?? 0.0;

                      final display = name.isNotEmpty ? name : "$category • $subCategory";

                      return ListTile(
                        tileColor: Colors.white.withOpacity(0.06),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        title: Text(display, style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          "${unitsKg.toStringAsFixed(2)} kg available",
                          style: const TextStyle(color: Colors.white54),
                        ),
                        onTap: () {
                          Navigator.pop(
                            context,
                            _InventoryPick(
                              docId: doc.id,
                              category: category,
                              subCategory: subCategory,
                              displayName: display,
                              unitsKg: unitsKg,
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
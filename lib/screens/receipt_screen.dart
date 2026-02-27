// ===================== receipt_screen.dart (UPDATED - with Resident/Collector searchable picker) =====================
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants/categories.dart';

class ReceiptScreen extends StatefulWidget {
  final String shopID;
  final String? prefillName; // ✅ ADD THIS

  const ReceiptScreen({
    super.key,
    required this.shopID,
    this.prefillName,
  });

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  
  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);
  final TextEditingController _walkInNameCtrl = TextEditingController();

  // ✅ prevents double-save/double-deduct
  bool _saving = false;

  // ✅ consistent lower-case everywhere
  String _txType = "sell"; // "sell" | "buy"

  // ✅ SELL branch dropdown values
  static const List<String> _sellBranches = [
    "Cabuyao Branch",
    "JMC Branch",
  ];
  String _selectedSellBranch = _sellBranches.first;

  // ✅ BUY source dropdown values (UPDATED: added Walk-in)
  static const List<String> _buySources = [
    "Walk-in",
    "Resident",
  ];
  String _selectedBuySource = _buySources.first;

  // ✅ BUY source name (resident/collector, optional for walk-in)
  final TextEditingController _sourceNameCtrl = TextEditingController();

  // ✅ Selected user document id (Resident/Collector) from Users collection
  String? _sourceUserId;

  // (kept) for older uses, but BUY now uses _sourceNameCtrl for the label/name
  final TextEditingController _customerCtrl = TextEditingController();

  final List<_ReceiptItem> _items = [];

  double get _totalAmount => _items.fold(0.0, (sum, it) => sum + it.subtotal);

  // ✅ robust walk-in check (handles "walk in", "walk-in", "walkin", etc.)
  bool get _isWalkInBuy {
    final v = _selectedBuySource.trim().toLowerCase();
    return v == "walkin" || v == "walk-in" || v == "walk in" || v == "walk_in";
  }

  // ===================== PRICE HELPERS =====================
  void _recalcBuyItem(_ReceiptItem it) {
    if (_txType != "buy") return;

    final cat = (it.categoryValue ?? kMajorCategories.first).trim();
    final kg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;

    final costPerKg = kFixedBuyCostPerKg[cat] ?? 0.0;
    it.buyCostPerKg = costPerKg;

    final totalCost = kg * costPerKg;
    it.subtotalCtrl.text = totalCost.toStringAsFixed(2);
  }

  void _recalcSellItem(_ReceiptItem it) {
    if (_txType != "sell") return;

    final cat = (it.categoryValue ?? kMajorCategories.first).trim();
    final kg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;

    final sellPerKg = kFixedSellPricePerKg[cat] ?? 0.0;
    it.sellPricePerKg = sellPerKg;

    final sellTotal = kg * sellPerKg;
    it.subtotalCtrl.text = sellTotal.toStringAsFixed(2);
  }

  void _addItem() => setState(() {
        final it = _ReceiptItem();

        if (_txType == "buy") {
          it.categoryValue = kMajorCategories.first;
          it.subCategoryValue = kBuySubCategories.first;
          _recalcBuyItem(it);
        }

        _items.add(it);
      });

  void _removeItem(int index) => setState(() {
        _items[index].dispose();
        _items.removeAt(index);
      });

  @override
  void initState() {
    super.initState();

    if (widget.prefillName != null && widget.prefillName!.isNotEmpty) {
      _txType = "buy";
      _selectedBuySource = "Resident";

      _sourceNameCtrl.text = widget.prefillName!;

      // optional safety
      _sourceUserId = null;
    }
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _sourceNameCtrl.dispose();
    _walkInNameCtrl.dispose();
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
      item.sellPickedName = (picked['name'] ?? '').toString();
      item.categoryValue = (picked['category'] ?? '').toString();
      item.subCategoryValue = (picked['subCategory'] ?? '').toString();

      // Optional: don’t auto-fill weight; keep what user typed
      // item.weightCtrl.text = "";

      _recalcSellItem(item);
    });
  }

  void _switchType(String next) {
    if (_txType == next) return;
    setState(() {
      _txType = next;

      // ✅ reset party field depending on type
      if (_txType == "sell") {
        _selectedSellBranch = _sellBranches.first;
        _customerCtrl.clear();

        _selectedBuySource = _buySources.first;
        _sourceNameCtrl.clear();
        _sourceUserId = null;
      } else {
        _customerCtrl.clear();

        _selectedBuySource = _buySources.first;
        _sourceNameCtrl.clear();
        _sourceUserId = null;
      }

      for (final i in _items) {
        i.dispose();
      }
      _items.clear();
    });
  }

  Widget _buildTypeButton(String label, String value) {
    final isSelected = _txType == value;

    return Expanded(
      child: GestureDetector(
        onTap: () => _switchType(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isSelected ? primaryColor.withOpacity(0.25) : Colors.transparent,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
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

  // ✅ find existing inventory doc for BUY (query OUTSIDE transaction)
  Future<String?> _findInventoryDocIdForBuy(String cat, String sub) async {
    final snap = await FirebaseFirestore.instance
        .collection('Users')
        .doc(widget.shopID)
        .collection('inventory')
        .where('category', isEqualTo: cat)
        .where('subCategory', isEqualTo: sub)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  // ===================== SAVE (SELL deduct, BUY add) =====================
  Future<void> _saveReceipt() async {
    if (_saving) return; // ✅ prevent double-save
    _saving = true;
    if (mounted) setState(() {});

    final isSell = _txType == "sell";

    try {
      if (_items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Add at least 1 item.")),
        );
        return;
      }

      // ✅ BUY supports Walk-in with NO name required
      final isWalkIn = (!isSell && _isWalkInBuy);

      final sourceType = isSell
          ? ""
          : (isWalkIn ? "walkin" : _selectedBuySource.trim().toLowerCase()); // walkin|resident|collector

      final residentName = _sourceNameCtrl.text.trim();
      final walkInName = _walkInNameCtrl.text.trim();

      final sourceName = isSell ? "" : (isWalkIn ? walkInName : residentName);

      final partyName = isSell
          ? _selectedSellBranch
          : (isWalkIn ? (walkInName.isEmpty ? "Walk-in" : walkInName) : residentName);

      // ✅ only require name when NOT walk-in
      if (!isSell && isWalkIn) {
      if (walkInName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Enter walk-in name.")),
        );
        return;
      }
    } else if (!isSell && !isWalkIn) {
      if (residentName.isEmpty || _sourceUserId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Select the resident.")),
        );
        return;
      }
    }

      // validate + compute total weight
      double totalWeightKg = 0.0;

      for (final it in _items) {
        final kg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;
        if (kg <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Weight must be greater than 0.")),
          );
          return;
        }
        totalWeightKg += kg;

        if (isSell && it.inventoryDocId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Select an inventory item for each SELL line.")),
          );
          return;
        }
      }

      // ✅ prevent duplicate inventory selection in SELL (double-deduct)
      if (isSell) {
        final ids = _items.map((it) => it.inventoryDocId).whereType<String>().toList();
        if (ids.toSet().length != ids.length) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("You selected the same inventory item more than once.")),
          );
          return;
        }
      }

      // ✅ show what will be saved (helps debug)
      for (final it in _items) {
        // ignore: avoid_print
        print("ITEM LINE → doc=${it.inventoryDocId} weight='${it.weightCtrl.text}' picked='${it.sellPickedName}'");
      }

      final db = FirebaseFirestore.instance;
      final shopRef = db.collection('Users').doc(widget.shopID);
      final txCol = shopRef.collection('transaction');
      final invCol = shopRef.collection('inventory');

      // ✅ pre-fetch BUY merge targets outside transaction
      final Map<_ReceiptItem, String?> buyTargets = {};
      if (!isSell) {
        for (final it in _items) {
          final cat = (it.categoryValue ?? "").trim();
          final sub = (it.subCategoryValue ?? "").trim();
          buyTargets[it] = await _findInventoryDocIdForBuy(cat, sub);
        }
      }

      await db.runTransaction((trx) async {
        final txRef = txCol.doc();
        final itemsPayload = <Map<String, dynamic>>[];

        for (final it in _items) {
          final weightKg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;
          final cat = (it.categoryValue ?? "").trim();
          final sub = (it.subCategoryValue ?? "").trim();

          if (isSell) {
            final invRef = invCol.doc(it.inventoryDocId);
            final invSnap = await trx.get(invRef);

            if (!invSnap.exists) throw Exception("Inventory item not found.");

            final invData = invSnap.data() as Map<String, dynamic>;
            final currentKg = (invData['unitsKg'] as num?)?.toDouble() ?? 0.0;

            if (currentKg < weightKg) {
              final itemName = (invData['name'] ?? "Item").toString();
              throw Exception(
                "Not enough stock for $itemName. Available: ${currentKg.toStringAsFixed(2)} kg",
              );
            }

            // ✅ Debug before update
            // ignore: avoid_print
            print(
              "SELL DEBUG → doc=${it.inventoryDocId} "
              "picked=${it.sellPickedName} "
              "weightText='${it.weightCtrl.text}' "
              "weightKg=$weightKg "
              "currentKg=$currentKg "
              "newKg=${currentKg - weightKg}",
            );

            // ✅ SELL: deduct inventory
            /*trx.update(invRef, {
              'unitsKg': FieldValue.increment(-weightKg),
              'updatedAt': FieldValue.serverTimestamp(),
            });*/

            final sellPerKg = kFixedSellPricePerKg[cat] ?? 0.0;
            final buyCostPerKg = kFixedBuyCostPerKg[cat] ?? 0.0;

            final sellTotal = weightKg * sellPerKg;
            final costTotal = weightKg * buyCostPerKg;
            final profit = sellTotal - costTotal;

            itemsPayload.add({
              'inventoryDocId': it.inventoryDocId,
              'itemName': (it.sellPickedName ?? "").trim(),
              'category': cat,
              'subCategory': sub,
              'weightKg': weightKg,
              'sellPricePerKg': sellPerKg,
              'sellTotal': sellTotal,
              'costPerKg': buyCostPerKg,
              'costTotal': costTotal,
              'profit': profit,
              'subtotal': sellTotal,
            });
          } else {
            // ✅ BUY: add inventory (merge if found, else create)
            final targetId = buyTargets[it];

            if (targetId != null) {
              final existingRef = invCol.doc(targetId);
              trx.update(existingRef, {
                'unitsKg': FieldValue.increment(weightKg),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            } else {
              final newInvRef = invCol.doc();
              trx.set(newInvRef, {
                'name': "$cat • $sub",
                'category': cat,
                'subCategory': sub,
                'unitsKg': weightKg,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }

            final buyCostPerKg = kFixedBuyCostPerKg[cat] ?? 0.0;
            final costTotal = weightKg * buyCostPerKg;

            itemsPayload.add({
              'itemName': "$cat • $sub",
              'category': cat,
              'subCategory': sub,
              'weightKg': weightKg,
              'costPerKg': buyCostPerKg,
              'costTotal': costTotal,
              'subtotal': costTotal,
            });
          }
        }

        // ✅ SAVE TRANSACTION DOC
        final payload = <String, dynamic>{
          'transactionType': _txType, // "sell" | "buy"
          'customerName': partyName, // SELL: branch, BUY: Walk-in or selected name
          'items': itemsPayload,
          'totalAmount': _totalAmount,
          'totalWeightKg': totalWeightKg,
          'transactionDate': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        };

        if (!isSell) {
          payload['sourceType'] = sourceType; // walkin | resident | collector
          payload['sourceName'] = sourceName; // empty allowed for walk-in
          if (!isWalkIn) {
            payload['sourceUserId'] = _sourceUserId; // ✅ link to Users doc id
          }
        }

        trx.set(txRef, payload);
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Save failed: $e")),
      );
    } finally {
      _saving = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSell = _txType == "sell";

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(isSell ? "Transaction" : "Transaction"),
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
                    _buildTypeButton("SELL", "sell"),
                    _buildTypeButton("BUY", "buy"),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _glassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(isSell ? "Client" : "Source"),
                  const SizedBox(height: 8),

                  if (isSell)
                    DropdownButtonFormField<String>(
                      initialValue: _selectedSellBranch,
                      items: _sellBranches
                          .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _selectedSellBranch = v);
                      },
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Colors.white),
                      decoration: _dropdownDecoration(""),
                    )
                  else ...[
                    DropdownButtonFormField<String>(
                      initialValue: _selectedBuySource,
                      items: _buySources
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _selectedBuySource = v;

                          // reset fields when source changes
                          _sourceNameCtrl.clear();
                          _sourceUserId = null;
                          _walkInNameCtrl.clear();
                        });
                      },
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Colors.white),
                      decoration: _dropdownDecoration(""),
                    ),
                    const SizedBox(height: 10),

                    // ✅ Walk-in: manual name input (editable)
                    if (_isWalkInBuy)
                      TextField(
                        controller: _walkInNameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration("Enter walk-in name"),
                      )
                    else
                      // ✅ Resident: view-only bar (NOT clickable, no search/picker)
                      TextField(
                        controller: _sourceNameCtrl,
                        readOnly: true, // view-only
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration("Resident name").copyWith(
                          suffixIcon: null, // remove dropdown icon
                        ),
                      ),
                  ],
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
                  : "${item.sellPickedName ?? ''} • ${item.categoryValue ?? ''}";

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

                                if (isSell)
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

                                if (!isSell) ...[
                                  DropdownButtonFormField<String>(
                                    initialValue: item.categoryValue ?? kMajorCategories.first,
                                    items: kMajorCategories
                                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                        .toList(),
                                    onChanged: (v) => setState(() {
                                      item.categoryValue = v;
                                      _recalcBuyItem(item);
                                    }),
                                    dropdownColor: const Color(0xFF0F172A),
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _dropdownDecoration("Category"),
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    initialValue: item.subCategoryValue ?? kBuySubCategories.first,
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
                              onChanged: (_) => setState(() {
                                if (isSell) {
                                  _recalcSellItem(item);
                                } else {
                                  _recalcBuyItem(item);
                                }
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              controller: item.subtotalCtrl,
                              label: isSell ? "Subtotal (₱)" : "Cost (₱)",
                              hint: "0.00",
                              readOnly: true,
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
                    isSell ? "Total Amount" : "Total Cost",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
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
                onPressed: _saving ? null : _saveReceipt, // ✅ disabled while saving
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: Text(
                  _saving ? "SAVING..." : "SAVE RECEIPT",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
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
    bool readOnly = false,
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
          readOnly: readOnly,
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

  String? inventoryDocId; // sell only
  String? sellPickedName;

  String? categoryValue;
  String? subCategoryValue;

  double? buyCostPerKg;
  double? sellPricePerKg;

  double get subtotal => double.tryParse(subtotalCtrl.text.trim()) ?? 0.0;

  void dispose() {
    weightCtrl.dispose();
    subtotalCtrl.dispose();
  }
}

// ===================== USER PICKER (Resident/Collector) =====================
class _UserPickerSheet extends StatefulWidget {
  final String role; // "resident" | "collector"
  const _UserPickerSheet({required this.role});

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  String q = "";

  @override
  Widget build(BuildContext context) {
    final title = widget.role == "resident" ? "Select Resident" : "Select Collector";

    // ✅ MAP UI ROLE -> FIRESTORE ROLE VALUE
    final roleValue = widget.role == "resident" ? "Users" : "collector";

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
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 10),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Search name...",
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Users')
                  .where('role', isEqualTo: roleValue)
                   // ✅ Name field in your Firestore
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      "Error: ${snap.error}",
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data?.docs ?? [];

                final filtered = docs.where((d) {
                  if (q.isEmpty) return true;
                  final m = d.data() as Map<String, dynamic>;
                  final name = (m['Name'] ?? '').toString().toLowerCase();
                  return name.contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text("No matching users", style: TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = filtered[i];
                    final m = d.data() as Map<String, dynamic>;
                    final name = (m['Name'] ?? '').toString();

                    return ListTile(
                      tileColor: Colors.white.withOpacity(0.06),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      title: Text(name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(roleValue, style: const TextStyle(color: Colors.grey)),
                      onTap: () {
                        Navigator.pop(context, {
                          'id': d.id,
                          'name': name,
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

// ===================== INVENTORY PICKER =====================
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Users') // ✅ FIXED (was Junkshop)
                  .doc(widget.shopID) // ✅ FIXED
                  .collection('inventory')
                  .orderBy('updatedAt', descending: true) // ✅ safer than createdAt
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
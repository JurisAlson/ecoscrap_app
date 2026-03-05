import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'collector_plastics.dart';

class CollectorTransactionPage extends StatefulWidget {
  final String? requestId; // ✅ for BUY only (arrived pickup)
  final bool embedded; // if true, no Scaffold/AppBar

  const CollectorTransactionPage({
    super.key,
    this.requestId,
    this.embedded = false,
  });

  @override
  State<CollectorTransactionPage> createState() => _CollectorTransactionPageState();
}

class _CollectorTransactionPageState extends State<CollectorTransactionPage> {
  static const Color bgColor = Color(0xFF0F172A);
  static const Color primaryColor = Color(0xFF1FA9A7);

  

  int _tab = 1;

  @override
  void initState() {
    super.initState();
    _tab = (widget.requestId != null && widget.requestId!.trim().isNotEmpty) ? 0 : 1;
  }

  @override
  void didUpdateWidget(covariant CollectorTransactionPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final had = oldWidget.requestId != null && oldWidget.requestId!.trim().isNotEmpty;
    final has = widget.requestId != null && widget.requestId!.trim().isNotEmpty;

    if (had != has) {
      setState(() {
        _tab = has ? 0 : 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      children: [
        Positioned(
          top: -120,
          right: -120,
          child: _blurCircle(primaryColor.withOpacity(0.14), 320),
        ),
        Positioned(
          bottom: 80,
          left: -120,
          child: _blurCircle(Colors.green.withOpacity(0.10), 360),
        ),
        Column(
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _segmented(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _tab == 0
                    ? _BuyForm(key: const ValueKey("buy"), requestId: widget.requestId)
                    : const _SellForm(key: ValueKey("sell")),
              ),
            ),
          ],
        ),
      ],
    );

    if (widget.embedded) {
      // ✅ for bottom nav tab
      return SafeArea(child: content);
    }

    // ✅ for standalone push page
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text("Transaction"),
      ),
      body: content,
    );
  }

  Widget _segmented() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segBtn(
              label: "BUY",
              selected: _tab == 0,
              onTap: () => setState(() => _tab = 0),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _segBtn(
              label: "SELL",
              selected: _tab == 1,
              onTap: () => setState(() => _tab = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segBtn({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  static Widget _blurCircle(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(color: Colors.transparent),
      ),
    );
  }
}

/// ===============================================================
/// BUY FORM (needs requestId, same logic as your buy receipt)
/// ===============================================================
class _BuyForm extends StatefulWidget {
  final String? requestId;
  const _BuyForm({super.key, required this.requestId});

  @override
  State<_BuyForm> createState() => _BuyFormState();
}

class _BuyFormState extends State<_BuyForm> {
  static const Color bgColor = Color(0xFF0F172A);
  static const Color primaryColor = Color(0xFF1FA9A7);

  bool _saving = false;
  final List<_PlasticLineItem> _items = [];

  double get _totalKg =>
      _items.fold(0.0, (sum, it) => sum + (double.tryParse(it.kgCtrl.text.trim()) ?? 0.0));

  @override
  void dispose() {
    for (final it in _items) {
      it.dispose();
    }
    super.dispose();
  }

  void _addItem() {
    setState(() {
      _items.add(_PlasticLineItem(
        plasticKey: kCollectorPlasticTypes.first['key']!,
        label: kCollectorPlasticTypes.first['label']!,
      ));
    });
  }

  void _removeItem(int i) {
    setState(() {
      _items[i].dispose();
      _items.removeAt(i);
    });
  }

  Future<void> _saveBuyReceipt(Map<String, dynamic> requestData) async {
    if (_saving) return;

    final requestId = widget.requestId;
    if (requestId == null || requestId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Open BUY from an ARRIVED pickup to create a receipt.")),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add at least 1 item.")),
      );
      return;
    }

    for (final it in _items) {
      final kg = double.tryParse(it.kgCtrl.text.trim()) ?? 0.0;
      if (kg <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("All kg must be greater than 0.")),
        );
        return;
      }
    }

    final householdId = (requestData['householdId'] ?? requestData['residentId'] ?? "").toString();
    final householdName =
        (requestData['householdName'] ?? requestData['residentName'] ?? "Household").toString();

    final collectorId = user.uid;
    final collectorName = user.displayName ??
        (requestData['collectorName'] ?? requestData['collectorDisplayName'] ?? "Collector")
            .toString();

    if (householdId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing householdId in request document.")),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final db = FirebaseFirestore.instance;

      final reqRef = db.collection('requests').doc(requestId);
      final receiptRef = reqRef.collection('collector_receipts').doc();

      final itemsPayload = _items.map((it) {
        final kg = (double.tryParse(it.kgCtrl.text.trim()) ?? 0.0);
        return {"plasticKey": it.plasticKey, "label": it.label, "kg": kg};
      }).toList();

      final batch = db.batch();

      batch.set(receiptRef, {
        "kind": "collector_buy",
        "requestId": requestId,
        "collectorId": collectorId,
        "collectorName": collectorName,
        "householdId": householdId,
        "householdName": householdName,
        "items": itemsPayload,
        "totalKg": _totalKg,
        "createdAt": FieldValue.serverTimestamp(),
      });

      final invCol = db.collection('Users').doc(collectorId).collection('inventory_plastics');
      for (final it in _items) {
        final kg = (double.tryParse(it.kgCtrl.text.trim()) ?? 0.0);
        final invRef = invCol.doc(it.plasticKey);

        batch.set(invRef, {
          "plasticKey": it.plasticKey,
          "label": it.label,
          "unitsKg": FieldValue.increment(kg),
          "updatedAt": FieldValue.serverTimestamp(),
          "createdAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      batch.set(reqRef, {
        "hasCollectorReceipt": true,
        "collectorReceiptAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("BUY receipt saved + inventory updated.")),
      );
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
    final requestId = widget.requestId;
    if (requestId == null || requestId.trim().isEmpty) {
      return _empty(
        title: "No pickup selected",
        body: "Open BUY from the ARRIVED pickup screen to create a buying receipt.",
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('requests').doc(requestId).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || !snap.data!.exists) {
          return _empty(title: "Request not found", body: "The pickup request no longer exists.");
        }

        final data = snap.data!.data() as Map<String, dynamic>? ?? {};
        final householdName =
            (data['householdName'] ?? data['residentName'] ?? "Household").toString();
        final address = (data['pickupAddress'] ?? "").toString();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _glassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label("Household (auto-filled)"),
                    const SizedBox(height: 8),
                    Text(householdName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(address, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Plastics",
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add, color: Colors.green),
                    label: const Text("Add", style: TextStyle(color: Colors.green)),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              ..._items.asMap().entries.map((entry) {
                final i = entry.key;
                final it = entry.value;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _glassCard(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: it.plasticKey,
                                items: kCollectorPlasticTypes
                                    .map((m) => DropdownMenuItem(
                                          value: m['key']!,
                                          child: Text(m['label']!),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  final match = kCollectorPlasticTypes.firstWhere((m) => m['key'] == v);
                                  setState(() {
                                    it.plasticKey = v;
                                    it.label = match['label']!;
                                  });
                                },
                                dropdownColor: bgColor,
                                style: const TextStyle(color: Colors.white),
                                decoration: _dropdownDecoration("Plastic type"),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: _items.length == 1 ? null : () => _removeItem(i),
                              icon: const Icon(Icons.close, color: Colors.redAccent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: it.kgCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration("Kg (e.g. 2.5)"),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 10),

              _glassCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Total kg",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(
                      _totalKg.toStringAsFixed(2),
                      style: const TextStyle(
                        color: primaryColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _saving ? null : () => _saveBuyReceipt(data),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: Text(
                    _saving ? "SAVING..." : "SAVE BUY RECEIPT",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty({required String title, required String body}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _glassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Text(body, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            ],
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

class _PlasticLineItem {
  _PlasticLineItem({
    required this.plasticKey,
    required this.label,
  });

  String plasticKey;
  String label;

  final TextEditingController kgCtrl = TextEditingController();

  void dispose() => kgCtrl.dispose();
}

/// ===============================================================
/// SELL FORM (same logic as your sell_to_mores page)
/// ===============================================================
class _SellForm extends StatefulWidget {
  const _SellForm({super.key});

  @override
  State<_SellForm> createState() => _SellFormState();
}

class _SellFormState extends State<_SellForm> {
  static const Color bgColor = Color(0xFF0F172A);
  static const Color primaryColor = Color(0xFF1FA9A7);

  static const String moresUid = "07Wi7N8fALh2yqNdt1CQgIYVGE43";

  bool _saving = false;
  final List<_SellLineItem> _items = [];

  double get _totalKg =>
      _items.fold(0.0, (sum, it) => sum + (double.tryParse(it.kgCtrl.text.trim()) ?? 0.0));

  @override
  void initState() {
    super.initState();
    _addItem();
  }

  @override
  void dispose() {
    for (final it in _items) {
      it.dispose();
    }
    super.dispose();
  }

  void _addItem() {
    setState(() {
      _items.add(_SellLineItem(
        plasticKey: kCollectorPlasticTypes.first['key']!,
        label: kCollectorPlasticTypes.first['label']!,
      ));
    });
  }

  void _removeItem(int i) {
    setState(() {
      _items[i].dispose();
      _items.removeAt(i);
    });
  }

  Future<void> _submitSell() async {
    if (_saving) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add at least 1 item.")),
      );
      return;
    }

    for (final it in _items) {
      final kg = double.tryParse(it.kgCtrl.text.trim()) ?? 0.0;
      if (kg <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("All kg must be greater than 0.")),
        );
        return;
      }
    }

    final collectorId = user.uid;
    final collectorName = user.displayName ?? "Collector";

    setState(() => _saving = true);

    try {
      final db = FirebaseFirestore.instance;

      final moresSellRef = db.collection('Users').doc(moresUid).collection('sell_requests').doc();

      final itemsPayload = _items.map((it) {
        final kg = (double.tryParse(it.kgCtrl.text.trim()) ?? 0.0);
        return {"plasticKey": it.plasticKey, "label": it.label, "kg": kg};
      }).toList();

      await db.runTransaction((trx) async {
        final invCol = db.collection('Users').doc(collectorId).collection('inventory_plastics');

        // verify
        for (final it in _items) {
          final kg = double.tryParse(it.kgCtrl.text.trim()) ?? 0.0;
          final invRef = invCol.doc(it.plasticKey);
          final invSnap = await trx.get(invRef);

          final currentKg = invSnap.exists
              ? ((invSnap.data() as Map<String, dynamic>)['unitsKg'] as num?)?.toDouble() ?? 0.0
              : 0.0;

          if (currentKg < kg) {
            throw Exception("Not enough stock for ${it.label}. Available: ${currentKg.toStringAsFixed(2)} kg");
          }
        }

        // deduct
        for (final it in _items) {
          final kg = double.tryParse(it.kgCtrl.text.trim()) ?? 0.0;
          trx.update(invCol.doc(it.plasticKey), {
            "unitsKg": FieldValue.increment(-kg),
            "updatedAt": FieldValue.serverTimestamp(),
          });
        }

        // create sell request (pending)
        trx.set(moresSellRef, {
          "kind": "collector_sell_to_junkshop",
          "status": "pending",
          "junkshopUid": moresUid,

          "sourceType": "collector",
          "collectorId": collectorId,
          "collectorName": collectorName,

          "items": itemsPayload,
          "totalKg": _totalKg,

          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sell request sent to Mores Scrap.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Submit failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = FirebaseAuth.instance.currentUser?.displayName ?? "Collector";

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _glassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label("Collector (auto-filled)"),
                const SizedBox(height: 8),
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text("Source type: collector",
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Items to sell",
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add, color: Colors.green),
                label: const Text("Add", style: TextStyle(color: Colors.green)),
              ),
            ],
          ),
          const SizedBox(height: 8),

          ..._items.asMap().entries.map((entry) {
            final i = entry.key;
            final it = entry.value;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _glassCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: it.plasticKey,
                            items: kCollectorPlasticTypes
                                .map((m) => DropdownMenuItem(
                                      value: m['key']!,
                                      child: Text(m['label']!),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              final match = kCollectorPlasticTypes.firstWhere((m) => m['key'] == v);
                              setState(() {
                                it.plasticKey = v;
                                it.label = match['label']!;
                              });
                            },
                            dropdownColor: bgColor,
                            style: const TextStyle(color: Colors.white),
                            decoration: _dropdownDecoration("Plastic type"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _items.length == 1 ? null : () => _removeItem(i),
                          icon: const Icon(Icons.close, color: Colors.redAccent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: it.kgCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration("Kg (e.g. 2.0)"),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 10),

          _glassCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total kg",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text(
                  _totalKg.toStringAsFixed(2),
                  style: const TextStyle(
                    color: primaryColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _saving ? null : _submitSell,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: Text(
                _saving ? "SENDING..." : "SEND TO MORES SCRAP",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),
          const Text(
            "Note: This deducts from your inventory immediately.",
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
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

class _SellLineItem {
  _SellLineItem({
    required this.plasticKey,
    required this.label,
  });

  String plasticKey;
  String label;

  final TextEditingController kgCtrl = TextEditingController();
  void dispose() => kgCtrl.dispose();
}
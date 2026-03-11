import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CollectorTransactionPage extends StatefulWidget {
  final String? requestId;
  final bool embedded;

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
      return SafeArea(child: content);
    }

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
/// BUY FORM
/// ===============================================================
class _BuyForm extends StatefulWidget {
  final String? requestId;
  const _BuyForm({super.key, required this.requestId});

  @override
  State<_BuyForm> createState() => _BuyFormState();
}

class _BuyFormState extends State<_BuyForm> {
  static const Color primaryColor = Color(0xFF1FA9A7);
  static const double buyPricePerKg = 5.0;

  bool _saving = false;

  Future<void> _saveBuyReceipt(Map<String, dynamic> requestData) async {
    if (_saving) return;

    final requestId = widget.requestId;
    if (requestId == null || requestId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Open BUY from an ARRIVED pickup.")),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final alreadyReceipted = requestData['hasCollectorReceipt'] == true;
    if (alreadyReceipted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Receipt already saved for this pickup.")),
      );
      return;
    }

    final bagKg = ((requestData['bagKg'] as num?) ?? 0).toDouble();
    final bagKey = (requestData['bagKey'] ?? "").toString();
    final bagLabel = (requestData['bagLabel'] ?? "Bag").toString();

    if (bagKg <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing or invalid bagKg in request.")),
      );
      return;
    }

    final householdId = (requestData['householdId'] ?? "").toString();
    final householdName = (requestData['householdName'] ?? "Household").toString();

    if (householdId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing householdId in request document.")),
      );
      return;
    }

    final collectorId = user.uid;
    final collectorName =
        user.displayName ?? (requestData['collectorName'] ?? "Collector").toString();

    final totalAmount = bagKg * buyPricePerKg;

    setState(() => _saving = true);

    try {
      final db = FirebaseFirestore.instance;

      final reqRef = db.collection('requests').doc(requestId);
      final receiptRef = reqRef.collection('collector_receipts').doc();
      final inventoryRef =
          db.collection('Users').doc(collectorId).collection('inventory').doc('summary');
      final txnRef =
          db.collection('Users').doc(collectorId).collection('transactions').doc();

      await db.runTransaction((trx) async {
        final reqSnap = await trx.get(reqRef);
        if (!reqSnap.exists) {
          throw Exception("Request not found.");
        }

        trx.set(receiptRef, {
          "kind": "collector_buy",
          "requestId": requestId,
          "collectorId": collectorId,
          "collectorName": collectorName,
          "householdId": householdId,
          "householdName": householdName,
          "bagKey": bagKey,
          "bagLabel": bagLabel,
          "kg": bagKg,
          "pricePerKg": buyPricePerKg,
          "totalAmount": totalAmount,
          "status": "completed",
          "createdAt": FieldValue.serverTimestamp(),
        });

        trx.set(txnRef, {
          "kind": "buy",
          "requestId": requestId,
          "householdId": householdId,
          "householdName": householdName,
          "bagKey": bagKey,
          "bagLabel": bagLabel,
          "kg": bagKg,
          "pricePerKg": buyPricePerKg,
          "totalAmount": totalAmount,
          "createdAt": FieldValue.serverTimestamp(),
        });

        trx.set(
          inventoryRef,
          {
            "totalKg": FieldValue.increment(bagKg),
            "totalValueSpent": FieldValue.increment(totalAmount),
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        trx.set(
          reqRef,
          {
            "hasCollectorReceipt": true,
            "collectorReceiptAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Buy receipt saved and inventory updated.")),
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
        body: "Open BUY from the ARRIVED pickup screen to create a receipt.",
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('requests').doc(requestId).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snap.hasData || !snap.data!.exists) {
          return _empty(
            title: "Request not found",
            body: "The pickup request no longer exists.",
          );
        }

        final data = snap.data!.data() as Map<String, dynamic>? ?? {};

        final householdName = (data['householdName'] ?? "Household").toString();
        final address = (data['fullAddress'] ?? data['pickupAddress'] ?? "").toString();
        final bagLabel = (data['bagLabel'] ?? "Bag").toString();
        final bagKg = ((data['bagKg'] as num?) ?? 0).toDouble();
        final collectorName =
            (data['collectorName'] ?? FirebaseAuth.instance.currentUser?.displayName ?? "Collector")
                .toString();
        final alreadyReceipted = data['hasCollectorReceipt'] == true;

        final totalAmount = bagKg * buyPricePerKg;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _glassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label("Household"),
                    const SizedBox(height: 8),
                    Text(
                      householdName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        address,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _glassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label("Collector"),
                    const SizedBox(height: 8),
                    Text(
                      collectorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Weight is locked based on the household bag size selection.",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _glassCard(
                child: Column(
                  children: [
                    _infoRow("Bag size", bagLabel),
                    const SizedBox(height: 10),
                    _infoRow("Locked weight", "${bagKg.toStringAsFixed(2)} kg"),
                    const SizedBox(height: 10),
                    _infoRow("Price per kg", "₱${buyPricePerKg.toStringAsFixed(2)}"),
                    const SizedBox(height: 10),
                    _infoRow(
                      "Total payment",
                      "₱${totalAmount.toStringAsFixed(2)}",
                      highlight: true,
                    ),
                  ],
                ),
              ),
              if (alreadyReceipted) ...[
                const SizedBox(height: 12),
                _glassCard(
                  child: Row(
                    children: const [
                      Icon(Icons.check_circle, color: Colors.greenAccent),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Receipt already saved for this pickup.",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_saving || alreadyReceipted || bagKg <= 0)
                      ? null
                      : () => _saveBuyReceipt(data),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    disabledBackgroundColor: Colors.white24,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    _saving
                        ? "SAVING..."
                        : alreadyReceipted
                            ? "RECEIPT ALREADY SAVED"
                            : "SAVE BUY RECEIPT",
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

  Widget _infoRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        Text(
          value,
          style: TextStyle(
            color: highlight ? primaryColor : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: highlight ? 16 : 14,
          ),
        ),
      ],
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
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
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
}

/// ===============================================================
/// SELL FORM
/// ===============================================================
class _SellForm extends StatefulWidget {
  const _SellForm({super.key});

  @override
  State<_SellForm> createState() => _SellFormState();
}

class _SellFormState extends State<_SellForm> {
  static const Color primaryColor = Color(0xFF1FA9A7);

  static const String moresUid = "07Wi7N8fALh2yqNdt1CQgIYVGE43";

  final TextEditingController _kgCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _kgCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitSell(double currentKg) async {
    if (_saving) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final sellKg = double.tryParse(_kgCtrl.text.trim()) ?? 0.0;
    if (sellKg <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid kg.")),
      );
      return;
    }

    if (sellKg > currentKg) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Not enough inventory.")),
      );
      return;
    }

    final collectorId = user.uid;
    final collectorName = user.displayName ?? "Collector";

    setState(() => _saving = true);

    try {
      final db = FirebaseFirestore.instance;

      final sellReqRef = db
          .collection('Users')
          .doc(moresUid)
          .collection('sell_requests')
          .doc();

      final txnRef = db
          .collection('Users')
          .doc(collectorId)
          .collection('transactions')
          .doc();

      await db.runTransaction((trx) async {
        final inventoryRef = db
            .collection('Users')
            .doc(collectorId)
            .collection('inventory')
            .doc('summary');

        final invSnap = await trx.get(inventoryRef);
        final latestKg = invSnap.exists
            ? (((invSnap.data() as Map<String, dynamic>)['totalKg'] as num?) ?? 0)
                .toDouble()
            : 0.0;

        if (latestKg < sellKg) {
          throw Exception(
            "Not enough stock. Available: ${latestKg.toStringAsFixed(2)} kg",
          );
        }

        // deduct collector inventory immediately
        trx.set(
          inventoryRef,
          {
            "totalKg": FieldValue.increment(-sellKg),
            "updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        // create notification/request for junkshop
        trx.set(sellReqRef, {
          "kind": "collector_sell_to_junkshop",
          "type": "sell",
          "status": "pending",
          "seen": false,
          "junkshopUid": moresUid,
          "junkshopName": "Mores Scrap",
          "sourceType": "collector",
          "collectorId": collectorId,
          "collectorName": collectorName,
          "kg": sellKg,
          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        });

        // local transaction history
        trx.set(txnRef, {
          "kind": "sell_request",
          "status": "pending",
          "junkshopUid": moresUid,
          "junkshopName": "Mores Scrap",
          "kg": sellKg,
          "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        });
      });

      _kgCtrl.clear();

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

  Future<void> _confirmAndSubmitSell(double currentKg) async {
    final sellKg = double.tryParse(_kgCtrl.text.trim()) ?? 0.0;

    if (sellKg <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid kg.")),
      );
      return;
    }

    if (sellKg > currentKg) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Not enough inventory.")),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            "Confirm Sell Request",
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            "You are about to send ${sellKg.toStringAsFixed(2)} kg to Mores Scrap.\n\nThis will deduct the amount from your inventory immediately.",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1FA9A7),
              ),
              child: const Text(
                "Confirm",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      await _submitSell(currentKg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final collectorId = user?.uid;

    if (collectorId == null) {
      return const Center(
        child: Text("Not signed in", style: TextStyle(color: Colors.white)),
      );
    }

    final inventoryStream = FirebaseFirestore.instance
        .collection('Users')
        .doc(collectorId)
        .collection('inventory')
        .doc('summary')
        .snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: inventoryStream,
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};
        final totalKg = ((data['totalKg'] as num?) ?? 0).toDouble();
        final collectorName = user?.displayName ?? "Collector";

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _glassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label("Collector"),
                    const SizedBox(height: 8),
                    Text(
                      collectorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "Inventory is now tracked as total kilograms only.",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              _glassCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Available inventory",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "${totalKg.toStringAsFixed(2)} kg",
                      style: const TextStyle(
                        color: primaryColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              _glassCard(
                child: TextField(
                  controller: _kgCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration("Kg to sell to Mores Scrap"),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _saving ? null : () => _confirmAndSubmitSell(totalKg),
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
                "Note: This deducts from your total inventory immediately.",
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        );
      },
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
}
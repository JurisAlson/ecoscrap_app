import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'collector_tracking_page.dart';

class CollectorTransactionPage extends StatefulWidget {
  final String? requestId;
  final bool embedded;

  const CollectorTransactionPage({
    super.key,
    this.requestId,
    this.embedded = false,
  });

  @override
  State<CollectorTransactionPage> createState() =>
      _CollectorTransactionPageState();
}

class _CollectorTransactionPageState extends State<CollectorTransactionPage> {
  static const Color bgColor = Color(0xFF0F172A);
  static const Color primaryColor = Color(0xFF1FA9A7);

  int _tab = 1;

  @override
  void initState() {
    super.initState();
    _tab =
        (widget.requestId != null && widget.requestId!.trim().isNotEmpty) ? 0 : 1;
  }

  @override
  void didUpdateWidget(covariant CollectorTransactionPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final had =
        oldWidget.requestId != null && oldWidget.requestId!.trim().isNotEmpty;
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
          child: _TransactionUi.blurCircle(
            primaryColor.withOpacity(0.14),
            320,
          ),
        ),
        Positioned(
          bottom: 80,
          left: -120,
          child: _TransactionUi.blurCircle(
            Colors.green.withOpacity(0.10),
            360,
          ),
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
                    ? _BuyForm(
                        key: const ValueKey("buy"),
                        requestId: widget.requestId,
                      )
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
              label: "COLLECTED",
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
}

/// ===============================================================
/// SHARED UI HELPERS
/// ===============================================================
class _TransactionUi {
  static Widget blurCircle(Color color, double size) {
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

  static Widget glassCard({required Widget child}) {
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

  static InputDecoration inputDecoration(String hint) {
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

  static String pickupAddress(Map<String, dynamic> data) {
    return (data['fullAddress'] ?? data['pickupAddress'] ?? "").toString();
  }

  static String collectorName({
    User? user,
    Map<String, dynamic>? requestData,
    String fallback = "Collector",
  }) {
    return user?.displayName ??
        (requestData?['collectorName'] ?? fallback).toString();
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

  static const int _historyItemsPerPage = 5;
  int _historyPage = 0;

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
    final householdName =
        (requestData['householdName'] ?? "Household").toString();

    if (householdId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Missing householdId in request document."),
        ),
      );
      return;
    }

    final collectorId = user.uid;
    final collectorName = _TransactionUi.collectorName(
      user: user,
      requestData: requestData,
    );

    final totalAmount = bagKg * buyPricePerKg;

    setState(() => _saving = true);

    try {
      final db = FirebaseFirestore.instance;

      final reqRef = db.collection('requests').doc(requestId);
      final receiptRef = reqRef.collection('collector_receipts').doc();
      final inventoryRef = db
          .collection('Users')
          .doc(collectorId)
          .collection('inventory')
          .doc('summary');
      final txnRef = db
          .collection('Users')
          .doc(collectorId)
          .collection('transactions')
          .doc();

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
    final hasRequest = requestId != null && requestId.trim().isNotEmpty;

    final collectorId = FirebaseAuth.instance.currentUser?.uid;
    if (collectorId == null) {
      return _empty(
        title: "Not signed in",
        body: "Please sign in to continue.",
      );
    }

    final historyStream = FirebaseFirestore.instance
        .collection('Users')
        .doc(collectorId)
        .collection('transactions')
        .where('kind', isEqualTo: 'buy')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();

    if (!hasRequest) {
      return StreamBuilder<QuerySnapshot>(
        stream: historyStream,
        builder: (context, historySnap) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                _historySection(historySnap),
              ],
            ),
          );
        },
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .snapshots(),
      builder: (context, requestSnap) {
        if (requestSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!requestSnap.hasData || !requestSnap.data!.exists) {
          return _empty(
            title: "Request not found",
            body: "The pickup request no longer exists.",
          );
        }

        final data = requestSnap.data!.data() as Map<String, dynamic>? ?? {};

        final householdName = (data['householdName'] ?? "Household").toString();
        final address = _TransactionUi.pickupAddress(data);
        final bagLabel = (data['bagLabel'] ?? "Bag").toString();
        final bagKg = ((data['bagKg'] as num?) ?? 0).toDouble();
        final collectorName = _TransactionUi.collectorName(
          user: FirebaseAuth.instance.currentUser,
          requestData: data,
        );
        final alreadyReceipted = data['hasCollectorReceipt'] == true;
        final totalAmount = bagKg * buyPricePerKg;

        return StreamBuilder<QuerySnapshot>(
          stream: historyStream,
          builder: (context, historySnap) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TransactionUi.glassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.receipt_long_rounded,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Current Transaction",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    "Review the selected pickup before saving.",
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _sectionTitle("Household"),
                        const SizedBox(height: 8),
                        Text(
                          householdName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            address,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _sectionTitle("Collector"),
                        const SizedBox(height: 8),
                        Text(
                          collectorName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TransactionUi.glassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Payment Breakdown",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _infoRow("Bag size", bagLabel),
                        const SizedBox(height: 10),
                        _infoRow("Locked weight", "${bagKg.toStringAsFixed(2)} kg"),
                        const SizedBox(height: 10),
                        _infoRow(
                          "Price per kg",
                          "₱${buyPricePerKg.toStringAsFixed(2)}",
                        ),
                        const Divider(color: Colors.white24, height: 22),
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
                    _TransactionUi.glassCard(
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
                                ? "TRANSACTION ALREADY SAVED"
                                : "SAVE TRANSACTION",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _historySection(historySnap),
                ],
              ),
            );
          },
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

  Widget _sectionTitle(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _historyCard({
    required String householdName,
    required String bagLabel,
    required double kg,
    required double pricePerKg,
    required double totalAmount,
    required Timestamp? createdAt,
  }) {
    return _TransactionUi.glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.shopping_bag_rounded,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      householdName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(createdAt),
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.greenAccent.withOpacity(0.18),
                  ),
                ),
                child: const Text(
                  "PAID",
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              children: [
                _infoRow("Bag size", bagLabel),
                const SizedBox(height: 10),
                _infoRow("Weight", "${kg.toStringAsFixed(2)} kg"),
                const SizedBox(height: 10),
                _infoRow("Per kg", "₱${pricePerKg.toStringAsFixed(2)}"),
                const Divider(color: Colors.white24, height: 22),
                _infoRow(
                  "Total payment",
                  "₱${totalAmount.toStringAsFixed(2)}",
                  highlight: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _historySection(AsyncSnapshot<QuerySnapshot> historySnap) {
    final historyDocs = historySnap.data?.docs ?? [];

    final totalItems = historyDocs.length;
    final totalPages = totalItems == 0
        ? 1
        : (totalItems / _historyItemsPerPage).ceil();

    if (_historyPage >= totalPages) {
      _historyPage = totalPages - 1;
    }
    if (_historyPage < 0) {
      _historyPage = 0;
    }

    final startIndex = _historyPage * _historyItemsPerPage;
    final endIndex = (startIndex + _historyItemsPerPage) > totalItems
        ? totalItems
        : (startIndex + _historyItemsPerPage);

    final pageDocs = totalItems == 0
        ? <QueryDocumentSnapshot>[]
        : historyDocs.sublist(startIndex, endIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.history_rounded, color: Colors.white70, size: 20),
            SizedBox(width: 8),
            Text(
              "Recent Collected History",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          "Your latest saved buy transactions.",
          style: TextStyle(
            color: Colors.white60,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        if (historySnap.connectionState == ConnectionState.waiting)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (historyDocs.isEmpty)
          _TransactionUi.glassCard(
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text(
                  "No transaction history yet.",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          )
        else ...[
          ...pageDocs.map((doc) {
            final item = doc.data() as Map<String, dynamic>;
            final household = (item['householdName'] ?? 'Household').toString();
            final bag = (item['bagLabel'] ?? 'Bag').toString();
            final kg = ((item['kg'] as num?) ?? 0).toDouble();
            final price = ((item['pricePerKg'] as num?) ?? 0).toDouble();
            final total = ((item['totalAmount'] as num?) ?? 0).toDouble();
            final createdAt = item['createdAt'] as Timestamp?;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _historyCard(
                householdName: household,
                bagLabel: bag,
                kg: kg,
                pricePerKg: price,
                totalAmount: total,
                createdAt: createdAt,
              ),
            );
          }),
          const SizedBox(height: 8),
          _buildHistoryPagination(totalPages),
        ],
      ],
    );
  }

  Widget _buildHistoryPagination(int totalPages) {
    if (totalPages <= 1) return const SizedBox.shrink();

    final pages = _visiblePages(totalPages, _historyPage);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _pageArrowButton(
          icon: Icons.chevron_left_rounded,
          enabled: _historyPage > 0,
          onTap: () {
            if (_historyPage > 0) {
              setState(() => _historyPage--);
            }
          },
        ),
        const SizedBox(width: 8),
        ...pages.map((pageIndex) {
          final isSelected = pageIndex == _historyPage;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _pageNumberButton(
              label: "${pageIndex + 1}",
              selected: isSelected,
              onTap: () => setState(() => _historyPage = pageIndex),
            ),
          );
        }),
        const SizedBox(width: 8),
        _pageArrowButton(
          icon: Icons.chevron_right_rounded,
          enabled: _historyPage < totalPages - 1,
          onTap: () {
            if (_historyPage < totalPages - 1) {
              setState(() => _historyPage++);
            }
          },
        ),
      ],
    );
  }

  List<int> _visiblePages(int totalPages, int currentPage) {
    if (totalPages <= 3) {
      return List.generate(totalPages, (i) => i);
    }

    if (currentPage <= 1) {
      return [0, 1, 2];
    }

    if (currentPage >= totalPages - 2) {
      return [totalPages - 3, totalPages - 2, totalPages - 1];
    }

    return [currentPage - 1, currentPage, currentPage + 1];
  }

  Widget _pageNumberButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? primaryColor : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primaryColor : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _pageArrowButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? Colors.white.withOpacity(0.06)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(
          icon,
          color: enabled ? Colors.white : Colors.white24,
        ),
      ),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "Date unavailable";

    final dt = timestamp.toDate();

    final months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ];

    final hour = dt.hour > 12
        ? dt.hour - 12
        : dt.hour == 0
            ? 12
            : dt.hour;

    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? "PM" : "AM";

    return "${months[dt.month - 1]} ${dt.day}, ${dt.year} • $hour:$minute $suffix";
  }

  Widget _empty({required String title, required String body}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _TransactionUi.glassCard(
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

  static const double moresLat = 14.198630;
  static const double moresLng = 121.117270;

  final TextEditingController _kgCtrl = TextEditingController();
  bool _saving = false;

    bool _isWithinMoresWorkingHours() {
    final now = DateTime.now();
    final hour = now.hour;

    // Allowed from 7:00 AM up to before 5:00 PM
    return hour >= 7 && hour < 17;
  }

  @override
  void dispose() {
    _kgCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitSell(double currentKg) async {
  if (_saving) return;

  if (!_isWithinMoresWorkingHours()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Mores Scrap only accepts sell transactions from 7:00 AM to 5:00 PM.",
        ),
      ),
    );
    return;
  }

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

    final activeStatuses = [
      "incoming",
      "accepted",
      "on_the_way",
      "arrived",
      "confirmed",
      "processing",
    ];

    final existingActive = await db
        .collection('Users')
        .doc(moresUid)
        .collection('sell_requests')
        .where('collectorId', isEqualTo: collectorId)
        .where('status', whereIn: activeStatuses)
        .limit(1)
        .get();

    if (existingActive.docs.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "You already have an active transaction with Mores Scrap. Finish or cancel it first.",
          ),
        ),
      );
      return;
    }

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

    final collectorRef = db.collection('Users').doc(collectorId);

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

      trx.set(sellReqRef, {
        "kind": "collector_sell_to_junkshop",
        "type": "sell",
        "status": "incoming",
        "seen": false,
        "junkshopUid": moresUid,
        "junkshopName": "Mores Scrap",
        "sourceType": "collector",
        "collectorId": collectorId,
        "collectorName": collectorName,
        "collectorTransactionId": txnRef.id,
        "kg": sellKg,
        "collectorArrived": false,
        "junkshopConfirmedArrival": false,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });

      trx.set(txnRef, {
        "kind": "sell_request",
        "status": "incoming",
        "sellRequestId": sellReqRef.id,
        "junkshopUid": moresUid,
        "junkshopName": "Mores Scrap",
        "kg": sellKg,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });

      trx.set(
        collectorRef,
        {
          "isOnline": true,
          "availabilityStatus": "busy_with_mores",
          "isAvailableForHousehold": false,
          "activeMoresSellRequestId": sellReqRef.id,
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    _kgCtrl.clear();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Sell request sent to Mores Scrap.")),
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CollectorTrackingPage(
          fixedDestination: const LatLng(moresLat, moresLng),
          destinationTitle: "Mores Scrap",
          destinationAddress: "Mores Scrap",
          trackingType: "sell",
          showChatButton: true,
          showCancelButton: true,
          showArrivedButton: true,
          sellRequestId: sellReqRef.id,
        ),
      ),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            "Confirm Sell Request",
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            "You are about to notify Mores Scrap that you are bringing ${sellKg.toStringAsFixed(2)} kg.\n\nYour inventory will only be deducted after arrival is confirmed and the receipt is processed.",
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

  final activeSellStream = FirebaseFirestore.instance
      .collection('Users')
      .doc(moresUid)
      .collection('sell_requests')
      .where('collectorId', isEqualTo: collectorId)
.where('status', whereIn: [
  'incoming',
  'accepted',
  'on_the_way',
  'arrived',
  'confirmed',
  'processing',
])
      .limit(1)
      .snapshots();

  return StreamBuilder<DocumentSnapshot>(
    stream: inventoryStream,
    builder: (context, inventorySnap) {
      final data = inventorySnap.data?.data() as Map<String, dynamic>? ?? {};
      final totalKg = ((data['totalKg'] as num?) ?? 0).toDouble();

      return StreamBuilder<QuerySnapshot>(
        stream: activeSellStream,
        builder: (context, activeSnap) {
          final hasActiveMoresTxn = activeSnap.data?.docs.isNotEmpty ?? false;
          final activeDoc = hasActiveMoresTxn ? activeSnap.data!.docs.first : null;
          final activeSellRequestId = activeDoc?.id;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),

                if (hasActiveMoresTxn) ...[
                  InkWell(
                    onTap: activeSellRequestId == null
                        ? null
                        : () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CollectorTrackingPage(
                                  fixedDestination: const LatLng(moresLat, moresLng),
                                  destinationTitle: "Mores Scrap",
                                  destinationAddress: "Mores Scrap",
                                  trackingType: "sell",
                                  showChatButton: true,
                                  showCancelButton: true,
                                  showArrivedButton: true,
                                  sellRequestId: activeSellRequestId,
                                ),
                              ),
                            );
                          },
                    borderRadius: BorderRadius.circular(18),
                    child: _TransactionUi.glassCard(
                      child: Row(
                        children: const [
                          Icon(Icons.map_rounded, color: Colors.orangeAccent),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "You already have an active transaction with Mores Scrap. Tap here to open the map.",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                _TransactionUi.glassCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Available inventory",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
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

                _TransactionUi.glassCard(
                  child: TextField(
                    controller: _kgCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    enabled: !hasActiveMoresTxn && !_saving,
                    decoration: _TransactionUi.inputDecoration(
                      "Kg to sell to Mores Scrap",
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _saving
                        ? null
                        : hasActiveMoresTxn
                            ? () async {
                                if (activeSellRequestId == null) return;

                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CollectorTrackingPage(
                                      fixedDestination: const LatLng(
                                        moresLat,
                                        moresLng,
                                      ),
                                      destinationTitle: "Mores Scrap",
                                      destinationAddress: "Mores Scrap",
                                      trackingType: "sell",
                                      showChatButton: true,
                                      showCancelButton: true,
                                      showArrivedButton: true,
                                      sellRequestId: activeSellRequestId,
                                    ),
                                  ),
                                );
                              }
                            : () => _confirmAndSubmitSell(totalKg),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      disabledBackgroundColor: Colors.white24,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      _saving
                          ? "SENDING..."
                          : hasActiveMoresTxn
                              ? "OPEN ACTIVE TRANSACTION"
                              : "SEND TO MORES SCRAP",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),
                Text(
                  hasActiveMoresTxn
                      ? "You already have an active trip to Mores Scrap. Open it to continue tracking."
                      : "Note: This will notify Mores Scrap of your intent to sell.",
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}}
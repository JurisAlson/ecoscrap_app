import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'receipt_screen.dart';

import 'TransactionDetailScreen.dart';

class TransactionScreen extends StatefulWidget {
  final String shopID;
  const TransactionScreen({super.key, required this.shopID});

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  static const Color bgColor = Color(0xFF0F172A);
  static const Color primaryColor = Color(0xFF1FA9A7);

  String _txType = "sale"; // "sale" | "buy"
  String _q = ""; // search query (name only)

  void _switchType(String next) {
    if (_txType == next) return;
    setState(() => _txType = next);
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

  Widget _buildTypeButton(String label) {
    final value = label.toLowerCase(); // "sale" | "buy"
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

  String _formatDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return "$y-$m-$day  $hh:$mm";
  }

  InputDecoration _searchDecoration() {
    return InputDecoration(
      hintText: "Search by name...",
      hintStyle: const TextStyle(color: Color(0xFF64748B)),
      prefixIcon: const Icon(Icons.search, color: Colors.white70),
      filled: true,
      fillColor: Colors.black.withOpacity(0.20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSale = _txType == "sale";

    // ✅ No composite index needed: orderBy only
    final txStream = FirebaseFirestore.instance
        .collection('Junkshop')
        .doc(widget.shopID)
        .collection('transaction')
        .orderBy('transactionDate', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: const Text("Transactions", style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ReceiptScreen(shopID: widget.shopID)),
          );
        },
        backgroundColor: Colors.greenAccent,
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text("NEW RECEIPT", style: TextStyle(color: Colors.black)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ✅ SALE / BUY toggle
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
            const SizedBox(height: 12),

            // ✅ Search bar (name only)
            _glassCard(
              child: TextField(
                style: const TextStyle(color: Colors.white),
                decoration: _searchDecoration(),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 14),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: txStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        "Error: ${snapshot.error}",
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    );
                  }

                  final allDocs = snapshot.data?.docs ?? [];

                  // ✅ Filter by type + name (client-side)
                  final docs = allDocs.where((d) {
                    final data = d.data() as Map<String, dynamic>;

                    final t = (data['transactionType'] ?? '').toString().toLowerCase();
                    if (t != _txType) return false;

                    if (_q.isEmpty) return true;

                    final name = (data['customerNameDisplay'] ??
                            data['customerName'] ??
                            '')
                        .toString()
                        .toLowerCase();

                    return name.contains(_q);
                  }).toList();

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        _q.isNotEmpty
                            ? "No matching results"
                            : (isSale ? "No sale transactions yet" : "No buy transactions yet"),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;

                      final partyName = (data['customerNameDisplay'] ??
                              data['customerName'] ??
                              '')
                          .toString()
                          .trim();

                      final total = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;

                      final ts = data['transactionDate'] as Timestamp?;
                      final date = ts?.toDate();

                      // ✅ Total KG (use stored totalWeightKg, fallback to summing items)
                      double totalKg = (data['totalWeightKg'] as num?)?.toDouble() ?? -1;
                      if (totalKg < 0) {
                        final items = (data['items'] as List<dynamic>?) ?? [];
                        totalKg = 0.0;
                        for (final item in items) {
                          final m = item as Map<String, dynamic>;
                          totalKg += (m['weightKg'] as num?)?.toDouble() ?? 0.0;
                        }
                      }

                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TransactionDetailScreen(
                                transactionData: data,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: ListTile(
                            title: Text(
                              partyName.isEmpty
                                  ? (isSale
                                      ? "Walk-in customer"
                                      : "Unknown supplier/source")
                                  : partyName,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  date != null ? _formatDate(date) : '',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${totalKg.toStringAsFixed(2)} kg ${isSale ? "sold" : "bought"}",
                                  style: TextStyle(
                                    color: isSale ? Colors.greenAccent : Colors.orangeAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Text(
                              "₱${total.toStringAsFixed(2)}",
                              style: TextStyle(
                                color: isSale ? Colors.greenAccent : Colors.orangeAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
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
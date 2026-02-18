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
  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  String _txType = "sale";
  String _q = "";

  void _switchType(String next) {
    if (_txType == next) return;
    setState(() => _txType = next);
  }

  Widget _blurCircle(
    Color color,
    double size, {
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child, EdgeInsets? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding ?? const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildTypeButton(String label) {
    final value = label.toLowerCase();
    final isSelected = _txType == value;

    return Expanded(
      child: GestureDetector(
        onTap: () => _switchType(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isSelected ? primaryColor.withOpacity(0.18) : Colors.transparent,
          ),
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
    return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}  "
        "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
  }

  InputDecoration _searchDecoration() {
    return InputDecoration(
      hintText: "Search by name...",
      hintStyle: const TextStyle(color: Color(0xFF64748B)),
      prefixIcon: const Icon(Icons.search, color: Colors.white70),
      filled: true,
      fillColor: Colors.black.withOpacity(0.25),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSale = _txType == "sale";

    final txStream = FirebaseFirestore.instance
        .collection('Junkshop')
        .doc(widget.shopID)
        .collection('transaction')
        .orderBy('transactionDate', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: bgColor,

      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        elevation: 0,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          "NEW RECEIPT",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReceiptScreen(shopID: widget.shopID),
            ),
          );
        },
      ),

      body: Stack(
        children: [
          _blurCircle(primaryColor.withOpacity(0.15), 300, top: -100, right: -100),
          _blurCircle(Colors.green.withOpacity(0.1), 350, bottom: 100, left: -100),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                children: [
                  const SizedBox(height: 18),

                  // ✅ Search bar (top)
                  _glassCard(
                    child: TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: _searchDecoration(),
                      onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ✅ Toggle
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

                  const SizedBox(height: 14),

                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: txStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final docs = (snapshot.data?.docs ?? []).where((d) {
                          final data = d.data() as Map<String, dynamic>;

                          final type = (data['transactionType'] ?? '')
                              .toString()
                              .toLowerCase();
                          if (type != _txType) return false;

                          if (_q.isEmpty) return true;

                          final name = (data['customerNameDisplay'] ??
                                  data['customerName'] ??
                                  '')
                              .toString()
                              .toLowerCase();

                          return name.contains(_q);
                        }).toList();

                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              "No transactions found",
                              style: TextStyle(color: Colors.grey),
                            ),
                          );
                        }

                        return ListView.separated(
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final data = docs[index].data() as Map<String, dynamic>;

                            final name = (data['customerNameDisplay'] ??
                                    data['customerName'] ??
                                    "Unknown")
                                .toString();

                            final total =
                                (data['totalAmount'] as num?)?.toDouble() ?? 0.0;

                            final ts = data['transactionDate'] as Timestamp?;
                            final date = ts?.toDate();

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withOpacity(0.06)),
                              ),
                              child: ListTile(
                                title: Text(name, style: const TextStyle(color: Colors.white)),
                                subtitle: Text(
                                  date != null ? _formatDate(date) : "",
                                  style: const TextStyle(color: Colors.white54),
                                ),
                                trailing: Text(
                                  "₱${total.toStringAsFixed(2)}",
                                  style: TextStyle(
                                    color: isSale ? Colors.greenAccent : Colors.orangeAccent,
                                    fontWeight: FontWeight.bold,
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
          ),
        ],
      ),
    );
  }
}

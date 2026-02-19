// ===================== transaction_screen.dart =====================
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'receipt_screen.dart';
import 'transactiondetailscreen.dart'; // make sure filename matches EXACTLY

class TransactionScreen extends StatefulWidget {
  final String shopID;
  const TransactionScreen({super.key, required this.shopID});

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  String _txType = "sell"; // must match firestore value: "sell" or "buy"
  String _q = "";
  DateTimeRange? _dateRange; // null = no date filter

  void _switchType(String next) {
    if (_txType == next) return;
    setState(() => _txType = next);
  }

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(14),
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

  String _titleCase(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1).toLowerCase();
  }

  String _displayPartyName(Map<String, dynamic> data) {
    final type = (data['transactionType'] ?? '').toString().toLowerCase();

    if (type == "sell") {
      final name = (data['customerNameDisplay'] ?? data['customerName'] ?? "Unknown")
          .toString()
          .trim();
      return name.isEmpty ? "Walk-in customer" : name;
    }

    // BUY => use sourceType/sourceName if present
    final sourceType = (data['sourceType'] ?? '').toString().trim().toLowerCase(); // walkin/resident/collector
    final sourceName = (data['sourceName'] ?? '').toString().trim();

    if (sourceType == "walkin") {
      return sourceName.isEmpty ? "Walk-in" : "Walk-in • $sourceName";
    }

    if (sourceType.isNotEmpty) {
      final pretty = _titleCase(sourceType);
      if (sourceName.isNotEmpty) return "$pretty • $sourceName";
      return pretty;
    }

    // fallback for old data
    final old = (data['customerNameDisplay'] ?? data['customerName'] ?? "Unknown")
        .toString()
        .trim();
    return old.isEmpty ? "Unknown source" : old;
  }

  @override
  Widget build(BuildContext context) {
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            children: [
              _glassCard(
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Search by name or transaction ID...",
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.25),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _dateRange == null ? Icons.calendar_month : Icons.event_available,
                        color: Colors.white70,
                      ),
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          initialDateRange: _dateRange,
                          builder: (context, child) {
                            return Theme(
                              data: ThemeData.dark().copyWith(
                                scaffoldBackgroundColor: const Color(0xFF0F172A),
                                dialogBackgroundColor: const Color(0xFF0F172A),
                                colorScheme: const ColorScheme.dark(
                                  primary: Color(0xFF1FA9A7),
                                  onPrimary: Colors.white,
                                  surface: Color(0xFF0F172A),
                                  onSurface: Colors.white,
                                ),
                                textButtonTheme: TextButtonThemeData(
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF1FA9A7),
                                  ),
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );

                        if (picked != null) {
                          setState(() => _dateRange = picked);
                        }
                      },
                      tooltip: _dateRange == null ? "Filter by date" : "Change date filter",
                    ),
                  ),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                ),
              ),

              const SizedBox(height: 12),

              _glassCard(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.black.withOpacity(0.25),
                  ),
                  child: Row(
                    children: [
                      _buildTypeButton("SELL"),
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

                      final type = (data['transactionType'] ?? '').toString().toLowerCase();
                      if (type != _txType) return false;

                      if (_dateRange != null) {
                        final ts = data['transactionDate'] as Timestamp?;
                        final date = ts?.toDate();
                        if (date == null) return false;

                        final start = DateTime(_dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day);
                        final end = DateTime(_dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day, 23, 59, 59, 999);

                        if (date.isBefore(start) || date.isAfter(end)) return false;
                      }

                      if (_q.isEmpty) return true;

                      final receiptId = d.id.toLowerCase();
                      final displayName = _displayPartyName(data).toLowerCase();
                      final hay = "$displayName $receiptId";
                      return hay.contains(_q);
                    }).toList();

                    if (docs.isEmpty) {
                      return const Center(
                        child: Text("No transactions found", style: TextStyle(color: Colors.grey)),
                      );
                    }

                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data() as Map<String, dynamic>;

                        final type = (data['transactionType'] ?? '').toString().toLowerCase();
                        final isSale = type == 'sell';

                        final name = _displayPartyName(data);

                        final total = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;

                        final ts = data['transactionDate'] as Timestamp?;
                        final date = ts?.toDate();

                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: ListTile(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TransactionDetailScreen(
                                    shopID: widget.shopID,
                                    transactionData: {
                                      ...data,
                                      'receiptId': doc.id,
                                    },
                                  ),
                                ),
                              );
                            },
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
    );
  }
}
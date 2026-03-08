// ===================== transaction_screen.dart =====================
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'receipt_screen.dart' as receipt;
import 'transactiondetailscreen.dart';

class TransactionScreen extends StatefulWidget {
  final String shopID;
  const TransactionScreen({super.key, required this.shopID});

  @override
  State<TransactionScreen> createState() => _TransactionScreenState();
}

class _TransactionScreenState extends State<TransactionScreen> {
  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  String _txType = "sell";
  String _q = "";
  DateTimeRange? _dateRange;

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
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.055),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildTypeButton(String label) {
    final value = label == "SOLD" ? "sell" : "buy";
    final isSelected = _txType == value;

    return Expanded(
      child: GestureDetector(
        onTap: () => _switchType(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isSelected ? primaryColor.withOpacity(0.22) : Colors.transparent,
            border: Border.all(
              color: isSelected
                  ? primaryColor.withOpacity(0.45)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
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

    final sourceType = (data['sourceType'] ?? '').toString().trim().toLowerCase();
    final sourceName = (data['sourceName'] ?? '').toString().trim();

    if (sourceType == "walkin") {
      return sourceName.isEmpty ? "Walk-in" : "Walk-in • $sourceName";
    }

    if (sourceType.isNotEmpty) {
      final pretty = _titleCase(sourceType);
      if (sourceName.isNotEmpty) return "$pretty • $sourceName";
      return pretty;
    }

    final old = (data['customerNameDisplay'] ?? data['customerName'] ?? "Unknown")
        .toString()
        .trim();
    return old.isEmpty ? "Unknown source" : old;
  }

  String _dateFilterLabel() {
    if (_dateRange == null) return "All dates";
    final start = _dateRange!.start;
    final end = _dateRange!.end;
    return "${start.month}/${start.day}/${start.year} - ${end.month}/${end.day}/${end.year}";
  }

  @override
  Widget build(BuildContext context) {
    final txStream = FirebaseFirestore.instance
        .collection('Users')
        .doc(widget.shopID)
        .collection('transaction')
        .orderBy('transactionDate', descending: true)
        .snapshots();

    return Scaffold(
      backgroundColor: bgColor,
      floatingActionButton: FloatingActionButton(
        backgroundColor: primaryColor,
        elevation: 2,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => receipt.ReceiptScreen(
                shopID: widget.shopID,
                initialTransactionType: _txType,
              ),
            ),
          );
        },
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
      body: Stack(
        children: [
          _blurCircle(
            primaryColor.withOpacity(0.15),
            300,
            top: -100,
            right: -100,
          ),
          _blurCircle(
            Colors.green.withOpacity(0.10),
            340,
            bottom: 80,
            left: -120,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  const Text(
                    "View and manage collected and sold logs",
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _glassCard(
                    child: TextField(
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: "Search by name...",
                        hintStyle: const TextStyle(color: Color(0xFF64748B)),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Colors.white70,
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_q.isNotEmpty)
                              IconButton(
                                onPressed: () {
                                  setState(() => _q = "");
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white54,
                                ),
                              ),
                            IconButton(
                              icon: Icon(
                                _dateRange == null
                                    ? Icons.calendar_month_rounded
                                    : Icons.event_available_rounded,
                                color: _dateRange == null
                                    ? Colors.white70
                                    : primaryColor,
                              ),
                              onPressed: () async {
                                final picked = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                  initialDateRange: _dateRange,
                                  builder: (context, child) {
                                    return Theme(
                                      data: ThemeData.dark().copyWith(
                                        scaffoldBackgroundColor:
                                            const Color(0xFF0F172A),
                                        colorScheme: const ColorScheme.dark(
                                          primary: Color(0xFF1FA9A7),
                                          onPrimary: Colors.white,
                                          surface: Color(0xFF0F172A),
                                          onSurface: Colors.white,
                                        ),
                                        textButtonTheme: TextButtonThemeData(
                                          style: TextButton.styleFrom(
                                            foregroundColor:
                                                const Color(0xFF1FA9A7),
                                          ),
                                        ),
                                        dialogTheme: const DialogThemeData(
                                          backgroundColor: Color(0xFF0F172A),
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
                              tooltip: _dateRange == null
                                  ? "Filter by date"
                                  : "Change date filter",
                            ),
                          ],
                        ),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 15,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: Colors.white.withOpacity(0.06),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: primaryColor.withOpacity(0.45),
                            width: 1.1,
                          ),
                        ),
                      ),
                      onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _glassCard(
                    padding: const EdgeInsets.all(6),
                    child: SizedBox(
                      height: 52,
                      child: Row(
                        children: [
                          _buildTypeButton("SOLD"),
                          _buildTypeButton("COLLECTED"),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dateFilterLabel(),
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_dateRange != null)
                        TextButton(
                          onPressed: () => setState(() => _dateRange = null),
                          child: const Text(
                            "Clear filter",
                            style: TextStyle(
                              color: Color(0xFF1FA9A7),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: txStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docs = (snapshot.data?.docs ?? []).where((d) {
                          final data = d.data() as Map<String, dynamic>;

                          final type = (data['transactionType'] ?? '')
                              .toString()
                              .toLowerCase();
                          if (type != _txType) return false;

                          if (_dateRange != null) {
                            final ts = data['transactionDate'] as Timestamp?;
                            final date = ts?.toDate();
                            if (date == null) return false;

                            final start = DateTime(
                              _dateRange!.start.year,
                              _dateRange!.start.month,
                              _dateRange!.start.day,
                            );
                            final end = DateTime(
                              _dateRange!.end.year,
                              _dateRange!.end.month,
                              _dateRange!.end.day,
                              23,
                              59,
                              59,
                              999,
                            );

                            if (date.isBefore(start) || date.isAfter(end)) {
                              return false;
                            }
                          }

                          if (_q.isEmpty) return true;

                          final displayName = _displayPartyName(data).toLowerCase();
                          return displayName.contains(_q);
                        }).toList();

                        if (docs.isEmpty) {
                          return Center(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.receipt_long_outlined,
                                    size: 64,
                                    color: Color(0xFF64748B),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    _txType == "sell"
                                        ? "No sold transactions found"
                                        : "No collected transactions found",
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    "Try changing the search or date filter.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                "${docs.length} transaction${docs.length == 1 ? '' : 's'}",
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.separated(
                                padding: const EdgeInsets.only(bottom: 100),
                                itemCount: docs.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final doc = docs[index];
                                  final data = doc.data() as Map<String, dynamic>;

                                  final type = (data['transactionType'] ?? '')
                                      .toString()
                                      .toLowerCase();
                                  final isSale = type == 'sell';

                                  final sourceType = (data['sourceType'] ?? '')
                                      .toString()
                                      .toLowerCase();
                                  final isCollector = sourceType == 'collector';
                                  final isWalkIn = sourceType == 'walkin';

                                  final name = _displayPartyName(data);
                                  final total =
                                      (data['totalAmount'] as num?)?.toDouble() ??
                                          0.0;
                                  final ts = data['transactionDate'] as Timestamp?;
                                  final date = ts?.toDate();

                                  return Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.055),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.07),
                                      ),
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
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      leading: Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: isSale
                                              ? Colors.green.withOpacity(0.14)
                                              : isCollector
                                                  ? Colors.orange.withOpacity(0.14)
                                                  : Colors.blue.withOpacity(0.14),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Icon(
                                          isSale
                                              ? Icons.sell_rounded
                                              : isWalkIn
                                                  ? Icons.person_rounded
                                                  : Icons.shopping_cart_rounded,
                                          color: isSale
                                              ? Colors.greenAccent
                                              : isWalkIn
                                                  ? Colors.blueAccent
                                                  : Colors.orangeAccent,
                                        ),
                                      ),
                                      title: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14.5,
                                        ),
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          date != null ? _formatDate(date) : "",
                                          style: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      trailing: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSale
                                                  ? Colors.green.withOpacity(0.12)
                                                  : Colors.orange.withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              isSale ? "SOLD" : "COLLECTED",
                                              style: TextStyle(
                                                color: isSale
                                                    ? Colors.greenAccent
                                                    : Colors.orangeAccent,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "₱${total.toStringAsFixed(2)}",
                                            style: TextStyle(
                                              color: isSale
                                                  ? Colors.greenAccent
                                                  : Colors.orangeAccent,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
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
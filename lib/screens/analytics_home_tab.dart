import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants/categories.dart';

class AnalyticsHomeTab extends StatefulWidget {
  final String shopID;
  const AnalyticsHomeTab({super.key, required this.shopID});

  @override
  State<AnalyticsHomeTab> createState() => _AnalyticsHomeTabState();
}

class _AnalyticsHomeTabState extends State<AnalyticsHomeTab> {
  int _selectedMonth = DateTime.now().month;

  DateTime _monthStart(int month) {
    final now = DateTime.now();
    return DateTime(now.year, month, 1);
  }

  DateTime _monthEndExclusive(int month) {
    final now = DateTime.now();
    return DateTime(now.year, month + 1, 1);
  }

  Widget _buildMonthSelector() {
    const months = [
      "JAN","FEB","MAR","APR","MAY","JUN",
      "JUL","AUG","SEP","OCT","NOV","DEC"
    ];

    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 12,
        itemBuilder: (context, index) {
          final monthNumber = index + 1;
          final isSelected = monthNumber == _selectedMonth;

          return GestureDetector(
            onTap: () => setState(() => _selectedMonth = monthNumber),
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.greenAccent.withOpacity(0.2)
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? Colors.greenAccent
                      : Colors.white.withOpacity(0.1),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                months[index],
                style: TextStyle(
                  color: isSelected ? Colors.greenAccent : Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = _monthStart(_selectedMonth);
    final end = _monthEndExclusive(_selectedMonth);

    final txStream = FirebaseFirestore.instance
        .collection('Junkshop')
        .doc(widget.shopID)
        .collection('transaction')
        .where('transactionDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('transactionDate', isLessThan: Timestamp.fromDate(end))
        .orderBy('transactionDate', descending: true)
        .snapshots();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          _buildMonthSelector(),
          const SizedBox(height: 16),
          _sectionTitle("MONTHLY PROJECTION"),

          StreamBuilder<QuerySnapshot>(
            stream: txStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return _card(
                    child: const Center(child: CircularProgressIndicator()));
              }

              if (snap.hasError) {
                return _card(
                  child: Text(
                    "Error: ${snap.error}",
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                );
              }

              double revenue = 0;
              double cost = 0;
              double profit = 0;
              int salesCount = 0;

              final revByCat = {for (final c in kMajorCategories) c: 0.0};
              final profitByCat = {for (final c in kMajorCategories) c: 0.0};

              for (final doc in snap.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final type = (data['transactionType'] ?? '').toString();

                if (type != 'sale') continue;

                salesCount++;

                final items = (data['items'] as List<dynamic>?) ?? [];

                for (final raw in items) {
                  final it = raw as Map<String, dynamic>;
                  final cat = (it['category'] ?? '').toString();

                  final sellTotal =
                      (it['sellTotal'] as num?)?.toDouble() ?? 0.0;

                  final costTotal =
                      (it['costTotal'] as num?)?.toDouble() ?? 0.0;

                  final itemProfit =
                      (it['profit'] as num?)?.toDouble() ??
                          (sellTotal - costTotal);

                  revenue += sellTotal;
                  cost += costTotal;
                  profit += itemProfit;

                  if (revByCat.containsKey(cat)) {
                    revByCat[cat] = revByCat[cat]! + sellTotal;
                  }

                  if (profitByCat.containsKey(cat)) {
                    profitByCat[cat] = profitByCat[cat]! + itemProfit;
                  }
                }
              }

              return Column(
                children: [
                  _metricRow(
                    leftTitle: "Revenue",
                    leftValue: "₱${revenue.toStringAsFixed(2)}",
                    rightTitle: "Profit",
                    rightValue: "₱${profit.toStringAsFixed(2)}",
                  ),
                  const SizedBox(height: 10),
                  _metricRow(
                    leftTitle: "Cost",
                    leftValue: "₱${cost.toStringAsFixed(2)}",
                    rightTitle: "Sales Count",
                    rightValue: "$salesCount",
                  ),
                  const SizedBox(height: 16),

                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "By Category",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),

                        ...kMajorCategories.map((c) {
                          final r = revByCat[c] ?? 0.0;
                          final p = profitByCat[c] ?? 0.0;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                    child: Text(c,
                                        style: const TextStyle(
                                            color: Colors.white70))),
                                Text(
                                  "₱${p.toStringAsFixed(2)}",
                                  style: const TextStyle(
                                      color: Colors.greenAccent),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  "₱${r.toStringAsFixed(2)}",
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          );
                        }),

                        const SizedBox(height: 4),
                        const Text(
                          "White = Revenue | Green = Profit",
                          style:
                              TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          t,
          style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14),
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: child,
      );

  Widget _metricRow({
    required String leftTitle,
    required String leftValue,
    required String rightTitle,
    required String rightValue,
  }) {
    return Row(
      children: [
        Expanded(child: _metricBox(leftTitle, leftValue)),
        const SizedBox(width: 10),
        Expanded(child: _metricBox(rightTitle, rightValue)),
      ],
    );
  }

  Widget _metricBox(String title, String value) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
}
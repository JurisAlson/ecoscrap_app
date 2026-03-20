import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/categories.dart';

class AnalyticsHomeTab extends StatefulWidget {
  final String shopID;
  final String shopName;
  final VoidCallback onOpenProfile;
  final Widget notifBell;

  const AnalyticsHomeTab({
    super.key,
    required this.shopID,
    required this.shopName,
    required this.onOpenProfile,
    required this.notifBell,
  });

  @override
  State<AnalyticsHomeTab> createState() => _AnalyticsHomeTabState();
}

class _AnalyticsHomeTabState extends State<AnalyticsHomeTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final Color primaryColor = const Color(0xFF1FA9A7);

  final NumberFormat _numberFormat = NumberFormat('#,##0.##');
  final NumberFormat _wholeNumberFormat = NumberFormat('#,##0');
  final NumberFormat _compactFormat = NumberFormat.compact();

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  String _formatCurrency(num value) {
    if (value % 1 == 0) {
      return '₱${_wholeNumberFormat.format(value)}';
    }
    return '₱${_numberFormat.format(value)}';
  }

  String _formatKg(num value) => '${_numberFormat.format(value)} kg';

  String _formatChartNumber(num value) {
    if (value >= 1000) return _compactFormat.format(value);
    if (value % 1 == 0) return _wholeNumberFormat.format(value);
    return _numberFormat.format(value);
  }

  DateTime _monthStart(int month) {
    return DateTime(_selectedYear, month, 1);
  }

  DateTime _monthEndExclusive(int month) {
    return DateTime(_selectedYear, month + 1, 1);
  }

  int _daysInMonth(DateTime start) {
    final end = DateTime(start.year, start.month + 1, 1);
    return end.subtract(const Duration(days: 1)).day;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final start = _monthStart(_selectedMonth);
    final end = _monthEndExclusive(_selectedMonth);

    final shopId = widget.shopID.trim();
    if (shopId.isEmpty) {
      return const Center(
        child: Text(
          "Missing shopID",
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    final txStream = FirebaseFirestore.instance
        .collection('Users')
        .doc(shopId)
        .collection('transaction')
        .where(
          'transactionDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(start),
        )
        .where(
          'transactionDate',
          isLessThan: Timestamp.fromDate(end),
        )
        .orderBy('transactionDate', descending: true)
        .snapshots();

    final inventoryStream = FirebaseFirestore.instance
        .collection('Users')
        .doc(shopId)
        .collection('inventory')
        .snapshots();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _homeHeader(),
        const SizedBox(height: 12),
        PromoSlider(primaryColor: primaryColor),
        const SizedBox(height: 16),
        _buildMonthSelector(),
        const SizedBox(height: 16),

        StreamBuilder<QuerySnapshot>(
          stream: txStream,
          builder: (context, txSnap) {
            if (txSnap.connectionState == ConnectionState.waiting) {
              return _card(
                child: const SizedBox(
                  height: 260,
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            if (txSnap.hasError) {
              return _card(
                child: Text(
                  "Chart error: ${txSnap.error}",
                  style: const TextStyle(color: Colors.redAccent),
                ),
              );
            }

            return StreamBuilder<QuerySnapshot>(
              stream: inventoryStream,
              builder: (context, invSnap) {
                if (invSnap.connectionState == ConnectionState.waiting) {
                  return _card(
                    child: const SizedBox(
                      height: 260,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }

                if (invSnap.hasError) {
                  return _card(
                    child: Text(
                      "Inventory chart error: ${invSnap.error}",
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  );
                }

                final days = _daysInMonth(start);

                final dailyRevenue = <int, double>{};
                for (int d = 1; d <= days; d++) {
                  dailyRevenue[d] = 0.0;
                }

                final revByCat = emptyMajorCategoryMap();
                final inventoryKgByCat = emptyMajorCategoryMap();

                for (final doc in txSnap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final type = (data['transactionType'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();

                  if (type != 'sell' && type != 'sale') continue;

                  final ts = data['transactionDate'] as Timestamp?;
                  final dt = ts?.toDate();
                  if (dt == null) continue;

                  final items = (data['items'] as List<dynamic>?) ?? [];
                  double txRevenue = 0.0;

                  for (final raw in items) {
                    final it = raw as Map<String, dynamic>;

                    final cat =
                        normalizeCategoryKey((it['category'] ?? '').toString());
                    final sellTotal =
                        (it['sellTotal'] as num?)?.toDouble() ?? 0.0;

                    txRevenue += sellTotal;

                    if (revByCat.containsKey(cat)) {
                      revByCat[cat] = revByCat[cat]! + sellTotal;
                    }
                  }

                  final day = dt.day;
                  if (dailyRevenue.containsKey(day)) {
                    dailyRevenue[day] = (dailyRevenue[day] ?? 0.0) + txRevenue;
                  }
                }

                for (final doc in invSnap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final cat = normalizeCategoryKey(
                    (data['category'] ?? '').toString(),
                  );
                  final unitsKg =
                      (data['unitsKg'] as num?)?.toDouble() ?? 0.0;

                  if (unitsKg <= 0) continue;

                  if (inventoryKgByCat.containsKey(cat)) {
                    inventoryKgByCat[cat] =
                        inventoryKgByCat[cat]! + unitsKg;
                  }
                }

                return _chartsBlock(
                  start: start,
                  dailyRevenue: dailyRevenue,
                  revByCat: revByCat,
                  inventoryKgByCat: inventoryKgByCat,
                );
              },
            );
          },
        ),

        const SizedBox(height: 16),
        _sectionTitle("MONTH-TO-DATE SUMMARY"),

        StreamBuilder<QuerySnapshot>(
          stream: txStream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return _card(
                child: const Center(child: CircularProgressIndicator()),
              );
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

            final revByCat = emptyMajorCategoryMap();
            final profitByCat = emptyMajorCategoryMap();

            for (final doc in snap.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final type = (data['transactionType'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();

              if (type != 'sell' && type != 'sale') continue;

              salesCount++;

              final items = (data['items'] as List<dynamic>?) ?? [];
              for (final raw in items) {
                final it = raw as Map<String, dynamic>;

                final cat =
                    normalizeCategoryKey((it['category'] ?? '').toString());
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
                  leftValue: _formatCurrency(revenue),
                  rightTitle: "Profit",
                  rightValue: _formatCurrency(profit),
                  rightValueColor: const Color(0xFF00E676),
                ),
                const SizedBox(height: 10),
                _metricRow(
                  leftTitle: "Cost",
                  leftValue: _formatCurrency(cost),
                  rightTitle: "Sales Count",
                  rightValue: _wholeNumberFormat.format(salesCount),
                ),
                const SizedBox(height: 16),
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Category",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...kMajorCategories.map((c) {
                        final key = normalizeCategoryKey(c);
                        final r = revByCat[key] ?? 0.0;
                        final p = profitByCat[key] ?? 0.0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  c,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                              Text(
                                _formatCurrency(p),
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _formatCurrency(r),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                      const Text(
                        "White = Revenue | Green = Profit",
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _chartsBlock({
    required DateTime start,
    required Map<int, double> dailyRevenue,
    required Map<String, double> revByCat,
    required Map<String, double> inventoryKgByCat,
  }) {
    return _card(
      child: SizedBox(
        height: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Analytics Overview",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: PageView(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Daily Revenue",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: _dailyRevenueLineChart(
                          start: start,
                          dailyRevenue: dailyRevenue,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Revenue by Category",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: _revenueByCategoryBarChart(revByCat),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Inventory Overview",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: _inventoryOverviewCard(inventoryKgByCat),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dailyRevenueLineChart({
    required DateTime start,
    required Map<int, double> dailyRevenue,
  }) {
    final days = _daysInMonth(start);

    final spots = <FlSpot>[];
    double maxY = 0.0;

    for (int d = 1; d <= days; d++) {
      final y = dailyRevenue[d] ?? 0.0;
      if (y > maxY) maxY = y;
      spots.add(FlSpot(d.toDouble(), y));
    }

    if (maxY <= 0) {
      return const Center(
        child: Text(
          "No sales data for this month.",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minX: 1,
        maxX: days.toDouble(),
        minY: 0,
        maxY: maxY * 1.15,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
            color: Colors.white.withOpacity(0.06),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: maxY <= 0 ? 1 : (maxY / 3),
              getTitlesWidget: (value, meta) {
                final label = _formatChartNumber(value);
                return Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 5,
              getTitlesWidget: (value, meta) {
                final day = value.toInt();
                if (day < 1 || day > days) {
                  return const SizedBox.shrink();
                }
                return Text(
                  "$day",
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: primaryColor,
            barWidth: 3,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: primaryColor.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _revenueByCategoryBarChart(Map<String, double> revByCat) {
    final entries = revByCat.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return const Center(
        child: Text(
          "No category revenue yet.",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    double maxY = entries.first.value;
    if (maxY <= 0) maxY = 1;

    final groups = <BarChartGroupData>[];
    for (int i = 0; i < entries.length; i++) {
      final v = entries[i].value;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: v,
              width: 18,
              borderRadius: BorderRadius.circular(6),
              color: primaryColor,
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY * 1.2,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
            color: Colors.white.withOpacity(0.06),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: maxY <= 0 ? 1 : (maxY / 3),
              getTitlesWidget: (value, meta) {
                final label = _formatChartNumber(value);
                return Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= entries.length) {
                  return const SizedBox.shrink();
                }

                final name = entries[i].key;
                final short = name.length <= 3 ? name : name.substring(0, 3);

                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    short.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: groups,
      ),
    );
  }

  Widget _inventoryOverviewCard(Map<String, double> inventoryKgByCat) {
    final entries = inventoryKgByCat.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return const Center(
        child: Text(
          "No inventory data yet.",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final totalKg = entries.fold<double>(0.0, (sum, e) => sum + e.value);
    final top = entries.first;
    final maxKg = top.value <= 0 ? 1.0 : top.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _miniStatCard(
                title: "Total Stock",
                value: _formatKg(totalKg),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _miniStatCard(
                title: "Highest Category",
                value: top.key,
                subValue: _formatKg(top.value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final e = entries[i];
              final percent = e.value / maxKg;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.key,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        _formatKg(e.value),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: percent.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: Colors.white.withOpacity(0.08),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(primaryColor),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _miniStatCard({
    required String title,
    required String value,
    String? subValue,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subValue != null) ...[
            const SizedBox(height: 4),
            Text(
              subValue,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _homeHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: widget.onOpenProfile,
          child: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [primaryColor, Colors.green]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.storefront, color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Junkshop Dashboard",
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
              Text(
                widget.shopName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        widget.notifBell,
      ],
    );
  }

  Widget _compactYearButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: disabled
              ? Colors.white.withOpacity(0.03)
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 14,
          color: disabled ? Colors.white24 : Colors.white,
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    const months = [
      "JAN",
      "FEB",
      "MAR",
      "APR",
      "MAY",
      "JUN",
      "JUL",
      "AUG",
      "SEP",
      "OCT",
      "NOV",
      "DEC",
    ];

    final currentYear = DateTime.now().year;
    final selectedLabel = months[_selectedMonth - 1];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Selected Period",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "$selectedLabel $_selectedYear",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _compactYearButton(
                      icon: Icons.remove,
                      onTap: _selectedYear > currentYear
                          ? () {
                              setState(() {
                                _selectedYear--;
                              });
                            }
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        "$_selectedYear",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _compactYearButton(
                      icon: Icons.add,
                      onTap: () {
                        setState(() {
                          _selectedYear++;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: months.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final monthNumber = index + 1;
                final isSelected = monthNumber == _selectedMonth;

                return GestureDetector(
                  onTap: () => setState(() => _selectedMonth = monthNumber),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: isSelected
                          ? const LinearGradient(
                              colors: [Color(0xFF1FA9A7), Colors.green],
                            )
                          : null,
                      color: isSelected ? null : Colors.white.withOpacity(0.06),
                      border: Border.all(
                        color: isSelected
                            ? Colors.white.withOpacity(0.16)
                            : Colors.white.withOpacity(0.08),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      months[index],
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: isSelected ? Colors.white : Colors.white70,
                      ),
                    ),
                  ),
                );
              },
            ),
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
            fontSize: 14,
          ),
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
    Color? leftValueColor,
    Color? rightValueColor,
  }) {
    return Row(
      children: [
        Expanded(
          child: _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leftTitle.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  leftValue,
                  style: TextStyle(
                    color: leftValueColor ?? Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rightTitle.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  rightValue,
                  style: TextStyle(
                    color: rightValueColor ?? Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class PromoSlider extends StatefulWidget {
  final Color primaryColor;

  const PromoSlider({super.key, required this.primaryColor});

  @override
  State<PromoSlider> createState() => _PromoSliderState();
}

class _PromoSliderState extends State<PromoSlider> {
  final PageController _controller = PageController();
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_controller.hasClients) return;

      final next = (_index + 1) % 3;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = [
      _promoSlide(
        icon: Icons.lightbulb_outline,
        title: "Did you know?",
        body:
            "Proper sorting improves material value and reduces waste in landfills.",
      ),
      _promoSlide(
        icon: Icons.location_city_outlined,
        title: "SDG 11: Sustainable Cities",
        body:
            "Your junkshop helps build cleaner, safer communities by supporting recycling systems.",
      ),
      _promoSlide(
        icon: Icons.eco_outlined,
        title: "Community + Environment",
        body:
            "Every transaction helps the community, supports collectors, and reduces pollution.",
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: 110,
          child: PageView.builder(
            controller: _controller,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => slides[i],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            slides.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 6,
              width: _index == i ? 18 : 6,
              decoration: BoxDecoration(
                color: _index == i ? widget.primaryColor : Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _promoSlide({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: widget.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: widget.primaryColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
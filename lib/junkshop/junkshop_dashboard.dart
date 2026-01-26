import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui';
import '../screens/inventory_screen.dart';

class JunkshopDashboardPage extends StatefulWidget {
  const JunkshopDashboardPage({super.key});

  @override
  State<JunkshopDashboardPage> createState() => _JunkshopDashboardPageState();
}

class _JunkshopDashboardPageState extends State<JunkshopDashboardPage> {
  int _activeTabIndex = 0;

  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  // Bottom nav screens
  List<Widget> _tabScreens() => [
        _homeTabStream(),
        InventoryScreen(shopID: FirebaseAuth.instance.currentUser!.uid),
        const Center(
          child: Text(
            "Supplier Map Screen",
            style: TextStyle(color: Colors.white, fontSize: 24),
          ),
        ),
        const Center(
          child: Text(
            "Profile Screen",
            style: TextStyle(color: Colors.white, fontSize: 24),
          ),
        ),
      ];

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Logout failed: $e")),
      );
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _startOfWeek(DateTime d) {
    final diff = d.weekday - DateTime.monday;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  double _sumKg(Iterable<Map<String, dynamic>> logs) {
    double total = 0;
    for (final l in logs) {
      total += (l['kg'] as num).toDouble();
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: bgColor,
      extendBody: true,
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -120,
            child: _blurCircle(primaryColor.withOpacity(0.15), 320),
          ),
          Positioned(
            bottom: 80,
            left: -120,
            child: _blurCircle(Colors.green.withOpacity(0.1), 360),
          ),
          SafeArea(
            child: Column(
              children: [
                // Top Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Row(
                    children: [
                      _logoBox(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Junkshop Dashboard",
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              user?.displayName ?? "Junkshop Owner",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _iconButton(Icons.logout, onTap: () => _logout(context)),
                    ],
                  ),
                ),

                // Tab content
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey(_activeTabIndex),
                    child: _tabScreens()[_activeTabIndex],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // Bottom navigation
      bottomNavigationBar: Container(
        height: 90,
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.85),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.1)),
          ),
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Material(
              color: Colors.transparent,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(0, Icons.storefront_outlined, "Home"),
                  _navItem(1, Icons.inventory_2_outlined, "Inventory"),
                  _navItem(2, Icons.map_outlined, "Map"),
                  _navItem(3, Icons.person_outline, "Profile"),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================== HOME TAB STREAM ==================
Widget _homeTabStream() {
  final userId = FirebaseAuth.instance.currentUser!.uid;

  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('Junkshop')
        .doc(userId)
        .collection('recycleLogs')
        .orderBy('timestamp', descending: true)
        .snapshots(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final logs = snapshot.data!.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'category': data['category'] ?? 'Unknown',
          'kg': (data['kg'] as num).toDouble(),
          'source': data['source'] ?? '',
          'timestamp': (data['timestamp'] as Timestamp).toDate(),
        };
      }).toList();

      final now = DateTime.now();
      final todayLogs =
          logs.where((l) => _isSameDay(l['timestamp'] as DateTime, now));
      final weekStart = _startOfWeek(now);
      final weekLogs = logs.where((l) {
        final t = l['timestamp'] as DateTime;
        return t.isAfter(weekStart.subtract(const Duration(milliseconds: 1)));
      });

      final todayKg = _sumKg(todayLogs);
      final weekKg = _sumKg(weekLogs);
      final todayCount = todayLogs.length;

      // Top category today
      final Map<String, double> catKg = {};
      for (final l in todayLogs) {
        final cat = (l['category'] ?? 'Unknown').toString();
        final kg = (l['kg'] as num).toDouble();
        catKg[cat] = (catKg[cat] ?? 0) + kg;
      }
      String topCat = "—";
      double topCatKg = 0;
      catKg.forEach((k, v) {
        if (v > topCatKg) {
          topCatKg = v;
          topCat = k;
        }
      });

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Cards
            Row(
              children: [
                Expanded(
                  child: _kpiCard(
                    title: "Recycled Today",
                    value: "${todayKg.toStringAsFixed(1)} kg",
                    subtitle: "$todayCount transactions",
                    icon: Icons.recycling,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _kpiCard(
                    title: "This Week",
                    value: "${weekKg.toStringAsFixed(1)} kg",
                    subtitle: "since Monday",
                    icon: Icons.calendar_month,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _kpiCard(
                    title: "Top Plastic Today",
                    value: topCat,
                    subtitle: topCat == "—"
                        ? "no logs yet"
                        : "${topCatKg.toStringAsFixed(1)} kg",
                    icon: Icons.category,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _actionCard(
                    title: "Add Recycle Log",
                    subtitle: "Realtime Firestore update",
                    icon: Icons.add,
                    onTap: _openAddLogDialog,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              "Recent Activity",
              style: TextStyle(
                color: Colors.grey.shade200,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 10),
            ...logs.take(6).map((l) => _activityTile(l)),
          ],
        ),
      );
    },
  );
}

  Widget _homeTab(List<Map<String, dynamic>> logs) {
    final now = DateTime.now();
    final todayLogs =
        logs.where((l) => _isSameDay(l['timestamp'] as DateTime, now));
    final weekStart = _startOfWeek(now);
    final weekLogs = logs.where((l) {
      final t = l['timestamp'] as DateTime;
      return t.isAfter(weekStart.subtract(const Duration(milliseconds: 1)));
    });

    final todayKg = _sumKg(todayLogs);
    final weekKg = _sumKg(weekLogs);
    final todayCount = todayLogs.length;

    // Top category today
    final Map<String, double> catKg = {};
    for (final l in todayLogs) {
      final cat = (l['category'] ?? 'Unknown').toString();
      final kg = (l['kg'] as num).toDouble();
      catKg[cat] = (catKg[cat] ?? 0) + kg;
    }
    String topCat = "—";
    double topCatKg = 0;
    catKg.forEach((k, v) {
      if (v > topCatKg) {
        topCatKg = v;
        topCat = k;
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Cards
          Row(
            children: [
              Expanded(
                child: _kpiCard(
                  title: "Recycled Today",
                  value: "${todayKg.toStringAsFixed(1)} kg",
                  subtitle: "$todayCount transactions",
                  icon: Icons.recycling,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _kpiCard(
                  title: "This Week",
                  value: "${weekKg.toStringAsFixed(1)} kg",
                  subtitle: "since Monday",
                  icon: Icons.calendar_month,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _kpiCard(
                  title: "Top Plastic Today",
                  value: topCat,
                  subtitle: topCat == "—"
                      ? "no logs yet"
                      : "${topCatKg.toStringAsFixed(1)} kg",
                  icon: Icons.category,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionCard(
                  title: "Add Recycle Log",
                  subtitle: "Realtime Firestore update",
                  icon: Icons.add,
                  onTap: _openAddLogDialog,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            "Recent Activity",
            style: TextStyle(
              color: Colors.grey.shade200,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          ...logs.take(6).map((l) => _activityTile(l)),
        ],
      ),
    );
  }

  // ================== ADD LOG TO FIRESTORE ==================
  Future<void> _openAddLogDialog() async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _AddRecycleLogDialog(primaryColor: primaryColor),
  );

  if (result != null) {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    await FirebaseFirestore.instance
        .collection('Junkshop')
        .doc(userId)
        .collection('recycleLogs')
        .add({
      'category': result['category'],
      'kg': result['kg'],
      'source': result['source'],
      'timestamp': FieldValue.serverTimestamp(),
    });

    // No need to setState anymore — StreamBuilder will auto-update
  }
}


  // ================== UI Helpers ==================
  Widget _kpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: primaryColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.add, color: Colors.green),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activityTile(Map<String, dynamic> log) {
    final cat = (log['category'] ?? '').toString();
    final kg = (log['kg'] as num).toDouble();
    final source = (log['source'] ?? '').toString();
    final t = log['timestamp'] as DateTime;

    String timeStr;
    final now = DateTime.now();
    if (_isSameDay(t, now)) {
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      timeStr = "Today • $hh:$mm";
    } else {
      timeStr = "${t.month}/${t.day}/${t.year}";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.local_shipping, color: primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$cat • ${kg.toStringAsFixed(1)} kg",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  "$source • $timeStr",
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================== NAV / UI Helpers ==================
  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _activeTabIndex == index;

    return InkWell(
      onTap: () => setState(() => _activeTabIndex = index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 3,
              width: isActive ? 18 : 0,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Icon(icon,
                color: isActive ? primaryColor : Colors.grey.shade500),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isActive ? primaryColor : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoBox() {
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, Colors.green.shade600],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.store, color: Colors.white),
    );
  }

  Widget _iconButton(IconData icon, {required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.grey.shade300),
      ),
    );
  }

  Widget _blurCircle(Color color, double size) {
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

// ========= Add Log Dialog (UI-only) =========
class _AddRecycleLogDialog extends StatefulWidget {
  final Color primaryColor;
  final String? initialCategory;
  final double? initialKg;
  final String? initialSource;

  const _AddRecycleLogDialog({
    required this.primaryColor,
    this.initialCategory,
    this.initialKg,
    this.initialSource,
  });

  @override
  State<_AddRecycleLogDialog> createState() => _AddRecycleLogDialogState();
}

class _AddRecycleLogDialogState extends State<_AddRecycleLogDialog> {
  late String _category;
  late TextEditingController _kgCtrl;
  late String _source;

  final _categories = const ["PP Color", "PP White", "HD", "Black"];
  final _sources = const ["Household pickup", "Walk-in drop-off"];

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory ?? "PP Color";
    _kgCtrl = TextEditingController(
        text: widget.initialKg != null ? widget.initialKg.toString() : "1.0");
    _source = widget.initialSource ?? "Household pickup";
  }

  @override
  void dispose() {
    _kgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Add Recycle Log"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            value: _category,
            items: _categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v!),
            decoration: const InputDecoration(labelText: "Category"),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _kgCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: "Kilograms (kg)"),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _source,
            items: _sources
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _source = v!),
            decoration: const InputDecoration(labelText: "Source"),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () {
            final kg = double.tryParse(_kgCtrl.text.trim()) ?? 0;
            if (kg <= 0) return;

            Navigator.pop(context, {
              'category': _category,
              'kg': kg,
              'source': _source,
            });
          },
          child: Text(
            "Add",
            style: TextStyle(color: widget.primaryColor),
          ),
        ),
      ],
    );
  }
}

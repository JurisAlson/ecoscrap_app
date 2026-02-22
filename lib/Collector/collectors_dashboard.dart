import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'collector_notifications_page.dart';
import 'collector_messages_page.dart';
import 'collector_pickup_map_page.dart';

class CollectorsDashboardPage extends StatefulWidget {
  const CollectorsDashboardPage({super.key});

  @override
  State<CollectorsDashboardPage> createState() => _CollectorsDashboardPageState();
}

class _CollectorsDashboardPageState extends State<CollectorsDashboardPage>
    with WidgetsBindingObserver {
  // Theme
  static const Color primaryColor = Color(0xFF1FA9A7);
  static const Color bgColor = Color(0xFF0F172A);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnline(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setOnline(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnline(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _setOnline(false);
    }
  }

  Future<void> _setOnline(bool online) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
        'isOnline': online,
        'lastSeen': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(), // ✅ helps if rules require updatedAt
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("❌ setOnline failed: $e");
    }
  }

  Widget _pendingVerificationScreenNew({
    required String collectorStatus,
    required bool legacyAdminOk,
    required bool legacyJunkshopOk,
    required bool legacyActive,
  }) {
    final s = collectorStatus.toLowerCase();

    String title = "Collector account pending";
    String body = "Your account is not verified yet.\nPlease wait for approval.";

    // NEW FLOW
    if (s == "pending") {
      title = "Collector request submitted";
      body = "Please wait for admin approval.";
    } else if (s == "adminapproved") {
      title = "Admin approved";
      body = "Now wait for a junkshop to accept you (first claim).";
    } else if (s == "rejected") {
      title = "Request rejected";
      body = "Your collector request was rejected.\nYou may submit again.";
    }

    // LEGACY FLOW fallback messaging (if you still use these flags somewhere)
    if (collectorStatus.isEmpty) {
      if (!legacyAdminOk) {
        title = "Collector account pending";
        body = "Please wait for admin approval.";
      } else if (!legacyJunkshopOk) {
        title = "Admin approved";
        body = "Now wait for junkshop verification.";
      } else if (!legacyActive) {
        title = "Almost ready";
        body = "Your account is verified but not yet active.";
      }
    }

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, color: Colors.white70, size: 70),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _setOnline(false);
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text("Logout"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isCollectorRole(Map<String, dynamic>? data) {
    final rolesRaw =
        (data?['Roles'] ?? data?['role'] ?? "").toString().trim().toLowerCase();
    return rolesRaw == "collector" || rolesRaw == "collectors";
  }

  bool _isJunkshopVerifiedNew(Map<String, dynamic>? data) {
    return data?['junkshopVerified'] == true ||
        (data?['junkshopStatus'] ?? "").toString().toLowerCase() == "verified";
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Text("Not logged in.", style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('Users').doc(user.uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: bgColor,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          return Scaffold(
            backgroundColor: bgColor,
            body: Center(
              child: Text("Error: ${snap.error}",
                  style: const TextStyle(color: Colors.white)),
            ),
          );
        }

        final data = snap.data?.data() as Map<String, dynamic>?;

        // ✅ NEW FLOW checks
        final isCollectorRole = _isCollectorRole(data);
        final junkshopOkNew = _isJunkshopVerifiedNew(data);
        final collectorStatus = (data?['collectorStatus'] ?? "").toString();

        // ✅ LEGACY FLOW checks (kept, so you don't break old accounts)
        final legacyAdminOk = data?['adminVerified'] == true;
        final legacyJunkshopOk = data?['junkshopVerified'] == true;
        final legacyActive = data?['collectorActive'] == true;

        // ✅ Allow entry if:
        // NEW FLOW: role=collector AND junkshop verified
        // OR legacy flow: adminVerified AND junkshopVerified AND collectorActive
        final allowDashboard =
            (isCollectorRole && junkshopOkNew) || (legacyAdminOk && legacyJunkshopOk && legacyActive);

        if (!allowDashboard) {
          return Scaffold(
            backgroundColor: bgColor,
            body: _pendingVerificationScreenNew(
              collectorStatus: collectorStatus,
              legacyAdminOk: legacyAdminOk,
              legacyJunkshopOk: legacyJunkshopOk,
              legacyActive: legacyActive,
            ),
          );
        }

        return Scaffold(
          backgroundColor: bgColor,
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
                child: _blurCircle(Colors.green.withOpacity(0.10), 360),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: Row(
                        children: [
                          _logoBox(),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Collector Dashboard",
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                                const Text(
                                  "Collector",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          _iconButton(
                            Icons.map_outlined,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Open a pickup from Notifications first.")),
                              );
                            },
                          ),
                          const SizedBox(width: 10),
                          _iconButton(
                            Icons.chat_bubble_outline,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CollectorMessagesPage()),
                              );
                            },
                          ),
                          const SizedBox(width: 10),
                          _iconButton(
                            Icons.notifications_none,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CollectorNotificationsPage()),
                              );
                            },
                          ),
                          _iconButton(
                            Icons.person_outline,
                            onTap: () => _showProfileSheet(context),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: _CollectorLogsHome(collectorId: user.uid)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ================== UI HELPERS ==================
  static Widget _logoBox() {
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primaryColor, Colors.green.shade600]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.person_pin_circle, color: Colors.white),
    );
  }

  static Widget _iconButton(IconData icon, {required VoidCallback onTap}) {
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

  void _showProfileSheet(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111928),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const Icon(Icons.person, size: 64, color: Colors.white54),
                const SizedBox(height: 10),
                Text(
                  user?.displayName ?? "Collector",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  user?.email ?? "No email",
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await _setOnline(false);
                      await FirebaseAuth.instance.signOut();
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text("Logout"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ================= LOGS HOME (unchanged) =================

class _CollectorLogsHome extends StatelessWidget {
  const _CollectorLogsHome({required this.collectorId});
  final String collectorId;

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('pickupRequests')
        .where('collectorId', isEqualTo: collectorId)
        .orderBy('updatedAt', descending: true)
        .limit(25);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Error loading logs: ${snap.error}",
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text("No logs yet.", style: TextStyle(color: Colors.white70)),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Logs",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              for (final d in docs) ...[
                _buildLogCard(d),
              ],
            ],
          ),
        );
      },
    );
  }

  static Widget _buildLogCard(QueryDocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>;
    final status = (data['status'] ?? '').toString().toLowerCase();

    final name = (data['householdName'] ??
            (data['household'] is Map ? (data['household']['name']) : null) ??
            data['name'] ??
            "Unknown")
        .toString();

    final title = _statusToTitle(status);
    final ts = _pickBestTimestamp(data, status);
    final timeText = _formatTimestamp(ts);

    return _logCard(
      title: title,
      subtitle: "Name: $name",
      time: timeText,
      icon: _statusToIcon(status),
      iconBg: _statusToIconBg(status),
      iconColor: _statusToIconColor(status),
    );
  }

  static String _statusToTitle(String status) {
    switch (status) {
      case 'completed':
        return "Pickup completed";
      case 'accepted':
        return "Pickup request accepted";
      case 'transferred':
        return "Transferred to junkshop";
      case 'pending':
        return "Pickup request received";
      case 'cancelled':
      case 'canceled':
        return "Pickup cancelled";
      default:
        return status.isEmpty ? "Pickup update" : "Pickup $status";
    }
  }

  static IconData _statusToIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'accepted':
        return Icons.thumb_up_alt_outlined;
      case 'transferred':
        return Icons.local_shipping_outlined;
      case 'pending':
        return Icons.schedule_outlined;
      case 'cancelled':
      case 'canceled':
        return Icons.cancel_outlined;
      default:
        return Icons.receipt_long;
    }
  }

  static Color _statusToIconBg(String status) {
    switch (status) {
      case 'completed':
        return Colors.green.withOpacity(0.15);
      case 'accepted':
        return Colors.blue.withOpacity(0.15);
      case 'transferred':
        return Colors.orange.withOpacity(0.15);
      case 'pending':
        return Colors.white.withOpacity(0.10);
      case 'cancelled':
      case 'canceled':
        return Colors.red.withOpacity(0.15);
      default:
        return Colors.green.withOpacity(0.15);
    }
  }

  static Color _statusToIconColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'accepted':
        return Colors.lightBlueAccent;
      case 'transferred':
        return Colors.orangeAccent;
      case 'pending':
        return Colors.white70;
      case 'cancelled':
      case 'canceled':
        return Colors.redAccent;
      default:
        return Colors.green;
    }
  }

  static Timestamp? _pickBestTimestamp(Map<String, dynamic> data, String status) {
    Timestamp? t(dynamic v) => v is Timestamp ? v : null;

    if (status == 'accepted') {
      return t(data['acceptedAt']) ?? t(data['updatedAt']) ?? t(data['createdAt']);
    }
    if (status == 'completed') {
      return t(data['completedAt']) ?? t(data['updatedAt']) ?? t(data['createdAt']);
    }
    if (status == 'transferred') {
      return t(data['transferredAt']) ?? t(data['updatedAt']) ?? t(data['createdAt']);
    }
    return t(data['updatedAt']) ?? t(data['createdAt']);
  }

  static String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return "—";
    final dt = ts.toDate();
    final now = DateTime.now();

    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = dt.year == now.year && dt.month == now.month && dt.day == now.day - 1;

    String two(int n) => n.toString().padLeft(2, '0');

    int hour = dt.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    final time = "$hour:${two(dt.minute)} $ampm";

    if (sameDay) return "Today • $time";
    if (yesterday) return "Yesterday • $time";

    const months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
    final m = months[dt.month - 1];
    return "$m ${dt.day} • $time";
  }

  static Widget _logCard({
    required String title,
    required String subtitle,
    required String time,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
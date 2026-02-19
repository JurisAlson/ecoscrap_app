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
    // foreground = online, background = offline
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
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid) // ✅ assumes Users docId == auth.uid
          .set({
        'isOnline': online,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("❌ setOnline failed: $e");
    }
  }

  Widget _pendingVerificationScreen() {
  return SafeArea(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top, color: Colors.white70, size: 70),
            const SizedBox(height: 16),
            const Text(
              "Collector account pending",
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Your account is not verified yet.\nPlease wait for admin approval.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  @override
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
            child: Text("Error: ${snap.error}", style: const TextStyle(color: Colors.white)),
          ),
        );
      }

      final data = snap.data?.data() as Map<String, dynamic>?;

      // ✅ If missing, default to false
      final bool adminOk = (data?['adminVerified'] == true);
      final bool junkshopOk = (data?['junkshopVerified'] == true);
      final bool active = (data?['collectorActive'] == true);

      // ✅ Gate the dashboard (must pass both approvals + active)
      if (!(adminOk && junkshopOk && active)) {
        return Scaffold(
          backgroundColor: bgColor,
          body: _pendingVerificationScreen(),
        );
      }


      return Scaffold(
        backgroundColor: bgColor,
        body: Stack(
          children: [
            Positioned(top: -120, right: -120, child: _blurCircle(primaryColor.withOpacity(0.15), 320)),
            Positioned(bottom: 80, left: -120, child: _blurCircle(Colors.green.withOpacity(0.10), 360)),

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
                              Text("Collector Dashboard", style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                              const Text(
                                "Collector",
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
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

                  const Expanded(child: _CollectorLogsHome()),
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
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
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
                      // ✅ mark offline before sign out
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

class _CollectorLogsHome extends StatelessWidget {
  const _CollectorLogsHome();

  @override
  Widget build(BuildContext context) {
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

          _logCard(
            title: "Pickup completed",
            subtitle: "Household: Juan Dela Cruz • 2.5kg",
            time: "Today",
          ),

          _logCard(
            title: "Pickup request accepted",
            subtitle: "Household: Maria Santos • 1.2kg",
            time: "Yesterday",
          ),

          _logCard(
            title: "Transferred to junkshop",
            subtitle: "Mores Scrap Trading • ₱120.00",
            time: "2 days ago",
          ),
        ],
      ),
    );
  }

  static Widget _logCard({
    required String title,
    required String subtitle,
    required String time,
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
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.receipt_long, color: Colors.green),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:ui';
import 'package:flutter/material.dart';
import 'collector_notifications_page.dart';
import 'collector_messages_page.dart';
import 'collector_pickup_map_page.dart'; // new separate map page file

class CollectorsDashboardPage extends StatelessWidget {
  const CollectorsDashboardPage({super.key});



  // Theme
  static const Color primaryColor = Color(0xFF1FA9A7);
  static const Color bgColor = Color(0xFF0F172A);

  @override
  Widget build(BuildContext context) {
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

                      // ✅ Pickup/Map (separate page)
                      _iconButton(
                        Icons.map_outlined,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Open a pickup from Notifications first.")),
                          );
                        },
                      ),
                      const SizedBox(width: 10),

                      // ✅ Messages (separate page)
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

                      // ✅ Notifications (kept in this same file)
                      _iconButton(
                        Icons.notifications_none,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const CollectorNotificationsPage()),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                // ✅ Logs stay on dashboard
                const Expanded(child: _CollectorLogsHome()),
              ],
            ),
          ),
        ],
      ),
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
}
class CollectorNotificationsPage extends StatelessWidget {
  const CollectorNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text("Notifications"),
      ),
      body: const Center(
        child: Text(
          "Pickup Requests / Notifications here",
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }
}
// =====================================================
// HOME TAB = LOGS (shown on dashboard)
// =====================================================
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
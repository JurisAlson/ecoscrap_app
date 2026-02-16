import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import '../image_detection.dart';
import '../auth/JunkshopAccountCreation.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _activeTabIndex = 0;

  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  // ================= TAB SCREENS =================
  // ✅ Map removed from tabs
  List<Widget> get _tabScreens => [
        _householdHome(),
        const Center(
          child: Text(
            "Chat Screen",
            style: TextStyle(color: Colors.white, fontSize: 22),
          ),
        ),
        _profileTab(),
      ];

  // ================= CAMERA =================

  Future<void> _openLens(BuildContext context) async {
    var status = await Permission.camera.status;
    if (status.isDenied) {
      status = await Permission.camera.request();
    }

    if (status.isGranted) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ImageDetectionPage()),
      );
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  // ================= BUILD =================

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: bgColor,
      extendBody: true,
      body: Stack(
        children: [
          _blurCircle(primaryColor.withOpacity(0.15), 300, top: -100, right: -100),
          _blurCircle(Colors.green.withOpacity(0.1), 350, bottom: 100, left: -100),
          SafeArea(
            child: Column(
              children: [
                // ===== HEADER =====
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
                            Text(
                              "Welcome back,",
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                            ),
                            Text(
                              user?.displayName ?? "Household User",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _iconButton(Icons.notifications_outlined, badge: true, onTap: () {}),
                    ],
                  ),
                ),

                // ===== TAB CONTENT =====
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _tabScreens[_activeTabIndex],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // ===== CAMERA FAB =====
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(top: 40),
        child: SizedBox(
          width: 68,
          height: 68,
          child: FloatingActionButton(
            onPressed: () => _openLens(context),
            backgroundColor: primaryColor,
            elevation: 10,
            shape: CircleBorder(side: BorderSide(color: bgColor, width: 4)),
            child: const Icon(Icons.camera_alt, color: Color(0xFF0F172A), size: 30),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // ===== BOTTOM NAV =====
      // ✅ Map removed from footer
      bottomNavigationBar: Container(
        height: 90,
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.8),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(0, Icons.home_outlined, "Home"),
                const SizedBox(width: 48), // space for FAB
                _navItem(1, Icons.message_outlined, "Chat"),
                _navItem(2, Icons.person_outline, "Profile"),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================= HOME TAB =================

  Widget _householdHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statCard("Items", "24", Icons.recycling),
              const SizedBox(width: 12),
              _statCard("Weight", "8.5 kg", Icons.scale),
              const SizedBox(width: 12),
              _statCard("CO₂ Saved", "3.2 kg", Icons.eco),
            ],
          ),
          const SizedBox(height: 30),

          GestureDetector(
            onTap: () => _openLens(context),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [primaryColor, Colors.green]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: const [
                  Icon(Icons.camera_alt, color: Colors.white, size: 36),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      "Scan an item\nCheck if it’s recyclable",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          Text(
            "What you can do",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // ✅ Keep cards as UI only for now
          Row(
            children: [
              _actionCard(Icons.local_shipping, "Request Pickup", onTap: () {
                // Later flow: show after scan result
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Pickup flow will be available after scanning.")),
                );
              }),
              const SizedBox(width: 12),
              _actionCard(Icons.location_on, "Find Junkshop", onTap: () {
                // Later flow: show after scan result
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Junkshop map will open after scanning.")),
                );
              }),
            ],
          ),

          const SizedBox(height: 30),

          _infoCard(
            "Did you know?",
            "Only 9% of plastic waste is recycled globally. "
            "Proper segregation helps reduce landfill waste.",
          ),
        ],
      ),
    );
  }

  // ================= PROFILE TAB =================

  Widget _profileTab() {
  final user = FirebaseAuth.instance.currentUser;

  return SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(
          Icons.person,
          size: 80,
          color: Colors.white54,
        ),
        const SizedBox(height: 16),

        Text(
          user?.email ?? "Household User",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 40),

        // ================= APPLY AS JUNKSHOP =================
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.storefront_outlined,
                color: Color(0xFF1FA9A7),
                size: 32,
              ),
              const SizedBox(height: 12),
              const Text(
                "Register as Junkshop",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Submit your business permit and create a business account.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1FA9A7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const JunkshopAccountCreationPage(),
                      ),
                    );
                  },
                  child: const Text(
                    "Apply Now",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 40),

        // ================= LOGOUT =================
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () async {
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
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

  // ================= HELPERS =================

  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _activeTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTabIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? primaryColor : Colors.grey.shade500),
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
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: primaryColor),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // ✅ Added onTap parameter
  Widget _actionCard(IconData icon, String text, {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(icon, color: primaryColor, size: 28),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard(String title, String content) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(content, style: TextStyle(color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Widget _logoBox() {
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primaryColor, Colors.green]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.eco, color: Colors.white),
    );
  }

  Widget _iconButton(IconData icon, {bool badge = false, required VoidCallback onTap}) {
    return Stack(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.grey.shade300),
          ),
        ),
        if (badge)
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }

  Widget _blurCircle(Color color, double size, {double? top, double? bottom, double? left, double? right}) {
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
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui';
import '../image_detection.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _activeTabIndex = 0;

  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

 // TAB CONTENT (visual confirmation)
final List<Widget> _tabScreens = [
  const Center(
    child: Text("Household Home",
        style: TextStyle(color: Colors.white, fontSize: 24)),
  ),
  const Center(
    child: Text("Map Screen",
        style: TextStyle(color: Colors.white, fontSize: 24)),
  ),
  const Center(
    child: Text("Chat Screen",
        style: TextStyle(color: Colors.white, fontSize: 24)),
  ),
  //  Profile Screen with Logout
  Builder(
    builder: (context) {
      final user = FirebaseAuth.instance.currentUser;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              user?.displayName ?? user?.email ?? "Household User",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (!context.mounted) return;
                Navigator.pushReplacementNamed(context, '/login');
              },
              icon: const Icon(Icons.logout),
              label: const Text("Logout"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1FA9A7),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    },
  ),
];


  // Logout
  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  // Camera / Lens
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: bgColor,
      extendBody: true,

      // ===== BODY (CONTENT ONLY CHANGES) =====
      body: Stack(
        children: [
          // Background blur
          Positioned(
            top: -100,
            right: -100,
            child: _blurCircle(primaryColor.withOpacity(0.15), 300),
          ),
          Positioned(
            bottom: 100,
            left: -100,
            child: _blurCircle(Colors.green.withOpacity(0.1), 350),
          ),

          SafeArea(
            child: Column(
              children: [
                // TOP HEADER
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
                            Text("Welcome back,",
                                style: TextStyle(
                                    color: Colors.grey.shade400, fontSize: 12)),
                            Text(
                              user?.displayName ?? "Household User",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      _iconButton(Icons.notifications_outlined,
                          badge: true, onTap: () {}),
                    ],
                  ),
                ),

                // TAB CONTENT
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

      // ===== FLOATING CAMERA BUTTON =====
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(top: 40),
        child: SizedBox(
          width: 68,
          height: 68,
          child: FloatingActionButton(
            onPressed: () => _openLens(context),
            backgroundColor: primaryColor,
            elevation: 10,
            shape:
                CircleBorder(side: BorderSide(color: bgColor, width: 4)),
            child: const Icon(Icons.camera_alt,
                color: Color(0xFF0F172A), size: 30),
          ),
        ),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerDocked,

      // ===== BOTTOM NAVIGATION =====
      bottomNavigationBar: Container(
        height: 90,
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.8),
          border:
              Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(0, Icons.home_outlined, "Home"),
                _navItem(1, Icons.location_on_outlined, "Map"),
                const SizedBox(width: 48),
                _navItem(2, Icons.message_outlined, "Chat"),
                _navItem(3, Icons.person_outline, "Profile"),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== WIDGET HELPERS =====

  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _activeTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _activeTabIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
    );
  }

  Widget _logoBox() {
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, Colors.green.shade500],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.eco, color: Colors.white),
    );
  }

  Widget _iconButton(IconData icon,
      {bool badge = false, required VoidCallback onTap}) {
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
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          )
      ],
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

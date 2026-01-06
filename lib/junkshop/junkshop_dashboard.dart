import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';

class JunkshopDashboardPage extends StatefulWidget {
  const JunkshopDashboardPage({super.key});

  @override
  State<JunkshopDashboardPage> createState() => _JunkshopDashboardPageState();
}

class _JunkshopDashboardPageState extends State<JunkshopDashboardPage> {
  int _activeTabIndex = 0;

  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  // JUNKSHOP TAB CONTENT (TEMP PLACEHOLDERS)
  final List<Widget> _tabScreens = const [
    Center(
      child: Text(
        "Junkshop Home",
        style: TextStyle(color: Colors.white, fontSize: 24),
      ),
    ),
    Center(
      child: Text(
        "Inventory Screen",
        style: TextStyle(color: Colors.white, fontSize: 24),
      ),
    ),
    Center(
      child: Text(
        "Supplier Map Screen",
        style: TextStyle(color: Colors.white, fontSize: 24),
      ),
    ),
    Center(
      child: Text(
        "Profile Screen",
        style: TextStyle(color: Colors.white, fontSize: 24),
      ),
    ),
  ];

  // Logout
  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: bgColor,
      extendBody: true,

      // ===== BODY =====
      body: Stack(
        children: [
          // Background blur
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
                            Text(
                              "Junkshop Dashboard",
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 12),
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

      // ===== BOTTOM NAV =====
      bottomNavigationBar: Container(
        height: 90,
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.85),
          border:
              Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
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
    );
  }

  // ===== HELPERS =====

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
          colors: [primaryColor, Colors.green.shade600],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.store, color: Colors.white),
    );
  }

  Widget _iconButton(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
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

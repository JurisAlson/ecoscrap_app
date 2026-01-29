import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../screens/inventory_screen.dart';
import '../screens/transaction_screen.dart';

class JunkshopDashboardPage extends StatefulWidget {
  final String shopID;

  const JunkshopDashboardPage({super.key, required this.shopID});

  @override
  State<JunkshopDashboardPage> createState() => _JunkshopDashboardPageState();
}

class _JunkshopDashboardPageState extends State<JunkshopDashboardPage> {
  int _activeTabIndex = 0;

  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  // ✅ Use widget.shopID everywhere (don’t re-derive it)
  List<Widget> _tabScreens() => [
        _homeTabStream(),

        // Inventory tab
        InventoryScreen(shopID: widget.shopID),

        // Transactions tab
        TransactionScreen(shopID: widget.shopID),

        // Map tab
        const Center(
          child: Text(
            "Supplier Map Screen",
            style: TextStyle(color: Colors.white, fontSize: 24),
          ),
        ),

        // Profile tab
        const Center(
          child: Text(
            "Profile Screen",
            style: TextStyle(color: Colors.white, fontSize: 24),
          ),
        ),
      ];

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
                              "Junkshop Dashboard",
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
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
                      _iconButton(
                        Icons.logout,
                        onTap: () async {
                          await FirebaseAuth.instance.signOut();
                          if (!mounted) return;
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            '/login',
                            (_) => false,
                          );
                        },
                      ),
                    ],
                  ),
                ),

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

      // ✅ Bottom navigation: fix labels/indexes
      bottomNavigationBar: Container(
        height: 90,
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.85),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
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
                  _navItem(2, Icons.receipt_long_outlined, "Transactions"),
                  _navItem(3, Icons.map_outlined, "Map"),
                  _navItem(4, Icons.person_outline, "Profile"),
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
    // ✅ Use widget.shopID
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Junkshop')
          .doc(widget.shopID)
          .collection('recycleLogs')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        // keep your existing home UI logic here...
        return const Center(
          child: Text("Home Tab", style: TextStyle(color: Colors.white)),
        );
      },
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
      ),
    );
  }

  Widget _logoBox() {
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primaryColor, Colors.green.shade600]),
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
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
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

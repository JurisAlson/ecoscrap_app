import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../screens/analytics_home_tab.dart';
import '../screens/inventory_screen.dart';
import '../screens/transaction_screen.dart';

class JunkshopDashboardPage extends StatefulWidget {
  final String shopID;
  final String shopName;

  const JunkshopDashboardPage({
    super.key,
    required this.shopID,
    required this.shopName,
  });

  @override
  State<JunkshopDashboardPage> createState() => _JunkshopDashboardPageState();
}

class _JunkshopDashboardPageState extends State<JunkshopDashboardPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _activeTabIndex = 0;

  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  late final PageController _pageController = PageController(initialPage: 0);

  bool _navVisible = false;
  double _dragAccum = 0;

  late final List<Widget> _tabs = [
    AnalyticsHomeTab(
      shopID: widget.shopID,
      shopName: widget.shopName,
      onOpenProfile: () => _scaffoldKey.currentState?.openDrawer(),
      onOpenNotifications: () => _scaffoldKey.currentState?.openEndDrawer(),
    ),
    InventoryScreen(shopID: widget.shopID),
    TransactionScreen(shopID: widget.shopID),
    const Center(
      child: Text(
        "Supplier Map Screen",
        style: TextStyle(color: Colors.white, fontSize: 22),
      ),
    ),
  ];

  void _goToTab(int index) {
    setState(() {
      _activeTabIndex = index;
      _navVisible = false;
    });

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: bgColor,
        extendBody: true,

        drawer: Drawer(
          backgroundColor: bgColor,
          child: SafeArea(child: _profileDrawer(user)),
        ),

        endDrawer: Drawer(
          backgroundColor: bgColor,
          child: SafeArea(child: _notificationsDrawer()),
        ),

        body: Stack(
          children: [
            _blurCircle(primaryColor.withOpacity(0.15), 300,
                top: -100, right: -100),
            _blurCircle(Colors.green.withOpacity(0.1), 350,
                bottom: 100, left: -100),

            SafeArea(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _activeTabIndex = i),
                children: _tabs,
              ),
            ),

            _bottomSwipeNav(),
          ],
        ),
      ),
    );
  }

  // ================= DRAWERS (RESTORED) =================

  Widget _notificationsDrawer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              const Text(
                "Notifications",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _notificationTile(
            icon: Icons.info_outline,
            title: "Welcome!",
            subtitle: "Track inventory, transactions, and community impact here.",
          ),
          const SizedBox(height: 12),
          _notificationTile(
            icon: Icons.location_city_outlined,
            title: "SDG 11 Impact",
            subtitle:
                "Your junkshop supports cleaner, safer communities through recycling.",
          ),
          const SizedBox(height: 12),
          _notificationTile(
            icon: Icons.eco_outlined,
            title: "Tip",
            subtitle: "Sorted and clean plastics usually have higher value.",
          ),
        ],
      ),
    );
  }

  Widget _notificationTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primaryColor, size: 22),
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
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileDrawer(User? user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              const Text(
                "Profile",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Icon(Icons.storefront, size: 80, color: Colors.white54),
          const SizedBox(height: 14),
          Text(
            widget.shopName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            user?.email ?? "",
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Impact",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "Your junkshop helps the community and the environment by increasing recycling, supporting collectors, and reducing waste in landfills.",
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
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

  // ================= BOTTOM NAV (UNCHANGED) =================

  Widget _bottomSwipeNav() {
    const double navHeight = 96;
    const double swipeZoneHeight = 10;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: (_) => _dragAccum = 0,
        onVerticalDragUpdate: (d) {
          _dragAccum += d.delta.dy;

          if (_dragAccum < -18 && !_navVisible) {
            setState(() => _navVisible = true);
            _dragAccum = 0;
          }
          if (_dragAccum > 18 && _navVisible) {
            setState(() => _navVisible = false);
            _dragAccum = 0;
          }
        },
        child: Stack(
          children: [
            SizedBox(height: _navVisible ? navHeight : swipeZoneHeight),
            AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              offset: _navVisible ? Offset.zero : const Offset(0, 1.2),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: _navVisible ? 1 : 0,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(22)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        height: navHeight,
                        decoration: BoxDecoration(
                          color: bgColor.withOpacity(0.86),
                          border: Border(
                            top: BorderSide(
                                color: Colors.white.withOpacity(0.08)),
                          ),
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            Container(
                              width: 42,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _navItem(
                                    0, Icons.storefront_outlined, "Home"),
                                _navItem(1, Icons.inventory_2_outlined,
                                    "Inventory"),
                                _navItem(2, Icons.receipt_long_outlined,
                                    "Transactions"),
                                _navItem(3, Icons.map_outlined, "Map"),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _activeTabIndex == index;

    return GestureDetector(
      onTap: () => _goToTab(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
      ),
    );
  }

  Widget _blurCircle(
    Color color,
    double size, {
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
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

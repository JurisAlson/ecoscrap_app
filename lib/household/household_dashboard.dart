import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import '../image_detection.dart';
import '../auth/JunkshopAccountCreation.dart';

import '../auth/CollectorAccountCreation.dart';


class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _activeTabIndex = 0;

  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  // ===== TOP SLIDER STATE =====
  final PageController _promoController = PageController();
  int _promoIndex = 0;
  Timer? _promoTimer;

  // ✅ FIXED bottom bar height (nav + room for camera action bar)
  static const double _bottomBarHeight = 140;

  // ===== CAMERA BAR STATE =====
  bool _cameraBarOpen = false;

  // ================= TAB SCREENS =================
  List<Widget> get _tabScreens => [
        _householdHome(),
        _historyScreen(),
        _collectorsTab(),
        const Center(
          child: Text(
            "Chat Screen",
            style: TextStyle(color: Colors.white, fontSize: 22),
          ),
        ),
      ];

  @override
  void initState() {
    super.initState();

    // Auto-slide top slider every 4 seconds
    _promoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_promoController.hasClients) return;
      final next = (_promoIndex + 1) % 3;
      _promoController.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _promoTimer?.cancel();
    _promoController.dispose();
    super.dispose();
  }

  void _toggleCameraBar() => setState(() => _cameraBarOpen = !_cameraBarOpen);

  void _closeCameraBar() {
    if (_cameraBarOpen) setState(() => _cameraBarOpen = false);
  }

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

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        _closeCameraBar();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: bgColor,
        extendBody: true,

        // ✅ LEFT SLIDE = PROFILE
        drawer: Drawer(
          backgroundColor: bgColor,
          child: SafeArea(child: _profileDrawer()),
        ),

        // ✅ RIGHT SLIDE = NOTIFICATIONS
        endDrawer: Drawer(
          backgroundColor: bgColor,
          child: SafeArea(child: _notificationsDrawer()),
        ),

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
                        // ✅ LEFT PROFILE ICON
                        GestureDetector(
                          onTap: () {
                            _closeCameraBar();
                            _scaffoldKey.currentState?.openDrawer();
                          },
                          child: Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [primaryColor, Colors.green]),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.person, color: Colors.white),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // ✅ USERNAME
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Welcome back,",
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                user?.displayName ?? "Household User",
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

                        // ✅ RIGHT NOTIFICATION ICON
                        _iconButton(
                          Icons.notifications_outlined,
                          badge: true,
                          onTap: () {
                            _closeCameraBar();
                            _scaffoldKey.currentState?.openEndDrawer();
                          },
                        ),
                      ],
                    ),
                  ),

                  // ===== TAB CONTENT =====
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: KeyedSubtree(
                        key: ValueKey(_activeTabIndex),
                        child: _tabScreens[_activeTabIndex],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ✅ FIXED BOTTOM NAV (NO DROPDOWN / NO AUTO-HIDE)
        bottomNavigationBar: SizedBox(
          height: _bottomBarHeight,
          child: Stack(
            children: [
              // ===== BOTTOM NAV BAR (FIXED) =====
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  height: 90,
                  decoration: BoxDecoration(
                    color: bgColor.withOpacity(0.86),
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
                  ),
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _navItem(0, Icons.home_outlined, "Home"),
                          _navItem(1, Icons.history, "History"),
                          const SizedBox(width: 62),
                          _navItem(2, Icons.group_outlined, "Collectors"),
                          _navItem(3, Icons.message_outlined, "Chat"),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ===== CENTER CAMERA BUTTON (FIXED) =====
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Center(
                  child: GestureDetector(
                    onTap: _toggleCameraBar,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(color: bgColor, width: 5),
                      ),
                      child: Icon(
                        _cameraBarOpen ? Icons.close : Icons.camera_alt,
                        color: const Color(0xFF0F172A),
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),

              // ===== SLIDING CAMERA BAR (ONLY THIS SLIDES) =====
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOut,
                left: 16,
                right: 16,
                bottom: _cameraBarOpen ? 94 : 40,
                child: IgnorePointer(
                  ignoring: !_cameraBarOpen,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _cameraBarOpen ? 1 : 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: bgColor.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: _cameraAction(
                        icon: Icons.camera_alt,
                        title: "Scan",
                        subtitle: "Use camera",
                        onTap: () async {
                          _closeCameraBar();
                          await _openLens(context);
                        },
                      ),
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

  // ================= HOME TAB =================
  Widget _householdHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _topSlider(),
          const SizedBox(height: 18),

          GestureDetector(
            onTap: () async {
              _closeCameraBar();
              await _openLens(context);
            },
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [primaryColor, Colors.green]),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Row(
                children: [
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

          const Text(
            "Why this matters",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          _infoCard(
            "Stronger communities (SDG 11)",
            "Segregating waste and tracking recyclable materials helps keep neighborhoods clean, "
            "reduces landfill overflow, and supports community-based collectors.",
          ),

          const SizedBox(height: 18),

          _infoCard(
            "Community impact",
            "Every scan improves awareness and can help connect households with local collectors—"
            "making recycling more accessible for everyone.",
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

  // ================= TOP SLIDER =================
  Widget _topSlider() {
    final slides = [
      _promoSlide(
        icon: Icons.lightbulb_outline,
        title: "Quick Tip",
        body: "Rinse bottles before recycling for better acceptance.",
      ),
      _promoSlide(
        icon: Icons.eco_outlined,
        title: "Daily Goal",
        body: "Scan 3 items today and improve your waste sorting.",
      ),
      _promoSlide(
        icon: Icons.recycling_outlined,
        title: "Know Your Plastics",
        body: "PET (1) and HDPE (2) are commonly recyclable.",
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: 120,
          child: PageView.builder(
            controller: _promoController,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _promoIndex = i),
            itemBuilder: (context, index) => slides[index],
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
              width: _promoIndex == i ? 18 : 6,
              decoration: BoxDecoration(
                color: _promoIndex == i ? primaryColor : Colors.white24,
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
      padding: const EdgeInsets.all(18),
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
              color: primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: primaryColor),
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

  // ================= HISTORY TAB =================
  Widget _historyScreen() {
    return const Center(
      child: Text(
        "History Screen",
        style: TextStyle(color: Colors.white, fontSize: 22),
      ),
    );
  }

  // ================= COLLECTORS TAB =================
  Widget _collectorsTab() {
    return const Center(
      child: Text(
        "Collector Screen",
        style: TextStyle(color: Colors.white, fontSize: 22),
      ),
    );
  }

  // ================= NOTIFICATIONS DRAWER (RIGHT) =================
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
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _notificationTile(
            icon: Icons.info_outline,
            title: "Welcome!",
            subtitle: "Scan an item to see if it’s recyclable.",
          ),
          const SizedBox(height: 12),
          _notificationTile(
            icon: Icons.eco_outlined,
            title: "Community",
            subtitle: "Your actions help support cleaner, safer neighborhoods (SDG 11).",
          ),
          const SizedBox(height: 12),
          _notificationTile(
            icon: Icons.recycling_outlined,
            title: "Tip",
            subtitle: "Rinse plastic containers before recycling.",
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
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= PROFILE DRAWER (LEFT) =================
Widget _profileDrawer() {
  final user = FirebaseAuth.instance.currentUser;

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
        const Icon(Icons.person, size: 80, color: Colors.white54),
        const SizedBox(height: 16),
        Text(
          user?.email ?? "Household User",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 30),

        _howToUseCard(),

        const SizedBox(height: 20),

        // ===== REGISTER AS JUNKSHOP =====
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Icon(Icons.storefront_outlined, color: Color(0xFF1FA9A7), size: 32),
              const SizedBox(height: 12),
              const Text(
                "Register as Junkshop",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const JunkshopAccountCreationPage()),
                    );
                  },
                  child: const Text("Apply Now", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ===== APPLY AS COLLECTOR (NEW) =====
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Icon(Icons.local_shipping_outlined, color: Colors.green, size: 32),
              const SizedBox(height: 12),
              const Text(
                "Apply as Collector",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                "Create a collector account and submit requirements to start collecting.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 45,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CollectorAccountCreation()),
                    );
                  },
                  child: const Text("Apply Now", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),

        // ===== LOGOUT =====
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    ),
  );
}

  // ================= HOW TO USE CARD =================
  Widget _howToUseCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "How to Use",
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          _HowToRow(icon: Icons.camera_alt, text: "Tap Scan to check if an item is recyclable."),
          SizedBox(height: 10),
          _HowToRow(icon: Icons.history, text: "See your past scans in History."),
          SizedBox(height: 10),
          _HowToRow(icon: Icons.group_outlined, text: "Collectors shows community partners (soon)."),
          SizedBox(height: 10),
          _HowToRow(icon: Icons.notifications_outlined, text: "Check updates and tips in Notifications."),
        ],
      ),
    );
  }

  // ================= HELPERS =================
  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _activeTabIndex == index;
    return GestureDetector(
      onTap: () {
        _closeCameraBar();
        setState(() => _activeTabIndex = index);
      },
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

  Widget _cameraAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: primaryColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
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

class _HowToRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HowToRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF1FA9A7), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

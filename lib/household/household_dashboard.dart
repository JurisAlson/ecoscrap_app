import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../geomapping.dart';
import '../image_detection.dart';
import 'household_order_page.dart';
import '../auth/CollectorAccountCreation.dart';
import '../services/notification_service.dart';
import 'package:ecoscrap_app/chat/screens/chat_list_page.dart';

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

  // (kept)
  static const double _bottomBarClosedHeight = 140;
  static const double _bottomBarOpenHeight = 230;
  bool _cameraBarOpen = false;

  // ================= TAB SCREENS =================
  List<Widget> get _tabScreens => [
        _householdHome(),
        _historyScreen(),
        const HouseholdOrderPage(),
        const ChatListPage(type: "pickup", title: "Chats"),
      ];

  @override
  void initState() {
    super.initState();

    NotificationService.init();

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

  Widget _swipeHint({
    String? label, // optional, you can pass null if you want ZERO text
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chevron_left,
              size: 18, color: Colors.white.withOpacity(0.65)),
          const SizedBox(width: 2),
          Icon(Icons.swipe, size: 18, color: Colors.white.withOpacity(0.85)),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right,
              size: 18, color: Colors.white.withOpacity(0.65)),
          if (label != null) ...[
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
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
  Future<void> _markNotifsSeen() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('Users')
        .doc(user.uid)
        .set({
      'lastNotifSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ================= CAMERA =================
  Future<void> _openLens(BuildContext context) async {
    final proceed = await _showScanHowToSheet(context);
    if (!proceed) return;

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
  
  Stream<int> _householdNotifCountStream(String householdUid) {
    // Count "important updates" for the household:
    // - accepted / arrived / completed / cancelled (and scheduled if you want)
    return FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('householdId', isEqualTo: householdUid)
        .where('active', isEqualTo: true) // focus on current order notifications
        .where('status', whereIn: ['accepted', 'arrived', 'completed', 'cancelled', 'canceled'])
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Widget _pickupNotificationTile(QueryDocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>;

    final status = (data['status'] ?? '').toString().toLowerCase();
    final driver = (data['collectorName'] ?? 'Driver').toString();

    String title;
    IconData icon;

    switch (status) {
      case 'accepted':
        title = "Pickup accepted • Driver: $driver";
        icon = Icons.thumb_up_alt_outlined;
        break;
      case 'arrived':
        title = "Driver arrived at pickup location";
        icon = Icons.location_on_outlined;
        break;
      case 'completed':
        title = "Pickup completed";
        icon = Icons.check_circle_outline;
        break;
      case 'cancelled':
      case 'canceled':
        title = "Pickup cancelled";
        icon = Icons.cancel_outlined;
        break;
      case 'scheduled':
        title = "Pickup scheduled";
        icon = Icons.event_available_outlined;
        break;
      default:
        title = "Pickup update";
        icon = Icons.receipt_long;
    }

    return _notificationTile(
      icon: icon,
      title: title,
      subtitle: "Tap Order tab to view details.",
    );
  }

  Future<bool> _showScanHowToSheet(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScanHowToSheet(
        primaryColor: primaryColor,
        bgColor: bgColor,
      ),
    );
    return result == true;
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

        drawer: Drawer(
          backgroundColor: bgColor,
          child: SafeArea(child: _profileDrawer()),
        ),

        endDrawer: Drawer(
          backgroundColor: bgColor,
          child: SafeArea(child: _notificationsDrawer()),
        ),

        body: Stack(
          children: [
            _blurCircle(primaryColor.withOpacity(0.14), 320,
                top: -120, right: -120),
            _blurCircle(Colors.green.withOpacity(0.10), 380,
                bottom: 110, left: -130),
            SafeArea(
              child: Column(
                children: [
                  _header(user),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
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

        // ✅ FIXED BOTTOM NAV (uniform spacing / better tap feedback)
        bottomNavigationBar: SizedBox(
          height: 90,
          child: Container(
            height: 90,
            decoration: BoxDecoration(
              color: bgColor.withOpacity(0.86),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.08)),
              ),
            ),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _navItem(0, Icons.home_outlined, "Home"),
                      _navItem(1, Icons.history, "History"),
                      _navItem(2, Icons.receipt_long, "Order"),
                      _navItem(3, Icons.message_outlined, "Chat"),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildNotifBell() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return _iconButton(
        Icons.notifications_outlined,
        badge: false,
        onTap: () {
          _closeCameraBar();
          _scaffoldKey.currentState?.openEndDrawer();
        },
      );
    }

    final userDocStream =
        FirebaseFirestore.instance.collection('Users').doc(uid).snapshots();

    return StreamBuilder<DocumentSnapshot>(
      stream: userDocStream,
      builder: (context, userSnap) {
        final userData =
            userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final lastSeen = userData['lastNotifSeenAt'] as Timestamp?;

        final requestQuery = FirebaseFirestore.instance
            .collection('requests')
            .where('type', isEqualTo: 'pickup')
            .where('householdId', isEqualTo: uid)
            .orderBy('updatedAt', descending: true)
            .limit(1);

        return StreamBuilder<QuerySnapshot>(
          stream: requestQuery.snapshots(),
          builder: (context, snap) {
            bool hasUnread = false;

            final docs = snap.data?.docs ?? [];
            if (docs.isNotEmpty) {
              final data = docs.first.data() as Map<String, dynamic>;
              final updatedAt = data['updatedAt'] as Timestamp?;

              if (updatedAt != null) {
                if (lastSeen == null) {
                  hasUnread = true;
                } else {
                  hasUnread =
                      updatedAt.toDate().isAfter(lastSeen.toDate());
                }
              }
            }

            return _iconButton(
              Icons.notifications_outlined,
              badge: hasUnread,
              onTap: () async {
                _closeCameraBar();
                _scaffoldKey.currentState?.openEndDrawer();
                await _markNotifsSeen(); // mark as read
              },
            );
          },
        );
      },
    );
  }
  

  // ================= HEADER =================
  Widget _header(User? user) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final notifQuery = (uid == null)
        ? null
        : FirebaseFirestore.instance
            .collection('requests')
            .where('type', isEqualTo: 'pickup')
            .where('householdId', isEqualTo: uid)
            .orderBy('updatedAt', descending: true)
            .limit(1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              _closeCameraBar();
              _scaffoldKey.currentState?.openDrawer();
            },
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [primaryColor, Colors.green]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(Icons.person, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Welcome back,",
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                Text(
                  user?.displayName ?? "Household User",
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          _buildNotifBell(),
        ],
      ),
    );
  }

  // ================= HOME TAB =================
  Widget _householdHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _topSlider(),
          const SizedBox(height: 18),

          _sectionHeader(
            title: "Accepted by Mores Scrap Trading",
            subtitle:
                "Swipe and compare. If your item looks similar, it is likely accepted.",
          ),
          const SizedBox(height: 10),
          _acceptedPlasticsSection(),
          const SizedBox(height: 14),

          _hintText(
            "Tip: Compare your item with the examples above. If you’re not sure, use Scan below.",
          ),
          const SizedBox(height: 12),

          // ✅ UNIFORM action cards (Scan + Drop-off/Pickup)
          _actionCard(
            icon: Icons.camera_alt,
            title: "Scan an item",
            subtitle: "Check if it’s recyclable",
            gradientColors: [primaryColor, Colors.green],
            onTap: () async {
              _closeCameraBar();
              await _openLens(context);
            },
          ),

          const SizedBox(height: 12),

          _actionCard(
            icon: Icons.location_on_outlined,
            title: "Drop-off & Pickup",
            subtitle: "Set a schedule for recyclables",
            gradientColors: [Colors.green, primaryColor],
            onTap: () {
              _closeCameraBar();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GeoMappingPage()),
              );
            },
          ),

          const SizedBox(height: 14),

          _hintText(
            "If your item matches the examples above, you can schedule a pickup or drop-off. Not sure? Use Scan instead.",
          ),

          const SizedBox(height: 22),

          const Text(
            "Why this matters",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),

          _infoCard(
            "Stronger communities (SDG 11)",
            "Segregating waste and tracking recyclable materials helps keep neighborhoods clean, "
                "reduces landfill overflow, and supports community-based collectors.",
          ),
          const SizedBox(height: 12),
          _infoCard(
            "Community impact",
            "Every scan improves awareness and can help connect households with local collectors—"
                "making recycling more accessible for everyone.",
          ),
          const SizedBox(height: 12),
          _infoCard(
            "Did you know?",
            "Only 9% of plastic waste is recycled globally. Proper segregation helps reduce landfill waste.",
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _sectionHeader({required String title, required String subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _hintText(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.grey.shade400,
        fontSize: 12,
        height: 1.35,
      ),
    );
  }

  // ✅ NEW uniform Action Card (Scan + Drop-off/Pickup)
  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= ACCEPTED PLASTICS =================
  // ✅ UPDATED: moved the swipe/hand hint to TOP of this widget
  Widget _acceptedPlasticsSection() {
    final plastics = [
      {
        "code": "A",
        "short": "COLOR",
        "name": "Colored Hard Plastics",
        "note": "Thick plastic with strong colors.",
        "examples": const [
          "Plastic chair",
          "Durabox",
          "Colored container",
          "Machine parts"
        ],
      },
      {
        "code": "B",
        "short": "WHITE/CLEAR",
        "name": "White or Clear Hard Plastics",
        "note": "Rigid plastic that is white or transparent.",
        "examples": const [
          "Clear food container",
          "White cup",
          "Transparent bin",
          "Plastic lid"
        ],
      },
      {
        "code": "C",
        "short": "BOTTLES",
        "name": "Thick Bottles & Gallons",
        "note": "Heavy-duty bottles for liquids.",
        "examples": const [
          "Zonrox bottle",
          "Detergent bottle",
          "4-gallon container",
          "Cleaning bottle"
        ],
      },
      {
        "code": "D",
        "short": "BLACK",
        "name": "Black Plastics",
        "note": "Any thick black plastic item.",
        "examples": const [
          "Black bucket",
          "Black container",
          "Black storage box",
          "Black plastic parts"
        ],
      },
    ];

    return SizedBox(
      height: 460,
      child: Stack(
        children: [
          // Give room so the hint doesn't overlap the cards
          Padding(
            padding: const EdgeInsets.only(top: 34),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: plastics.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final p = plastics[i];
                return _plasticTypeCard(
                  code: p["code"] as String,
                  short: p["short"] as String,
                  name: p["name"] as String,
                  note: p["note"] as String,
                  exampleLabels: (p["examples"] as List).cast<String>(),
                );
              },
            ),
          ),

          // ✅ hand/swipe icon placed on TOP of this section
          Positioned(
            top: 0,
            right: 10,
            child: _swipeHint(), // or _swipeHint(label: "SWIPE")
          ),
        ],
      ),
    );
  }

  Widget _plasticTypeCard({
    required String code,
    required String short,
    required String name,
    required String note,
    required List<String> exampleLabels,
  }) {
    final labels = List<String>.from(exampleLabels);
    while (labels.length < 4) {
      labels.add("Example ${labels.length + 1}");
    }
    if (labels.length > 4) {
      labels.removeRange(4, labels.length);
    }

    return Container(
      width: 300,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.10)),
                ),
                child: Text(
                  "$code • $short",
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Text(
                  "Accepted",
                  style: TextStyle(
                    color: Colors.grey.shade300,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _exampleSlot(label: labels[0]),
              _exampleSlot(label: labels[1]),
              _exampleSlot(label: labels[2]),
              _exampleSlot(label: labels[3]),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Compare your item with these examples first.",
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _exampleSlot({required String label}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Stack(
        children: [
          const Center(
            child: Icon(Icons.photo_outlined, color: Colors.white38, size: 22),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withOpacity(0.72),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
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
          child: Stack(
            children: [
              PageView.builder(
                controller: _promoController,
                itemCount: slides.length,
                onPageChanged: (i) => setState(() => _promoIndex = i),
                itemBuilder: (context, index) => slides[index],
              ),

              // ✅ swipe cue (no reading required)
              
            ],
          ),
        ),
        const SizedBox(height: 10),

        // dots already help too
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
                    fontWeight: FontWeight.w800,
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(
        child: Text("Not logged in.", style: TextStyle(color: Colors.white)),
      );
    }

    final query = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('householdId', isEqualTo: user.uid)
        .where('active', isEqualTo: false)
        .orderBy('updatedAt', descending: true)
        .limit(30);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Error loading history: ${snap.error}",
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text("No history yet.",
                style: TextStyle(color: Colors.white70)),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Transaction History",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              for (final d in docs) _pickupHistoryCard(d),
            ],
          ),
        );
      },
    );
  }

  Widget _pickupHistoryCard(QueryDocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>;

    final collectorName = (data['collectorName'] ?? '—').toString();
    final status = (data['status'] ?? '').toString().toLowerCase();
    final pickupType = (data['pickupType'] ?? '').toString().toLowerCase();

    final createdAt =
        data['createdAt'] is Timestamp ? data['createdAt'] as Timestamp : null;
    final updatedAt =
        data['updatedAt'] is Timestamp ? data['updatedAt'] as Timestamp : null;
    final ts = createdAt ?? updatedAt;

    final windowStart = data['windowStart'] is Timestamp
        ? data['windowStart'] as Timestamp
        : null;
    final windowEnd =
        data['windowEnd'] is Timestamp ? data['windowEnd'] as Timestamp : null;

    final title = _statusToTitle(status);

    final subtitle = [
      "Collector: $collectorName",
      "Created: ${_formatDateTime(ts)}",
      "Pickup Type: ${pickupType.isEmpty ? '—' : pickupType}",
      "Status: ${status.isEmpty ? '—' : status}",
      if (pickupType == 'window' && windowStart != null && windowEnd != null)
        "Window: ${_formatTime(windowStart)} - ${_formatTime(windowEnd)}",
    ].join("\n");

    return _historyCard(
      title: title,
      subtitle: subtitle,
      rightText: _formatShortTime(ts),
      icon: _statusToIcon(status),
      iconBg: _statusToIconBg(status),
      iconColor: _statusToIconColor(status),
    );
  }

  String _statusToTitle(String status) {
    switch (status) {
      case 'accepted':
        return "Pickup request accepted";
      case 'scheduled':
        return "Pickup scheduled";
      case 'pending':
        return "Pickup request sent";
      case 'completed':
        return "Pickup completed";
      case 'cancelled':
      case 'canceled':
        return "Pickup cancelled";
      default:
        return status.isEmpty ? "Pickup update" : "Pickup $status";
    }
  }

  IconData _statusToIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'accepted':
        return Icons.thumb_up_alt_outlined;
      case 'scheduled':
        return Icons.event_available_outlined;
      case 'pending':
        return Icons.schedule_outlined;
      case 'cancelled':
      case 'canceled':
        return Icons.cancel_outlined;
      default:
        return Icons.receipt_long;
    }
  }

  Color _statusToIconBg(String status) {
    switch (status) {
      case 'completed':
        return Colors.green.withOpacity(0.15);
      case 'accepted':
        return Colors.blue.withOpacity(0.15);
      case 'scheduled':
        return Colors.purple.withOpacity(0.15);
      case 'pending':
        return Colors.white.withOpacity(0.10);
      case 'cancelled':
      case 'canceled':
        return Colors.red.withOpacity(0.15);
      default:
        return Colors.white.withOpacity(0.10);
    }
  }

  Color _statusToIconColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'accepted':
        return Colors.lightBlueAccent;
      case 'scheduled':
        return Colors.purpleAccent;
      case 'pending':
        return Colors.white70;
      case 'cancelled':
      case 'canceled':
        return Colors.redAccent;
      default:
        return Colors.white70;
    }
  }

  String _formatDateTime(Timestamp? ts) {
    if (ts == null) return "—";
    final dt = ts.toDate();

    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ];
    final m = months[dt.month - 1];

    int hour = dt.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    final mm = dt.minute.toString().padLeft(2, '0');

    return "${dt.day} $m ${dt.year} • $hour:$mm $ampm";
  }

  String _formatShortTime(Timestamp? ts) {
    if (ts == null) return "—";
    final dt = ts.toDate();
    int hour = dt.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    final mm = dt.minute.toString().padLeft(2, '0');
    return "$hour:$mm $ampm";
  }

  String _formatTime(Timestamp ts) {
    final dt = ts.toDate();
    int hour = dt.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    final mm = dt.minute.toString().padLeft(2, '0');
    return "$hour:$mm $ampm";
  }

  Widget _historyCard({
    required String title,
    required String subtitle,
    required String rightText,
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                      color: Colors.grey.shade400, fontSize: 11, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            rightText,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ================= NOTIFICATIONS DRAWER (RIGHT) =================
  Widget _notificationsDrawer() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(
        child: Text("Not logged in", style: TextStyle(color: Colors.white)),
      );
    }

    final userDocStream =
        FirebaseFirestore.instance.collection('Users').doc(uid).snapshots();

    final query = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('householdId', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .limit(20);

    return Padding(
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
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: userDocStream,
              builder: (context, userSnap) {
                final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
                final lastSeen = userData['lastNotifSeenAt'] as Timestamp?;

                return StreamBuilder<QuerySnapshot>(
                  stream: query.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          "Failed to load notifications:\n${snap.error}",
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text("No notifications yet.",
                            style: TextStyle(color: Colors.white70)),
                      );
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final d = docs[i];
                        final data = d.data() as Map<String, dynamic>;

                        final status = (data['status'] ?? '').toString().toLowerCase();
                        final driver = (data['collectorName'] ?? '—').toString();

                        final updatedAt = data['updatedAt'] as Timestamp?;
                        final isUnread = (lastSeen == null || (updatedAt != null && updatedAt.toDate().isAfter(lastSeen.toDate())));

                        return _notificationLogTile(
                          title: _pickupStatusToTitle(status),
                          subtitle: "Driver: $driver",
                          time: _formatTimestamp(updatedAt),
                          unread: isUnread,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _pickupStatusToTitle(String status) {
    switch (status) {
      case 'completed':
        return "Pickup completed";
      case 'arrived':
        return "Collector arrived";
      case 'accepted':
        return "Pickup accepted";
      case 'scheduled':
        return "Pickup scheduled";
      case 'pending':
        return "Pickup request sent";
      case 'cancelled':
      case 'canceled':
        return "Pickup cancelled";
      case 'declined':
        return "Pickup declined";
      default:
        return status.isEmpty ? "Pickup update" : "Pickup $status";
    }
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return "—";
    final dt = ts.toDate();
    final now = DateTime.now();

    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = dt.year == now.year && dt.month == now.month && dt.day == (now.day - 1);

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

  Widget _notificationLogTile({
    required String title,
    required String subtitle,
    required String time,
    required bool unread,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: unread ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(unread ? 0.10 : 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.notifications_outlined, color: Colors.white70),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: unread ? FontWeight.w900 : FontWeight.w800,
                    )),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(time, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
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
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 13)),
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
                  fontWeight: FontWeight.w900,
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
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 30),
          _howToUseCard(),
          const SizedBox(height: 20),

          // ✅ APPLY AS COLLECTOR
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              children: [
                Icon(Icons.local_shipping_outlined,
                    color: primaryColor, size: 32),
                const SizedBox(height: 12),
                const Text(
                  "Apply as Collector",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Create a collector account and submit requirements to start collecting.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CollectorAccountCreation(),
                        ),
                      );
                    },
                    child: const Text("Apply Now",
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 26),

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
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _howToUseCard() {
    return Container(
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
            "How to Use",
            style: TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 12),
          _HowToRow(
              icon: Icons.camera_alt,
              text: "Tap Scan to check if an item is recyclable."),
          SizedBox(height: 10),
          _HowToRow(icon: Icons.history, text: "See your past scans in History."),
          SizedBox(height: 10),
          _HowToRow(
              icon: Icons.group_outlined,
              text: "Collectors shows community partners (soon)."),
          SizedBox(height: 10),
          _HowToRow(
              icon: Icons.notifications_outlined,
              text: "Check updates and tips in Notifications."),
        ],
      ),
    );
  }

  // ================= HELPERS =================
  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _activeTabIndex == index;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          _closeCameraBar();
          setState(() => _activeTabIndex = index);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
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
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(content,
              style: TextStyle(color: Colors.grey.shade400, height: 1.35)),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon,
      {bool badge = false, required VoidCallback onTap}) {
    return Stack(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Icon(icon, color: Colors.grey.shade300),
          ),
        ),
        if (badge)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration:
                  const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
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

// ✅ Scan instruction sheet shown BEFORE camera permission/page
class _ScanHowToSheet extends StatelessWidget {
  final Color primaryColor;
  final Color bgColor;

  const _ScanHowToSheet({
    required this.primaryColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.95),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.info_outline, color: primaryColor),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "How to use Scan",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close, color: Colors.white),
                )
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Use Scan only if you’re unsure. For best results:",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
            const SizedBox(height: 14),
            _step(
              icon: Icons.wb_sunny_outlined,
              title: "Good lighting",
              body: "Scan in a well-lit area to avoid blurry results.",
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 10),
            _step(
              icon: Icons.crop_free,
              title: "Center the item",
              body: "Keep the item inside the frame. Avoid blocking labels.",
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 10),
            _step(
              icon: Icons.front_hand_outlined,
              title: "Hold steady",
              body: "Keep your phone steady for 1–2 seconds before capturing.",
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 10),
            _step(
              icon: Icons.warning_amber_outlined,
              title: "Try another angle",
              body: "If the result looks wrong, try a different angle or distance.",
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withOpacity(0.18)),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      "Continue",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _step({
    required IconData icon,
    required String title,
    required String body,
    required Color primaryColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
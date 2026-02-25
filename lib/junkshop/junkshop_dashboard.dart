import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../screens/analytics_home_tab.dart';
import '../screens/inventory_screen.dart';
import '../screens/transaction_screen.dart';
import '../chat/screens/chat_list_page.dart';

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
  static const double _bottomNavHeight = 96;

  // ✅ Always use auth uid as the shopId (RBAC)
  String get _shopIdSafe =>
      FirebaseAuth.instance.currentUser?.uid ?? widget.shopID;

  // ✅ Get live shop doc from Users (no old Junkshop collection)
  Stream<DocumentSnapshot<Map<String, dynamic>>> get _shopDocStream =>
      FirebaseFirestore.instance.collection("Users").doc(_shopIdSafe).snapshots();

  void _goToTab(int index) {
    setState(() => _activeTabIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ✅ Junkshop ACCEPTS collector (2-step finalization)
  // - Updates collectorRequests/{collectorUid} status -> junkshopAccepted
  // - Promotes Users/{collectorUid}.role -> collector
  Future<void> _acceptCollector({
    required String collectorUid,
    required String shopUid,
    required String shopName,
  }) async {
    final db = FirebaseFirestore.instance;

    final reqRef = db.collection("collectorRequests").doc(collectorUid);
    final userRef = db.collection("Users").doc(collectorUid);

    await db.runTransaction((tx) async {
      final reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) throw Exception("Request not found.");

      final req = reqSnap.data() ?? {};
      final status = (req["status"] ?? "").toString();
      final acceptedBy = (req["acceptedByJunkshopUid"] ?? "").toString();

      if (status == "junkshopAccepted") {
        if (acceptedBy == shopUid) return;
        throw Exception("Collector already accepted by another junkshop.");
      }

      if (status != "adminApproved") {
        throw Exception("Collector is not admin approved yet.");
      }

      // 1) lock request
      tx.set(reqRef, {
        "status": "junkshopAccepted",
        "acceptedByJunkshopUid": shopUid,
        "acceptedAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2) promote + ✅ ASSIGN junkshop to collector (THIS FIXES CHAT)
      tx.set(userRef, {
        "role": "collector",
        "Roles": "collector",
        "junkshopVerified": true,
        "junkshopStatus": "verified",
        "collectorStatus": "junkshopAccepted",

        // ✅ REQUIRED for collector app to find its junkshop chat
        "assignedJunkshopUid": shopUid,
        "assignedJunkshopName": shopName,

        // optional compatibility
        "junkshopId": shopUid,
        "junkshopName": shopName,

        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); 
    });
  }

  // ✅ Junkshop REJECTS collector (hide it from THIS junkshop only)
  // This does NOT affect other junkshops.
Future<void> _rejectCollector({
  required String collectorUid,
  required String shopUid,
}) async {
  final reqRef = FirebaseFirestore.instance
      .collection("collectorRequests")
      .doc(collectorUid);

  // Hide ONLY from this junkshop (do NOT change global status)
  await reqRef.set({
    "rejectedByJunkshops": FieldValue.arrayUnion([shopUid]),
    "updatedAt": FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

  // ================= COLLECTOR REQUESTS SECTION (collectorRequests) =================
  Widget _collectorRequestsSection({required String shopId, required String shopName}) {
    final stream = FirebaseFirestore.instance
        .collection("collectorRequests")
        .where("status", isEqualTo: "adminApproved")
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(
            "Collector requests error: ${snap.error}",
            style: const TextStyle(color: Colors.redAccent),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        // Hide collectors this junkshop already rejected
        final docs = snap.data!.docs.where((d) {
          final data = d.data();
          final rejectedBy = (data["rejectedByJunkshops"] as List?) ?? const [];
          return !rejectedBy.contains(shopId);
        }).toList();

        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: const Row(
              children: [
                Icon(Icons.mark_email_read,
                    color: Colors.greenAccent, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "No collector requests available.",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: docs.map((d) {
            final data = d.data();
            final collectorUid = d.id;

            // ✅ Non-sensitive fields only (safe for junkshops)
            final name = (data["publicName"] ?? "Collector").toString();
            final email = (data["emailDisplay"] ?? "").toString();

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  if (email.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(email,
                          style: TextStyle(color: Colors.grey.shade300)),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text("Admin Approved",
                          style: TextStyle(color: Colors.orangeAccent)),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          try {
                            await _acceptCollector(
                              collectorUid: collectorUid,
                              shopUid: shopId,
                              shopName: shopName, 
                            );
                            _toast("Accepted collector: $name");
                          } catch (e) {
                            _toast("Accept failed: $e");
                          }
                        },
                        child: const Text("Accept"),
                      ),
                      TextButton(
                        onPressed: () async {
                          try {
                            await _rejectCollector(
                              collectorUid: collectorUid,
                              shopUid: shopId,
                            );
                            _toast("Rejected collector: $name");
                          } catch (e) {
                            _toast("Reject failed: $e");
                          }
                        },
                        child: const Text("Reject"),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _shopDocStream,
      builder: (context, snap) {
        final shopData = snap.data?.data() ?? {};
        final shopId = _shopIdSafe;

        // Keep format: still display a name in UI, but we do NOT use it for logic.
        final shopName =
            (shopData["name"] ?? shopData["shopName"] ?? widget.shopName)
                .toString();

        final tabs = <Widget>[
          AnalyticsHomeTab(
            shopID: shopId,
            shopName: shopName,
            onOpenProfile: () => _scaffoldKey.currentState?.openDrawer(),
            onOpenNotifications: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
          InventoryScreen(shopID: shopId),
          TransactionScreen(shopID: shopId),
          const Center(
            child: Text(
              "Supplier Map Screen",
              style: TextStyle(color: Colors.white, fontSize: 22),
            ),
          ),
        ];

        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: bgColor,
            extendBody: true,

            drawer: Drawer(
              backgroundColor: bgColor,
              child: SafeArea(child: _profileDrawer(user, shopId, shopName)),
            ),

            endDrawer: Drawer(
              backgroundColor: bgColor,
              child: SafeArea(child: _notificationsDrawer()),
            ),

            bottomNavigationBar: _fixedBottomNav(),

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
                    children: tabs,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ================= FIXED BOTTOM NAV =================
  Widget _fixedBottomNav() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: _bottomNavHeight,
          decoration: BoxDecoration(
            color: bgColor.withOpacity(0.86),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(0, Icons.storefront_outlined, "Home"),
                  _navItem(1, Icons.inventory_2_outlined, "Inventory"),
                  _navItem(2, Icons.receipt_long_outlined, "Transactions"),
                  _navItem(3, Icons.map_outlined, "Map"),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= DRAWERS =================
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
            subtitle: "Your junkshop supports cleaner, safer communities through recycling.",
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
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(subtitle,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileDrawer(User? user, String shopId, String shopName) {
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
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Icon(Icons.storefront, size: 80, color: Colors.white54),
          const SizedBox(height: 14),
          Text(
            shopName,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(user?.email ?? "",
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 18),

          // Impact card
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
                Text("Impact",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 10),
                Text(
                  "Your junkshop helps the community and the environment by increasing recycling, supporting collectors, and reducing waste in landfills.",
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.3),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Collector Requests card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Collector Requests",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                _collectorRequestsSection(shopId: shopId, shopName: shopName),
              ],
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChatListPage(
                      type: "junkshop",
                      title: "Collectors",
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text("Chats with Collectors"),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
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
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= NAV ITEM =================
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

  // ================= BACKGROUND BLUR =================
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
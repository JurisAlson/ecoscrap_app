import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/login_page.dart';

import 'admin_overview_tab.dart';
import 'collectors/admin_collector_requests.dart';
import 'residence/admin_residence_request.dart';
import 'users/admin_users_management_tab.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();

  
}

class _AdminHomePageState extends State<AdminHomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _index = 0;

  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  static const double _bottomBarHeight = 92;

  final _pages = const [
    AdminOverviewTab(),
    AdminCollectorRequestsTab(),
    AdminResidentRequestsTab(),
    AdminUsersManagementTab(),
  ];

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  Future<void> _clearAllNotifications() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final snap = await FirebaseFirestore.instance
      .collection('Users')
      .doc(uid)
      .collection('notifications')
      .get();

  if (snap.docs.isEmpty) return;

  final batch = FirebaseFirestore.instance.batch();

  for (final doc in snap.docs) {
    batch.delete(doc.reference);
  }

  await batch.commit();
}

  Future<void> _markAllNotificationsAsRead() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final snap = await FirebaseFirestore.instance
      .collection('Users')
      .doc(uid)
      .collection('notifications')
      .where('read', isEqualTo: false)
      .get();

  if (snap.docs.isEmpty) return;

  final batch = FirebaseFirestore.instance.batch();
  for (final doc in snap.docs) {
    batch.set(doc.reference, {'read': true}, SetOptions(merge: true));
  }
  await batch.commit();
}

  // -----------------------------
  // Streams for badges / counts
  // -----------------------------

  // Pending collector requests
  Stream<int> _pendingCollectorsCount() {
    return FirebaseFirestore.instance
        .collection("collectorRequests")
        .where("status", isEqualTo: "pending")
        .snapshots()
        .map((s) => s.size);
  }

  Stream<int> _unreadNotificationsCount() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('Users')
      .doc(uid)
      .collection('notifications')
      .where('read', isEqualTo: false)
      .snapshots()
      .map((s) => s.size);
}

  // Pending resident requests
  Stream<int> _pendingResidentsCount() {
    return FirebaseFirestore.instance
        .collection("residentRequests")
        .where("status", isEqualTo: "pending")
        .snapshots()
        .map((s) => s.size);
  }

  // ✅ Count ONLY approved residents as "users"
  // This excludes: pending / rejected / unverified

  @override
Widget build(BuildContext context) {
  final user = FirebaseAuth.instance.currentUser;

  return Scaffold(
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
        _blurCircle(primaryColor.withOpacity(0.15), 300, top: -100, right: -100),
        _blurCircle(Colors.green.withOpacity(0.10), 350, bottom: 100, left: -100),
        SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
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

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Admin Panel",
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          ),
                          const Text(
                            "Administrator",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    /// 🔥 FIXED NOTIFICATION BELL
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('Users')
                          .doc(FirebaseAuth.instance.currentUser!.uid)
                          .collection('notifications')
                          .where('read', isEqualTo: false)
                          .snapshots(),
                      builder: (context, snapshot) {
                        final hasUnread = (snapshot.data?.docs.length ?? 0) > 0;

                        return _iconButton(
                          Icons.notifications_outlined,
                          badge: hasUnread,
                          onTap: () async {
                            _scaffoldKey.currentState?.openEndDrawer();
                            await _markAllNotificationsAsRead();
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),

              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey(_index),
                    child: _pages[_index],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),

    bottomNavigationBar: SizedBox(
      height: _bottomBarHeight,
      child: Container(
        height: _bottomBarHeight,
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.86),
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
        ),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(0, Icons.dashboard_outlined, "Overview"),

                  StreamBuilder<int>(
                    stream: _pendingCollectorsCount(),
                    builder: (context, snap) {
                      final pending = (snap.data ?? 0) > 0;
                      return _navItem(1, Icons.local_shipping_outlined, "Collectors",
                          badge: pending);
                    },
                  ),

                  StreamBuilder<int>(
                    stream: _pendingResidentsCount(),
                    builder: (context, snap) {
                      final pending = (snap.data ?? 0) > 0;
                      return _navItem(2, Icons.home_outlined, "Residents",
                          badge: pending);
                    },
                  ),

                  _navItem(3, Icons.people_alt_outlined, "Users"),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  Future<void> runChatCleanup() async {
  try {
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-southeast1',
    ).httpsCallable('cleanupExistingCompletedChats');

    final result = await callable();

    print("Cleanup result: ${result.data}");
  } catch (e) {
    print("Cleanup failed: $e");
  }
}

  // ✅ updated to support optional badge
  Widget _navItem(int index, IconData icon, String label, {bool badge = false}) {
    final isActive = _index == index;

    return GestureDetector(
      onTap: () => setState(() => _index = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: isActive ? primaryColor : Colors.grey.shade500),

              if (badge)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: bgColor,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
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

  Widget _notificationsDrawer() {
  final uid = FirebaseAuth.instance.currentUser?.uid;

  if (uid == null) {
    return const Center(child: Text("Not logged in"));
  }

  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('Users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Text(
            'Error: ${snapshot.error}',
            style: const TextStyle(color: Colors.white),
          ),
        );
      }

      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }

      final docs = snapshot.data!.docs;

      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// 🔝 Header
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),

                const Expanded(
                  child: Text(
                    "Notifications",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                TextButton(
                  onPressed: _clearAllNotifications,
                  child: const Text(
                    "Clear",
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            /// ❌ Empty state
            if (docs.isEmpty)
              _notificationTile(
                icon: Icons.info_outline,
                title: "Admin",
                subtitle: "No notifications yet.",
              ),

            /// 🔔 Notifications list
            ...docs.map((doc) {
              final data = doc.data();

              final title = (data['title'] ?? 'Notification').toString();
              final body = (data['body'] ?? '').toString();
              final isRead = data['read'] == true;

              return GestureDetector(
                onTap: () {
                  final type = (data['type'] ?? '').toString();

                  Navigator.pop(context);

                  if (type == 'admin_new_resident_request') {
                    setState(() => _index = 2);
                  } else if (type == 'admin_new_collector_request') {
                    setState(() => _index = 1);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: _notificationTile(
                    icon: isRead
                        ? Icons.notifications_none
                        : Icons.notifications_active,
                    title: title,
                    subtitle: body,
                  ),
                ),
              );
            }),
          ],
        ),
      );
    },
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
                "Admin Profile",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Icon(Icons.person, size: 80, color: Colors.white54),
          const SizedBox(height: 16),
          const Text(
            "Administrator",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  "Admin Tools",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 8),
                Text(
                  "• Overview\n• Review collectors\n• Review residents (Palo Alto)\n• Manage users",
                  style: TextStyle(color: Colors.white70, height: 1.35, fontSize: 13),
                ),
              ],
            ),
          ),

          ElevatedButton(
  onPressed: runChatCleanup,
  child: const Text("Clean old chats"),
),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _logout();
              },
              icon: const Icon(Icons.logout),
              label: const Text("Logout"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(
    IconData icon, {
    bool badge = false,
    required VoidCallback onTap,
  }) {
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
            child: Icon(
              icon,
              color: badge ? Colors.amber : Colors.grey.shade300,
            ),
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
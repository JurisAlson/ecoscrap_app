import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../auth/login_page.dart';
import '../security/admin_profile_encrypt.dart';

import 'admin_overview_tab.dart';
import 'collectors/admin_collector_requests.dart';
import 'users/admin_users_management_tab.dart';

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
    AdminUsersManagementTab(),
  ];

  @override
  void initState() {
    super.initState();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  // ✅ Clean + reliable: checks the SAME doc, writes debug ping, then encrypts.
  Future<void> _encryptAdminProfileRunOnce(User user) async {
  try {
    print("=== START ENCRYPT === uid=${user.uid}");

    // 1. Find admin doc by uid field (works even if doc ID is different)
    final q = await FirebaseFirestore.instance
        .collection('Users') // ⚠️ change if your collection name is different
        .where('uid', isEqualTo: user.uid)
        .limit(1)
        .get();

    if (q.docs.isEmpty) {
      throw Exception("Admin document not found for uid ${user.uid}");
    }

    final docRef = q.docs.first.reference;
    final data = q.docs.first.data();

    print("=== FOUND DOC PATH === ${docRef.path}");

    // 2. FORCE WRITE test marker so you can see it immediately
    await docRef.set({
      "FORCE_TEST": "ENCRYPT_CLICKED",
      "FORCE_TIME": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    print("=== FORCE_TEST WRITTEN ===");

    // 3. Pick name from existing field
    final existingName = (data['Name'] as String?)?.trim();
    final nameToEncrypt =
        (existingName != null && existingName.isNotEmpty) ? existingName : "admin";

    // 4. Encrypt profile
    await upsertAdminEncryptedProfile(
      uid: user.uid,
      email: user.email ?? "",
      name: nameToEncrypt,
    );

    print("=== ENCRYPT COMPLETE ===");

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("✅ Encryption executed. Check Firestore for FORCE_TEST and profile."),
      ),
    );
  } catch (e, st) {
    print("❌ ENCRYPT ERROR: $e");
    print(st);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("❌ Encrypt failed: $e")),
    );
  }
}

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
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      _iconButton(
                        Icons.notifications_outlined,
                        badge: false,
                        onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
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
                    _navItem(1, Icons.local_shipping_outlined, "Collectors"),
                    _navItem(2, Icons.people_alt_outlined, "Users"),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _index == index;
    return GestureDetector(
      onTap: () => setState(() => _index = index),
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
            title: "Admin",
            subtitle: "No notifications yet.",
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
          Text(
            "UID: ${user?.uid ?? "-"}",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
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
              children: [
                const Text(
                  "Admin Tools",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                const Text(
                  "• Overview \n• Manage user Roles\n• Review collectors",
                  style: TextStyle(color: Colors.white70, height: 1.35, fontSize: 13),
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
                Navigator.pop(context);
                await _logout();
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
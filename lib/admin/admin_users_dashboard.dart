import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminUsersDashboardPage extends StatefulWidget {
  const AdminUsersDashboardPage({super.key});

  @override
  State<AdminUsersDashboardPage> createState() => _AdminUsersDashboardPageState();
}

class _AdminUsersDashboardPageState extends State<AdminUsersDashboardPage> {
  final primaryColor = const Color(0xFF1FA9A7);
  final bgColor = const Color(0xFF0F172A);

  String _query = "";

  /// ✅ DEBUG → Shows Auth Claims
  Future<void> _showClaims() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Claims: ${token?.claims}"),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, "/login", (_) => false);
  }

  bool _matchesQuery(String a, String b, String c) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return a.toLowerCase().contains(q) ||
        b.toLowerCase().contains(q) ||
        c.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final admin = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: bgColor,
      extendBody: true,
      body: Stack(
        children: [
          /// Background blur
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withOpacity(0.15),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          SafeArea(
            child: CustomScrollView(
              slivers: [
                /// Top Bar
                SliverPadding(
                  padding: const EdgeInsets.all(24),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        const Icon(Icons.admin_panel_settings, color: Colors.white),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Admin Panel",
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                              Text(
                                admin?.email ?? "Admin",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),

                        /// ✅ DEBUG BUTTON
                        _iconButton(Icons.verified_user, onTap: _showClaims),

                        const SizedBox(width: 10),

                        _iconButton(Icons.logout, onTap: _logout),
                      ],
                    ),
                  ),
                ),

                /// Search
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverToBoxAdapter(
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v.trim()),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: "Search...",
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ),

                /// List Card
                SliverPadding(
                  padding: const EdgeInsets.all(24),
                  sliver: SliverToBoxAdapter(child: _combinedCard()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// -------------------------------
  /// USERS + JUNKSHOP STREAM
  /// -------------------------------
  Widget _combinedCard() {
    final usersStream =
        FirebaseFirestore.instance.collection("Users").snapshots();

    final junkStream =
        FirebaseFirestore.instance.collection("Junkshop").snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: usersStream,
      builder: (context, usersSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: junkStream,
          builder: (context, junkSnap) {
            if (usersSnap.hasError || junkSnap.hasError) {
              return Text(
                "Firestore Error:\nUsers: ${usersSnap.error}\nJunk: ${junkSnap.error}",
                style: const TextStyle(color: Colors.white),
              );
            }

            if (!usersSnap.hasData || !junkSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final users = usersSnap.data!.docs;
            final junkshops = junkSnap.data!.docs;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Users (${users.length})",
                    style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 8),

                ...users.map((d) => _userTile(d.data(), d.id)),

                const SizedBox(height: 24),

                Text("Junkshops (${junkshops.length})",
                    style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 8),

                ...junkshops.map((d) => _userTile(d.data(), d.id)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _userTile(Map<String, dynamic> data, String id) {
    final email = data["Email"] ?? id;
    final role = data["Roles"] ?? "User";

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "$email ($role)",
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: Colors.white),
    );
  }
}

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminUsersDashboardPage extends StatefulWidget {
  const AdminUsersDashboardPage({super.key});

  @override
  State<AdminUsersDashboardPage> createState() => _AdminUsersDashboardPageState();
}

class _AdminUsersDashboardPageState extends State<AdminUsersDashboardPage> {
  final primaryColor = const Color(0xFF1FA9A7);
  final bgColor = const Color(0xFF0F172A);

  String _query = "";
  bool _busy = false;

  // ---------- Helpers ----------
  String _normRole(dynamic raw) {
    final s = (raw ?? "").toString().trim().toLowerCase();
    if (s == "users" || s == "user" || s == "household" || s == "households") return "user";
    if (s == "admins" || s == "admin") return "admin";
    if (s == "collectors" || s == "collector") return "collector";
    if (s == "junkshops" || s == "junkshop") return "junkshop";
    return "unknown";
  }

  bool _matchesQuery(List<String> fields) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fields.any((f) => f.toLowerCase().contains(q));
  }

  FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: "asia-southeast1");

  Future<void> _callSetUserRole(String uid, String role) async {
    final callable = _fn.httpsCallable("setUserRole");
    await callable.call({"uid": uid, "role": role});
  }

  Future<void> _callVerifyJunkshop(String uid) async {
    final callable = _fn.httpsCallable("verifyJunkshop");
    await callable.call({"uid": uid});
  }

  Future<void> _callAdminDeleteUser(String uid, {bool deleteJunkshopData = false}) async {
    final callable = _fn.httpsCallable("adminDeleteUser");
    await callable.call({"uid": uid, "deleteJunkshopData": deleteJunkshopData});
  }

  Future<void> _showClaims() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Claims: ${token?.claims}")),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, "/login", (_) => false);
  }

  Future<T?> _confirm<T>({
    required String title,
    required String body,
    required T yesValue,
    required String yesLabel,
    String noLabel = "Cancel",
  }) async {
    return showDialog<T>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(noLabel)),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, yesValue), child: Text(yesLabel)),
        ],
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final admin = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
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
                              Text("Admin Panel", style: TextStyle(color: Colors.grey.shade400)),
                              Text(
                                admin?.email ?? "Admin",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _showClaims,
                          icon: const Icon(Icons.verified_user, color: Colors.white),
                          tooltip: "Show claims",
                        ),
                        IconButton(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout, color: Colors.white),
                          tooltip: "Logout",
                        ),
                      ],
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverToBoxAdapter(
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Search (email / name / role / status)...",
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.all(24),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_busy)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: const [
                                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 10),
                                Text("Processing...", style: TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                        _usersSection(),
                        const SizedBox(height: 24),
                        _junkshopsSection(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Sections ----------
  Widget _usersSection() {
    final usersStream = FirebaseFirestore.instance.collection("Users").snapshots();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Users / RBAC", style: TextStyle(color: Colors.white, fontSize: 18)),
        const SizedBox(height: 10),

        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: usersStream,
          builder: (context, snap) {
            if (snap.hasError) {
              return Text("USERS ERROR: ${snap.error}", style: const TextStyle(color: Colors.red));
            }
            if (!snap.hasData) {
              return const Text("Loading Users...", style: TextStyle(color: Colors.white));
            }

            final allDocs = snap.data!.docs;

            // Counts
            final counts = <String, int>{"admin": 0, "user": 0, "collector": 0, "junkshop": 0, "unknown": 0};
            for (final d in allDocs) {
              final role = _normRole(d.data()["Roles"] ?? d.data()["roles"]);
              counts[role] = (counts[role] ?? 0) + 1;
            }

            // Filtered list
            final filtered = allDocs.where((d) {
              final data = d.data();
              final email = (data["Email"] ?? data["email"] ?? "").toString();
              final name = (data["Name"] ?? data["name"] ?? "").toString();
              final role = _normRole(data["Roles"] ?? data["roles"]);
              return _matchesQuery([email, name, role, d.id]);
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _countRow([
                  _countChip("Total", allDocs.length),
                  _countChip("Admins", counts["admin"] ?? 0),
                  _countChip("Users", counts["user"] ?? 0),
                  _countChip("Collectors", counts["collector"] ?? 0),
                  _countChip("Junkshops", counts["junkshop"] ?? 0),
                ]),
                const SizedBox(height: 12),

                if (filtered.isEmpty)
                  const Text("No users found.", style: TextStyle(color: Colors.white))
                else
                  Column(
                    children: filtered.map((d) => _userTile(uid: d.id, data: d.data())).toList(),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _junkshopsSection() {
    final junkStream = FirebaseFirestore.instance.collection("Junkshop").snapshots();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Junkshops", style: TextStyle(color: Colors.white, fontSize: 18)),
        const SizedBox(height: 10),

        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: junkStream,
          builder: (context, snap) {
            if (snap.hasError) {
              return Text("JUNKSHOP ERROR: ${snap.error}", style: const TextStyle(color: Colors.red));
            }
            if (!snap.hasData) {
              return const Text("Loading Junkshops...", style: TextStyle(color: Colors.white));
            }

            final allDocs = snap.data!.docs;

            int verifiedCount = 0;
            int pendingCount = 0;
            for (final d in allDocs) {
              final v = d.data()["verified"] == true;
              if (v) {
                verifiedCount++;
              } else {
                pendingCount++;
              }
            }

            final filtered = allDocs.where((d) {
              final data = d.data();
              final shopName = (data["shopName"] ?? "").toString();
              final email = (data["shopEmail"] ?? data["email"] ?? "").toString();
              final status = data["verified"] == true ? "verified" : "pending";
              return _matchesQuery([shopName, email, status, d.id]);
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _countRow([
                  _countChip("Total", allDocs.length),
                  _countChip("Verified", verifiedCount),
                  _countChip("Pending", pendingCount),
                ]),
                const SizedBox(height: 12),

                if (filtered.isEmpty)
                  const Text("No junkshops found.", style: TextStyle(color: Colors.white))
                else
                  Column(
                    children: filtered.map((d) => _junkshopTile(uid: d.id, data: d.data())).toList(),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  // ---------- Tiles ----------
  Widget _userTile({required String uid, required Map<String, dynamic> data}) {
    final email = (data["Email"] ?? data["email"] ?? "").toString();
    final name = (data["Name"] ?? data["name"] ?? "").toString();
    final role = _normRole(data["Roles"] ?? data["roles"]);

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
          Text(
            name.isNotEmpty ? name : (email.isNotEmpty ? email : uid),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          if (email.isNotEmpty && name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(email, style: TextStyle(color: Colors.grey.shade300)),
            ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _roleDropdown(
                  value: role,
                  onChanged: (newRole) async {
                    if (newRole == null || newRole == role) return;

                    final ok = await _confirm<bool>(
                      title: "Change role?",
                      body: "Set $uid role to '$newRole'?",
                      yesValue: true,
                      yesLabel: "Change",
                    );

                    if (ok != true) return;

                    setState(() => _busy = true);
                    try {
                      await _callSetUserRole(uid, newRole);
                      _toast("Role updated to $newRole");
                    } catch (e) {
                      _toast("Failed: $e");
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: "Delete user",
                onPressed: () async {
                  final choice = await showDialog<int>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Delete user"),
                      content: const Text(
                        "This deletes Firebase Auth account and Users/{uid}.\n\n"
                        "If this is a junkshop account, you can also delete Junkshop data (inventory/transaction/logs).",
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                        TextButton(onPressed: () => Navigator.pop(ctx, 1), child: const Text("Delete user only")),
                        ElevatedButton(onPressed: () => Navigator.pop(ctx, 2), child: const Text("Delete incl. junkshop data")),
                      ],
                    ),
                  );
                  if (choice != 1 && choice != 2) return;

                  setState(() => _busy = true);
                  try {
                    await _callAdminDeleteUser(uid, deleteJunkshopData: choice == 2);
                    _toast("Deleted $uid");
                  } catch (e) {
                    _toast("Delete failed: $e");
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _junkshopTile({required String uid, required Map<String, dynamic> data}) {
    final shopName = (data["shopName"] ?? uid).toString();
    final verified = data["verified"] == true;

    final email = (data["shopEmail"] ?? data["email"] ?? "").toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shopName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              if (email.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(email, style: TextStyle(color: Colors.grey.shade300)),
                ),
              const SizedBox(height: 6),
              Text(
                verified ? "verified" : "pending",
                style: TextStyle(color: verified ? Colors.greenAccent : Colors.orangeAccent),
              ),
            ]),
          ),
          if (!verified)
            ElevatedButton(
              onPressed: () async {
                final ok = await _confirm<bool>(
                  title: "Verify junkshop?",
                  body: "Verify $uid ($shopName)?",
                  yesValue: true,
                  yesLabel: "Verify",
                );
                if (ok != true) return;

                setState(() => _busy = true);
                try {
                  await _callVerifyJunkshop(uid);
                  _toast("Verified $shopName");
                } catch (e) {
                  _toast("Verify failed: $e");
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
              child: const Text("Verify"),
            ),
        ],
      ),
    );
  }

  // ---------- Small UI widgets ----------
  Widget _countRow(List<Widget> chips) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips,
    );
  }

  Widget _countChip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Text(
        "$label: $value",
        style: const TextStyle(color: Colors.white),
      ),
    );
  }

  Widget _roleDropdown({
    required String value,
    required Future<void> Function(String?) onChanged,
  }) {
    const roles = ["user", "collector", "junkshop", "admin"];

    final safeValue = roles.contains(value) ? value : "user";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          dropdownColor: const Color(0xFF111827),
          value: safeValue,
          isExpanded: true,
          iconEnabledColor: Colors.white,
          style: const TextStyle(color: Colors.white),
          items: roles
              .map((r) => DropdownMenuItem(
                    value: r,
                    child: Text(r),
                  ))
              .toList(),
          onChanged: (v) => onChanged(v),
        ),
      ),
    );
  }
}
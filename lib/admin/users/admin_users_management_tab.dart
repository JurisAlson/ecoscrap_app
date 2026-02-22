import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../admin_theme_page.dart';

class AdminUsersManagementTab extends StatefulWidget {
  const AdminUsersManagementTab({super.key});

  @override
  State<AdminUsersManagementTab> createState() => _AdminUsersManagementTabState();
}

class _AdminUsersManagementTabState extends State<AdminUsersManagementTab> {
  String _query = "";
  String _roleFilter = "all";
  bool _busy = false;

  String _normRole(dynamic raw) {
    final s = (raw ?? "").toString().trim().toLowerCase();
    if (s == "admin" || s == "admins") return "admin";
    if (s == "collector" || s == "collectors") return "collector";
    if (s == "junkshop" || s == "junkshops") return "junkshop";
    if (s == "user" || s == "users" || s == "household" || s == "households") return "user";
    return "user";
  }

  Color _roleColor(String role) {
    switch (role) {
      case "admin":
        return Colors.redAccent;
      case "collector":
        return Colors.cyanAccent;
      case "junkshop":
        return Colors.purpleAccent;
      case "user":
      default:
        return Colors.greenAccent;
    }
  }

  Widget _roleBadge(String role) {
    final c = _roleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.35)),
      ),
      child: Text(
        role,
        style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  Future<void> _deleteUser({
    required String uid,
    required String name,
    required String email,
    required String role,
  }) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    // ✅ Safety: can't delete yourself
    if (currentUid != null && uid == currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You cannot delete your own admin account.")),
      );
      return;
    }

    // ✅ Safety: can't delete admins
    if (role == "admin") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Admin accounts cannot be deleted from here.")),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete User?"),
        content: Text(
          "This will permanently delete:\n\n"
          "Name: $name\n"
          "Email: ${email.isEmpty ? "(none)" : email}\n"
          "Role: $role\n"
          "UID: $uid\n\n"
          "Continue?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);

    try {
      final callable = FirebaseFunctions.instanceFor(region: "asia-southeast1")
          .httpsCallable("adminDeleteUser");

      await callable.call({"uid": uid});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User deleted")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Delete failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance.collection("Users").snapshots();

    return Scaffold(
      backgroundColor: AdminTheme.bg,
      body: AdminTheme.background(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.people, color: Colors.white),
                  SizedBox(width: 10),
                  Text(
                    "User Management",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Search
              TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Search name / email / uid...",
                  hintStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Role filter chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ["all", "admin", "user", "junkshop", "collector"]
                    .map((role) => ChoiceChip(
                          label: Text(role),
                          selected: _roleFilter == role,
                          onSelected: (_) => setState(() => _roleFilter = role),
                        ))
                    .toList(),
              ),

              const SizedBox(height: 10),

              if (_busy) const LinearProgressIndicator(),

              const SizedBox(height: 10),

              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: stream,
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snap.data!.docs;

                    final q = _query.trim().toLowerCase();

                    final filtered = docs.where((d) {
                      final data = d.data();
                      final name = (data["Name"] ?? data["name"] ?? "").toString();
                      final email = (data["emailDisplay"] ?? data["Email"] ?? data["email"] ?? "").toString();
                      final role = _normRole(data["Roles"] ?? data["role"] ?? data["roles"]);

                      final matchesSearch = q.isEmpty ||
                          name.toLowerCase().contains(q) ||
                          email.toLowerCase().contains(q) ||
                          d.id.toLowerCase().contains(q);

                      final matchesRole = _roleFilter == "all" || role == _roleFilter;

                      return matchesSearch && matchesRole;
                    }).toList();

                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text("No users found.", style: TextStyle(color: Colors.white70)),
                      );
                    }

                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final d = filtered[i];
                        final data = d.data();

                        final uid = d.id;
                        final name = (data["Name"] ?? data["name"] ?? "").toString();
                        final email = (data["emailDisplay"] ?? data["Email"] ?? data["email"] ?? "").toString();
                        final role = _normRole(data["Roles"] ?? data["role"] ?? data["roles"]);

                        final title = name.isNotEmpty ? name : (email.isNotEmpty ? email : uid);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    if (email.isNotEmpty)
                                      Text(email, style: TextStyle(color: Colors.grey.shade300, fontSize: 12)),
                                    const SizedBox(height: 8),
                                    _roleBadge(role),
                                  ],
                                ),
                              ),
                             if (role != "admin")
                              IconButton(
                                tooltip: "Delete user",
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                onPressed: _busy
                                    ? null
                                    : () => _deleteUser(uid: uid, name: title, email: email, role: role),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
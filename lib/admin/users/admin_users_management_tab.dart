import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminUsersManagementTab extends StatefulWidget {
  const AdminUsersManagementTab({super.key});

  @override
  State<AdminUsersManagementTab> createState() => _AdminUsersManagementTabState();
}

class _AdminUsersManagementTabState extends State<AdminUsersManagementTab> {
  String _query = "";
  String _roleFilter = "all";
  bool _busy = false;

  // keep your brand colors (same as dashboard)
  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

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
        role.toUpperCase(),
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

    if (currentUid != null && uid == currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You cannot delete your own admin account.")),
      );
      return;
    }

    if (role == "admin") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Admin accounts cannot be deleted from here.")),
      );
      return;
    }

    // ✅ DARK / UNIFORM dialog (no white)
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => AlertDialog(
        backgroundColor: bgColor.withOpacity(0.96),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text("Delete User?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          "This will permanently delete:\n\n"
          "Name: $name\n"
          "Email: ${email.isEmpty ? "(none)" : email}\n"
          "Role: $role\n"
          "UID: $uid\n\n"
          "Continue?",
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);

    try {
      final callable =
          FirebaseFunctions.instanceFor(region: "asia-southeast1").httpsCallable("adminDeleteUser");
      await callable.call({"uid": uid});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: bgColor.withOpacity(0.95),
          content: const Text("User deleted", style: TextStyle(color: Colors.white)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: bgColor.withOpacity(0.95),
          content: Text("Delete failed: $e", style: const TextStyle(color: Colors.white)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance.collection("Users").snapshots();

    // ✅ IMPORTANT: NO Scaffold here (AdminHomePage already handles it)
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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

          // ✅ UNIFORM search field (no white focus)
          TextField(
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: Colors.white),
            cursorColor: primaryColor,
            decoration: InputDecoration(
              hintText: "Search name / email / uid...",
              hintStyle: TextStyle(color: Colors.grey.shade500),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: primaryColor.withOpacity(0.75), width: 1.2),
              ),
            ),
          ),

const SizedBox(height: 10),

// ✅ UNIFORM chips (no white selected)
Wrap(
  spacing: 8,
  runSpacing: 8,
  children: ["all", "admin", "user", "junkshop", "collector"]
      .map((role) {
    final selected = _roleFilter == role;

    return ChoiceChip(
      label: Text(role.toUpperCase()),
      selected: selected,
      onSelected: (_) => setState(() => _roleFilter = role),

      // ✅ Not too dark (soft surface tone)
      backgroundColor: const Color(0xFF141B2D),

      // ✅ Not too light (soft teal tint, no white)
      selectedColor: const Color(0xFF1FA9A7).withOpacity(0.22),

      labelStyle: TextStyle(
        color: selected
            ? const Color(0xFF1FA9A7)
            : Colors.white.withOpacity(0.75), // soft white, not gray
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),

      side: BorderSide(
        color: selected
            ? const Color(0xFF1FA9A7).withOpacity(0.6)
            : Colors.white.withOpacity(0.08),
      ),

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),

      elevation: 0,
      pressElevation: 0,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }).toList(),
),
  
          const SizedBox(height: 10),

          if (_busy)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LinearProgressIndicator(
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation(primaryColor),
                minHeight: 4,
              ),
            ),

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
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                if (email.isNotEmpty)
                                  Text(email, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
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
    );
  }
}
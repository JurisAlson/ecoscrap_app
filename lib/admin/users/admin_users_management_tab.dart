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

  // for cleaner UI: tap "Manage" to reveal actions
  String? _manageUid;

  // Brand colors
  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  static const List<String> _filterRoles = ["all", "residence", "collector"];

  String _normRole(dynamic raw) {
    final s = (raw ?? "").toString().trim().toLowerCase();

    if (s == "residence" ||
        s == "resident" ||
        s == "user" ||
        s == "users" ||
        s == "household" ||
        s == "households") {
      return "residence";
    }

    if (s == "collector" || s == "collectors") return "collector";

    // Hidden roles
    if (s == "admin" || s == "admins") return "admin";
    if (s == "junkshop" || s == "junkshops") return "junkshop";

    return "residence";
  }

  Color _roleColor(String role) {
    switch (role) {
      case "collector":
        return Colors.cyanAccent;
      case "residence":
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

  // Only show this badge when restricted (no "ACTIVE" badge)
  Widget _restrictedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.orangeAccent.withOpacity(0.35)),
      ),
      child: const Text(
        "RESTRICTED",
        style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }

  Future<void> _setRestricted({
    required String uid,
    required String name,
    required bool restricted,
  }) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (currentUid != null && uid == currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You cannot restrict your own admin account.")),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => AlertDialog(
        backgroundColor: bgColor.withOpacity(0.96),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          restricted ? "Restrict User?" : "Unrestrict User?",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          restricted
              ? "This user can still log in, but will see a restricted page and cannot use the app.\n\nUser: $name\nUID: $uid\n\nContinue?"
              : "Restore access for:\n\nUser: $name\nUID: $uid\n\nContinue?",
          style: const TextStyle(color: Colors.white70, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: restricted ? Colors.orangeAccent : Colors.greenAccent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(restricted ? "Restrict" : "Unrestrict"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);

    try {
      final callable = FirebaseFunctions.instanceFor(region: "asia-southeast1")
          .httpsCallable("adminSetUserRestricted");

      await callable.call({
        "uid": uid,
        "restricted": restricted,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: bgColor.withOpacity(0.95),
          content: Text(
            restricted ? "User restricted" : "User un-restricted",
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: bgColor.withOpacity(0.95),
          content: Text("Action failed: $e", style: const TextStyle(color: Colors.white)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance.collection("Users").snapshots();

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

          // Search
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

          // Filters
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filterRoles.map((role) {
              final selected = _roleFilter == role;

              return ChoiceChip(
                label: Text(role.toUpperCase()),
                selected: selected,
                onSelected: (_) => setState(() => _roleFilter = role),
                backgroundColor: const Color(0xFF141B2D),
                selectedColor: const Color(0xFF1FA9A7).withOpacity(0.22),
                labelStyle: TextStyle(
                  color: selected ? const Color(0xFF1FA9A7) : Colors.white.withOpacity(0.75),
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
                  final role = _normRole(data["Roles"] ?? data["role"] ?? data["roles"]);

                  // Hide admin + junkshop entirely
                  if (role == "admin" || role == "junkshop") return false;

                  final name = (data["Name"] ?? data["name"] ?? "").toString();
                  final email =
                      (data["emailDisplay"] ?? data["Email"] ?? data["email"] ?? "").toString();

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
                    final email =
                        (data["emailDisplay"] ?? data["Email"] ?? data["email"] ?? "").toString();
                    final role = _normRole(data["Roles"] ?? data["role"] ?? data["roles"]);

                    final status = (data["status"] ?? "active").toString().trim().toLowerCase();
                    final restricted = status == "restricted";

                    final title = name.isNotEmpty ? name : (email.isNotEmpty ? email : uid);

                    final managing = _manageUid == uid;

                    // Darken restricted cards
                    final cardColor = restricted
                        ? Colors.white.withOpacity(0.03)
                        : Colors.white.withOpacity(0.06);

                    final borderColor = restricted
                        ? Colors.orangeAccent.withOpacity(0.25)
                        : Colors.white.withOpacity(0.08);

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Opacity(
                              opacity: restricted ? 0.82 : 1,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (email.isNotEmpty)
                                    Text(
                                      email,
                                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                                    ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _roleBadge(role),
                                      if (restricted) _restrictedBadge(),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Clean UI: Manage button first
                          if (!managing)
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white.withOpacity(0.85),
                                backgroundColor: Colors.white.withOpacity(0.06),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.white.withOpacity(0.08)),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              onPressed: _busy ? null : () => setState(() => _manageUid = uid),
                              child: const Text(
                                "Manage",
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                            )
                          else
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white70,
                                    side: BorderSide(color: Colors.white.withOpacity(0.12)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  onPressed: _busy ? null : () => setState(() => _manageUid = null),
                                  child: const Text(
                                    "Close",
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        restricted ? Colors.greenAccent : Colors.orangeAccent,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _setRestricted(
                                            uid: uid,
                                            name: title,
                                            restricted: !restricted,
                                          ),
                                  child: Text(
                                    restricted ? "Unrestrict" : "Restrict",
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                                  ),
                                ),
                              ],
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
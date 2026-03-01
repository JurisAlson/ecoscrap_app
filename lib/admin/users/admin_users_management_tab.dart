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

  // ✅ Added "restricted" filter
  static const List<String> _filterRoles = ["all", "residence", "collector", "restricted"];

  // Roles that represent "resident/user"
  static const residenceRoles = [
    "residence",
    "resident",
    "user",
    "users",
    "household",
    "households",
  ];

  String _normRole(dynamic raw) {
    final s = (raw ?? "").toString().trim().toLowerCase();

    if (s == "collector" || s == "collectors") return "collector";
    if (residenceRoles.contains(s)) return "residence";

    // Hidden roles
    if (s == "admin" || s == "admins") return "admin";
    if (s == "junkshop" || s == "junkshops") return "junkshop";

    // IMPORTANT: do NOT default to residence (causes mislabel)
    return "unknown";
  }

  bool _isVerifiedResident(Map<String, dynamic> data) {
    final adminVerified = data["adminVerified"] == true;
    final adminStatus = (data["adminStatus"] ?? "").toString().toLowerCase();
    // only approved counts as resident in Users tab
    return adminVerified && adminStatus == "approved";
  }

  Color _roleColor(String role) {
    switch (role) {
      case "collector":
        return Colors.cyanAccent;
      case "residence":
        return Colors.greenAccent;
      default:
        return Colors.white54;
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
        style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }

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
        style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w900, fontSize: 12),
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
          const SizedBox(height: 6),

          // ✅ Simple header row
          const Row(
            children: [
              Icon(Icons.people, color: Colors.white),
              SizedBox(width: 10),
              Text(
                "User Management",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ✅ Search
          _panel(
            child: TextField(
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
          ),

          const SizedBox(height: 10),

          // ✅ Filters
          _sectionLabel("Filter"),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filterRoles.map((role) {
              final selected = _roleFilter == role;

              // ✅ Special label for restricted (optional)
              final labelWidget = role == "restricted"
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("RESTRICTED"),
                        const SizedBox(width: 6),
                        Icon(Icons.block, size: 14, color: selected ? Colors.orangeAccent : Colors.white54),
                      ],
                    )
                  : Text(role.toUpperCase());

              return ChoiceChip(
                label: labelWidget,
                selected: selected,
                onSelected: (_) => setState(() => _roleFilter = role),
                backgroundColor: const Color(0xFF141B2D),
                selectedColor: role == "restricted"
                    ? Colors.orangeAccent.withOpacity(0.18)
                    : const Color(0xFF1FA9A7).withOpacity(0.22),
                labelStyle: TextStyle(
                  color: selected
                      ? (role == "restricted" ? Colors.orangeAccent : const Color(0xFF1FA9A7))
                      : Colors.white.withOpacity(0.75),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected
                      ? (role == "restricted"
                          ? Colors.orangeAccent.withOpacity(0.6)
                          : const Color(0xFF1FA9A7).withOpacity(0.6))
                      : Colors.white.withOpacity(0.08),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
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

                  // Hide admin + junkshop + unknown
                  if (role == "admin" || role == "junkshop" || role == "unknown") return false;

                  // status restricted?
                  final status = (data["status"] ?? "active").toString().trim().toLowerCase();
                  final restricted = status == "restricted";

                  // ✅ If filter is restricted, show ONLY restricted (role can be collector/residence)
                  if (_roleFilter == "restricted") {
                    // still hide unverified residence for cleanliness? up to you.
                    // BUT since these are restricted users, admins usually want to see them all.
                    // We'll show restricted regardless of resident verification.
                    return restricted && _matchesSearch(d, data, q);
                  }

                  // ✅ Existing rule:
                  // If it is a resident/user, show ONLY if admin approved.
                  if (role == "residence" && !_isVerifiedResident(data)) return false;

                  final matchesSearch = _matchesSearch(d, data, q);
                  final matchesRole = _roleFilter == "all" || role == _roleFilter;

                  return matchesSearch && matchesRole;
                }).toList();

                if (filtered.isEmpty) {
                  return _emptyState();
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
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

                    final cardColor =
                        restricted ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.045);

                    final borderColor = restricted
                        ? Colors.orangeAccent.withOpacity(0.25)
                        : Colors.white.withOpacity(0.07);

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 4,
                            height: restricted ? 84 : 78,
                            decoration: BoxDecoration(
                              color: (restricted ? Colors.orangeAccent : _roleColor(role))
                                  .withOpacity(0.55),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(width: 12),

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
                                      fontWeight: FontWeight.w900,
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

                          const SizedBox(width: 10),

                          if (!managing)
                            _quietButton(
                              label: "Manage",
                              onTap: _busy ? null : () => setState(() => _manageUid = uid),
                            )
                          else
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _quietOutlinedButton(
                                  label: "Close",
                                  onTap: _busy ? null : () => setState(() => _manageUid = null),
                                ),
                                const SizedBox(height: 8),
                                _primaryActionButton(
                                  label: restricted ? "Unrestrict" : "Restrict",
                                  background: restricted ? Colors.greenAccent : Colors.orangeAccent,
                                  onTap: _busy
                                      ? null
                                      : () => _setRestricted(
                                            uid: uid,
                                            name: title,
                                            restricted: !restricted,
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

  bool _matchesSearch(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
    Map<String, dynamic> data,
    String q,
  ) {
    final name = (data["Name"] ?? data["name"] ?? "").toString();
    final email = (data["emailDisplay"] ?? data["Email"] ?? data["email"] ?? "").toString();

    return q.isEmpty ||
        name.toLowerCase().contains(q) ||
        email.toLowerCase().contains(q) ||
        d.id.toLowerCase().contains(q);
  }

  // ---------- UI helpers ----------
  Widget _panel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: child,
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withOpacity(0.60),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.045),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Text(
          "No users found.",
          style: TextStyle(color: Colors.white.withOpacity(0.75), fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _quietButton({required String label, required VoidCallback? onTap}) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white.withOpacity(0.85),
        backgroundColor: Colors.white.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withOpacity(0.07)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }

  Widget _quietOutlinedButton({required String label, required VoidCallback? onTap}) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: BorderSide(color: Colors.white.withOpacity(0.12)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }

  Widget _primaryActionButton({
    required String label,
    required Color background,
    required VoidCallback? onTap,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        elevation: 0,
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}
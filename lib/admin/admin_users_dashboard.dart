import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

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

  // ✅ Role filter for clickable chips
  String _roleFilter = "all"; // all | admin | user | collector

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

  FirebaseFunctions get _fn => FirebaseFunctions.instanceFor(region: "asia-southeast1");

  Future<void> _callVerifyJunkshop(String uid) async {
    final callable = _fn.httpsCallable("verifyJunkshop");
    await callable.call({"uid": uid});
  }

  Future<void> _callAdminDeleteUser(String uid) async {
    final callable = _fn.httpsCallable("adminDeleteUser");
    await callable.call({"uid": uid});
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

  Future<void> _deleteUserFlow(String uid, String label) async {
    final ok = await _confirm<bool>(
      title: "Delete User?",
      body: "This will permanently delete the entire account ($label).",
      yesValue: true,
      yesLabel: "Delete",
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _callAdminDeleteUser(uid);
      _toast("Deleted $label");
    } catch (e) {
      _toast("Delete failed: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Storage helpers ----------
  final Map<String, Future<String>> _urlCache = {};

  Future<String> _storageUrl(String path) {
    return _urlCache.putIfAbsent(
      path,
      () => FirebaseStorage.instance.ref(path).getDownloadURL(),
    );
  }

  void _showImageDialog(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  // ---------- Requests helpers ----------
  Future<void> _setApproved(DocumentReference ref, bool value) async {
    await ref.update({'approved': value});
  }

  Future<void> _deleteRequest(DocumentReference ref) async {
    await ref.delete();
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
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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

                // Search
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
                        const SizedBox(height: 24),
                        _permitRequestsSection(),
                        const SizedBox(height: 24),
                        _collectorRequestsSection(),
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
        const Text("Users", style: TextStyle(color: Colors.white, fontSize: 18)),
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

            // ✅ Hide junkshops from Users list
            final allDocs = snap.data!.docs.where((d) {
              final data = d.data();
              final role = _normRole(data["Roles"] ?? data["roles"]);
              return role != "junkshop";
            }).toList();

            final counts = <String, int>{"admin": 0, "user": 0, "collector": 0, "unknown": 0};
            for (final d in allDocs) {
              final role = _normRole(d.data()["Roles"] ?? d.data()["roles"]);
              counts[role] = (counts[role] ?? 0) + 1;
            }

            // ✅ Apply search + role filter
            final filtered = allDocs.where((d) {
              final data = d.data();
              final email = (data["Email"] ?? data["email"] ?? "").toString();
              final name = (data["Name"] ?? data["name"] ?? "").toString();
              final role = _normRole(data["Roles"] ?? data["roles"]);

              final matchesSearch = _matchesQuery([email, name, role, d.id]);
              final matchesRole = (_roleFilter == "all") || (role == _roleFilter);

              return matchesSearch && matchesRole;
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _countRow([
                  _countChip("Total", allDocs.length, filterValue: "all"),
                  _countChip("Admins", counts["admin"] ?? 0, filterValue: "admin"),
                  _countChip("Users", counts["user"] ?? 0, filterValue: "user"),
                  _countChip("Collectors", counts["collector"] ?? 0, filterValue: "collector"),
                ]),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  const Text("No users found.", style: TextStyle(color: Colors.white))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final d = filtered[i];
                      return _userTile(uid: d.id, data: d.data());
                    },
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
                  _countChipStatic("Total", allDocs.length),
                  _countChipStatic("Verified", verifiedCount),
                  _countChipStatic("Pending", pendingCount),
                ]),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  const Text("No junkshops found.", style: TextStyle(color: Colors.white))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final d = filtered[i];
                      return _junkshopTile(uid: d.id, data: d.data());
                    },
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _permitRequestsSection() {
    final permitsStream = FirebaseFirestore.instance
        .collection("permitRequests")
        .where("approved", isEqualTo: false)
        .snapshots();

    return _requestSection(
      title: "Permit Requests",
      stream: permitsStream,
      emptyText: "No New Permit Requests",
      tileBuilder: (d) {
        final data = d.data();
        final shopName = (data["shopName"] ?? "Unknown").toString();
        final email = (data["email"] ?? "").toString();
        final permitPath = (data["permitPath"] ?? "").toString();

        return _requestCard(
          title: shopName,
          subtitle: email,
          imagePath: permitPath,
          onApprove: () async {
            setState(() => _busy = true);
            try {
              await _setApproved(d.reference, true);
              _toast("Approved $shopName");
            } catch (e) {
              _toast("Approve failed: $e");
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
          onReject: () async {
            setState(() => _busy = true);
            try {
              await _setApproved(d.reference, false);
              _toast("Rejected $shopName");
            } catch (e) {
              _toast("Reject failed: $e");
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
          onDelete: () async {
            final ok = await _confirm<bool>(
              title: "Delete permit request?",
              body: "This will delete the request document in Firestore.",
              yesValue: true,
              yesLabel: "Delete",
            );
            if (ok != true) return;

            setState(() => _busy = true);
            try {
              await _deleteRequest(d.reference);
              _toast("Deleted request");
            } catch (e) {
              _toast("Delete failed: $e");
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
        );
      },
    );
  }

  // ✅ Assumes collection name: collectorRequests
  Widget _collectorRequestsSection() {
  // ✅ Collectors are saved in Users collection (NOT collectorRequests)
  final usersStream = FirebaseFirestore.instance.collection("Users").snapshots();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text("Collector Requests", style: TextStyle(color: Colors.white, fontSize: 18)),
      const SizedBox(height: 10),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: usersStream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Text("Collector Requests ERROR: ${snap.error}", style: const TextStyle(color: Colors.red));
          }
          if (!snap.hasData) {
            return const Text("Loading Collector Requests...", style: TextStyle(color: Colors.white));
          }

          final all = snap.data!.docs;

          // ✅ pending collectors = role collector + verified false + status pending
          final pending = all.where((d) {
            final data = d.data();
            final role = _normRole(data["Roles"] ?? data["roles"]);
            final verified = data["verified"] == true;
            final status = (data["Status"] ?? data["status"] ?? "pending")
                .toString()
                .toLowerCase()
                .trim();

            return role == "collector" && !verified && status == "pending";
          }).toList();

          // newest first if you have createdAt
          pending.sort((a, b) {
            final ta = a.data()["createdAt"];
            final tb = b.data()["createdAt"];
            final da = (ta is Timestamp) ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            final db = (tb is Timestamp) ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });

          if (pending.isEmpty) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Column(
                children: const [
                  Icon(Icons.mark_email_read, color: Colors.greenAccent, size: 40),
                  SizedBox(height: 10),
                  Text("No New Collector Requests", style: TextStyle(color: Colors.white, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pending.length,
            itemBuilder: (context, i) {
              final d = pending[i];
              final uid = d.id;
              final data = d.data();

              final name = (data["Name"] ?? data["name"] ?? "Unknown Collector").toString();
              final email = (data["Email"] ?? data["email"] ?? "").toString();

              // ✅ Your collector submission stores a DOWNLOAD URL (not a storage path)
              final imgUrl = (data["permitUrl"] ?? data["idImageUrl"] ?? "").toString();

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
                    Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    if (email.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(email, style: TextStyle(color: Colors.grey.shade300)),
                      ),
                    const SizedBox(height: 8),

                    Row(
                      children: [
                        const Text("pending", style: TextStyle(color: Colors.orangeAccent)),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            final ok = await _confirm<bool>(
                              title: "Approve collector?",
                              body: "Approve $name as collector?",
                              yesValue: true,
                              yesLabel: "Approve",
                            );
                            if (ok != true) return;

                            setState(() => _busy = true);
                            try {
                              await FirebaseFirestore.instance.collection("Users").doc(uid).update({
                                "verified": true,
                                "Status": "approved",
                                "updatedAt": FieldValue.serverTimestamp(),
                              });
                              _toast("Approved $name");
                            } catch (e) {
                              _toast("Approve failed: $e");
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                          child: const Text("Approve"),
                        ),
                        TextButton(
                          onPressed: () async {
                            final ok = await _confirm<bool>(
                              title: "Reject collector?",
                              body: "Reject $name collector request?",
                              yesValue: true,
                              yesLabel: "Reject",
                            );
                            if (ok != true) return;

                            setState(() => _busy = true);
                            try {
                              await FirebaseFirestore.instance.collection("Users").doc(uid).update({
                                "verified": false,
                                "Status": "rejected",
                                "updatedAt": FieldValue.serverTimestamp(),
                              });
                              _toast("Rejected $name");
                            } catch (e) {
                              _toast("Reject failed: $e");
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                          child: const Text("Reject"),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // ✅ View uploaded ID image
                    if (imgUrl.isEmpty)
                      const Text("No ID image uploaded.", style: TextStyle(color: Colors.white))
                    else
                      GestureDetector(
                        onTap: () => _showImageDialog(imgUrl),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            imgUrl,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, e, __) => Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text("Render error: $e", style: const TextStyle(color: Colors.redAccent)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ],
  );
}
  // ---------- Reusable request section ----------
  Widget _requestSection({
    required String title,
    required Stream<QuerySnapshot<Map<String, dynamic>>> stream,
    required String emptyText,
    required Widget Function(QueryDocumentSnapshot<Map<String, dynamic>> d) tileBuilder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 18)),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: stream,
          builder: (context, snap) {
            if (snap.hasError) {
              return Text("$title ERROR: ${snap.error}", style: const TextStyle(color: Colors.red));
            }
            if (!snap.hasData) {
              return Text("Loading $title...", style: const TextStyle(color: Colors.white));
            }

            final docs = snap.data!.docs;

            if (docs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.mark_email_read, color: Colors.greenAccent, size: 40),
                    const SizedBox(height: 10),
                    Text(emptyText, style: const TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              itemBuilder: (context, i) => tileBuilder(docs[i]),
            );
          },
        ),
      ],
    );
  }

  // ---------- Request card UI ----------
  Widget _requestCard({
    required String title,
    String? subtitle,
    required String imagePath,
    required Future<void> Function() onApprove,
    required Future<void> Function() onReject,
    required Future<void> Function() onDelete,
  }) {
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
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          if ((subtitle ?? "").isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(subtitle!, style: TextStyle(color: Colors.grey.shade300)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text("pending", style: TextStyle(color: Colors.orangeAccent)),
              const Spacer(),
              TextButton(onPressed: onApprove, child: const Text("Approve")),
              TextButton(onPressed: onReject, child: const Text("Reject")),
              IconButton(
                tooltip: "Delete request",
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (imagePath.isEmpty)
            const Text("No image path.", style: TextStyle(color: Colors.white))
          else
            FutureBuilder<String>(
              future: _storageUrl(imagePath),
              builder: (context, urlSnap) {
                if (urlSnap.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                if (urlSnap.hasError || !urlSnap.hasData) {
                  return Text("Image failed: ${urlSnap.error}", style: const TextStyle(color: Colors.redAccent));
                }

                final url = urlSnap.data!;
                return GestureDetector(
                  onTap: () => _showImageDialog(url),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      url,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ---------- Tiles ----------
  Widget _userTile({required String uid, required Map<String, dynamic> data}) {
    final email = (data["Email"] ?? data["email"] ?? "").toString();
    final name = (data["Name"] ?? data["name"] ?? "").toString();
    final role = _normRole(data["Roles"] ?? data["roles"]);

    final title = name.isNotEmpty ? name : (email.isNotEmpty ? email : uid);

    Color roleColor;
    switch (role) {
      case "admin":
        roleColor = Colors.redAccent;
        break;
      case "collector":
        roleColor = Colors.cyanAccent;
        break;
      case "user":
        roleColor = Colors.greenAccent;
        break;
      default:
        roleColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          if (email.isNotEmpty && name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(email, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  role,
                  style: TextStyle(
                    color: roleColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: "Delete user",
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () async => _deleteUserFlow(uid, title),
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
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
          if (verified)
            IconButton(
              tooltip: "Delete verified junkshop",
              onPressed: () async => _deleteUserFlow(uid, shopName),
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            ),
        ],
      ),
    );
  }

  // ---------- Small UI widgets ----------
  Widget _countRow(List<Widget> chips) {
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  // ✅ Clickable filter chip for USERS section
  Widget _countChip(String label, int value, {required String filterValue}) {
    final isSelected = filterValue == _roleFilter;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _roleFilter = filterValue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withOpacity(0.22) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? primaryColor.withOpacity(0.55) : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Text(
          "$label: $value",
          style: TextStyle(
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // Static chip (for junkshop counts)
  Widget _countChipStatic(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Text("$label: $value", style: const TextStyle(color: Colors.white)),
    );
  }
}

// ======================= collector_details_page.dart =======================

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../admin_helpers.dart';
import '../admin_storage_cache.dart';
import '../admin_theme_page.dart';

class CollectorDetailsPage extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> requestRef;
  const CollectorDetailsPage({super.key, required this.requestRef});

  @override
  State<CollectorDetailsPage> createState() => _CollectorDetailsPageState();
}

class _CollectorDetailsPageState extends State<CollectorDetailsPage> {
  bool _busy = false;

  Future<void> _deleteStorageIfAny(String path) async {
    if (path.trim().isEmpty) return;
    try {
      await FirebaseStorage.instance.ref(path).delete();
    } catch (_) {}
  }

  /// ✅ Admin rejects:
  /// - marks collectorRequests/{uid} as rejected
  /// - restores Users/{uid} back to normal user state (keeps base profile)
  /// - deletes permit file if any
  Future<void> _rejectCollectorAndRestoreUser(
    String uid, {
    String permitPath = "",
  }) async {
    // 1) delete uploaded ID file (optional)
    await _deleteStorageIfAny(permitPath);

    final userRef = FirebaseFirestore.instance.collection("Users").doc(uid);
    final reqRef = FirebaseFirestore.instance.collection("collectorRequests").doc(uid);

    // 2) read current role so we don't accidentally downgrade admin/junkshop
    final snap = await userRef.get();
    final data = snap.data() ?? {};
    final existingRole = (data["role"] ?? data["Roles"] ?? "user")
        .toString()
        .trim()
        .toLowerCase();

    final roleToSave =
        (existingRole == "collector" || existingRole.isEmpty) ? "user" : existingRole;

    final batch = FirebaseFirestore.instance.batch();

    // 3) mark request rejected (so it disappears from admin list)
    batch.set(reqRef, {
      "status": "rejected",
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 4) restore clean user state but keep base profile (name/email/etc.)
    batch.set(userRef, {
      "collectorStatus": "rejected",

      // remove application-only fields
      "collectorSubmittedAt": FieldValue.delete(),
      "collectorUpdatedAt": FieldValue.delete(),
      "collectorKyc": FieldValue.delete(),

      // keep role safe
      "role": roleToSave,
      "Roles": roleToSave,

      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// ✅ Admin approves:
  /// - collectorRequests/{uid} => status: adminApproved (junkshops can see it)
  /// - Users/{uid} => collectorStatus: adminApproved
  /// - DOES NOT promote role to collector (junkshop does final step)
  Future<void> _adminApprove(String uid) async {
    final reqRef = FirebaseFirestore.instance.collection("collectorRequests").doc(uid);
    final userRef = FirebaseFirestore.instance.collection("Users").doc(uid);

    final batch = FirebaseFirestore.instance.batch();

    batch.set(reqRef, {
      "status": "adminApproved",
      "adminReviewedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(userRef, {
      "collectorStatus": "adminApproved",
      "collectorUpdatedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  void _showImageDialog(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.85),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.bg,
        foregroundColor: Colors.white,
        title: const Text("Collector Details"),
      ),
      body: AdminTheme.background(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.requestRef.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Text(
                  "Error: ${snap.error}",
                  style: const TextStyle(color: Colors.redAccent),
                ),
              );
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (!snap.data!.exists) {
              return const Center(
                child: Text("Request not found.", style: TextStyle(color: Colors.white70)),
              );
            }

            final data = snap.data!.data() ?? {};
            final uid = snap.data!.id;

            // ✅ from collectorRequests
            final name = (data["publicName"] ?? "Collector").toString();
            final email = (data["emailDisplay"] ?? "").toString();
            final status = (data["status"] ?? "").toString();

            final permitPath = (data["permitPath"] ?? "").toString();
            final permitUrlOld = (data["permitUrl"] ?? "").toString(); // optional legacy

            Widget imageBlock;
            if (permitPath.isNotEmpty) {
              imageBlock = FutureBuilder<String>(
                future: AdminStorageCache.url(permitPath),
                builder: (context, s) {
                  if (s.connectionState == ConnectionState.waiting) {
                    return const SizedBox(
                      height: 220,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  if (s.hasError || !s.hasData) {
                    return Text(
                      "Image failed: ${s.error}",
                      style: const TextStyle(color: Colors.redAccent),
                    );
                  }
                  final url = s.data!;
                  return GestureDetector(
                    onTap: () => _showImageDialog(url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        url,
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              );
            } else if (permitUrlOld.isNotEmpty) {
              imageBlock = GestureDetector(
                onTap: () => _showImageDialog(permitUrlOld),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    permitUrlOld,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            } else {
              imageBlock =
                  const Text("No ID image uploaded.", style: TextStyle(color: Colors.white70));
            }

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (email.isNotEmpty)
                    Text(email, style: TextStyle(color: Colors.grey.shade300)),
                  const SizedBox(height: 6),
                  Text("UID: $uid", style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 6),
                  Text("Status: $status", style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),

                  imageBlock,
                  const SizedBox(height: 16),

                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text("Processing...", style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text("Approve"),
                          onPressed: _busy
                              ? null
                              : () async {
                                  final ok = await AdminHelpers.confirm<bool>(
                                    context: context,
                                    title: "Approve collector?",
                                    body: "Approve $name? (This makes it visible to junkshops)",
                                    yesValue: true,
                                    yesLabel: "Approve",
                                  );
                                  if (ok != true) return;

                                  setState(() => _busy = true);
                                  try {
                                    await _adminApprove(uid);
                                    if (mounted) AdminHelpers.toast(context, "Approved $name");
                                    if (mounted) Navigator.pop(context);
                                  } catch (e) {
                                    if (mounted) AdminHelpers.toast(context, "Approve failed: $e");
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.close),
                          label: const Text("Reject"),
                          onPressed: _busy
                              ? null
                              : () async {
                                  final ok = await AdminHelpers.confirm<bool>(
                                    context: context,
                                    title: "Reject collector?",
                                    body: "Reject $name? This keeps the account as a normal user.",
                                    yesValue: true,
                                    yesLabel: "Reject",
                                  );
                                  if (ok != true) return;

                                  setState(() => _busy = true);
                                  try {
                                    await _rejectCollectorAndRestoreUser(
                                      uid,
                                      permitPath: permitPath,
                                    );
                                    if (mounted) {
                                      AdminHelpers.toast(context, "Rejected $name. User restored.");
                                      Navigator.pop(context);
                                    }
                                  } catch (e) {
                                    if (mounted) AdminHelpers.toast(context, "Reject failed: $e");
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
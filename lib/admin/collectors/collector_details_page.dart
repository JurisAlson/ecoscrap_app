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

  /// ✅ Admin rejects:
  /// - deletes permit file if any
  /// - restores Users/{uid} back to normal user state (keeps base profile)
  /// - marks collectorRequests/{uid} as rejected (keeps history)
  /// - clears stale permit pointers so next re-submit won't show broken image
  Future<void> _rejectCollectorAndRestoreUser(
    String uid, {
    String permitPath = "",
  }) async {
    // 1) delete uploaded ID file (optional)
    if (permitPath.trim().isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(permitPath).delete();
      } catch (_) {}
    }

    final userRef = FirebaseFirestore.instance.collection("Users").doc(uid);
    final reqRef = FirebaseFirestore.instance.collection("collectorRequests").doc(uid);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      // Read user to preserve role safely (do not downgrade admin/junkshop)
      final userSnap = await tx.get(userRef);
      final userData = (userSnap.data() as Map<String, dynamic>?) ?? {};

      // preserve exact previous role string if it was admin/junkshop/user etc.
      final rawRole = userData["role"] ?? userData["Roles"] ?? "user";
      final rawRoleStr = rawRole.toString().trim();
      final rawLower = rawRoleStr.toLowerCase();

      // If user was collector (or blank), restore to user; otherwise keep exact role
      final roleToSave = (rawLower == "collector" || rawRoleStr.isEmpty) ? "user" : rawRoleStr;

      // 2) restore clean user state but keep base profile fields
      tx.set(userRef, {
        "collectorStatus": "rejected",

        // remove application-only fields
        "collectorSubmittedAt": FieldValue.delete(),
        "collectorUpdatedAt": FieldValue.delete(),
        "collectorKyc": FieldValue.delete(),

        // remove junkshop verification flags if they existed
        "junkshopVerified": FieldValue.delete(),
        "junkshopStatus": FieldValue.delete(),

        // keep role safe
        "role": roleToSave,
        "Roles": roleToSave,

        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3) mark request rejected (keeps history + allows resubmit)
      // and clear stale permit pointers (so admin doesn't see broken image later)
      tx.set(reqRef, {
        "status": "rejected",
        "acceptedByJunkshopUid": "",
        "acceptedAt": FieldValue.delete(),
        "rejectedByJunkshops": [],
        "permitPath": FieldValue.delete(),
        "permitUrl": FieldValue.delete(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// ✅ Admin approves (NEW FLOW):
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

            final isPending = status.toLowerCase() == "pending";

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
                  if (email.isNotEmpty) Text(email, style: TextStyle(color: Colors.grey.shade300)),
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
                          onPressed: (_busy || !isPending)
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
                          onPressed: (_busy || !isPending)
                              ? null
                              : () async {
                                  final ok = await AdminHelpers.confirm<bool>(
                                    context: context,
                                    title: "Reject collector?",
                                    body: "Reject $name? This restores the account to a normal user and allows re-submit.",
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
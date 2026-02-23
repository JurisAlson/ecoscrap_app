import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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

  Future<void> _rejectCollectorAndRestoreUser(String uid) async {
    final db = FirebaseFirestore.instance;

    final userRef = db.collection("Users").doc(uid);
    final reqRef = db.collection("collectorRequests").doc(uid);
    final kycRef = db.collection("collectorKYC").doc(uid);

    // 1) Read KYC doc to get ONLY filename (admin-only)
    String kycFileName = "";
    try {
      final kycSnap = await kycRef.get();
      final kycData = kycSnap.data() ?? {};
      kycFileName = (kycData["kycFileName"] ?? "").toString();
    } catch (_) {}

    // 2) Delete uploaded KYC file (if any) using reconstructed path
    if (kycFileName.trim().isNotEmpty) {
      final path = "kyc/$uid/$kycFileName";
      try {
        await FirebaseStorage.instance.ref(path).delete();
      } catch (_) {}
    }

    // 3) Transaction: restore user + mark request rejected + delete KYC doc pointer
    await db.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final userData = userSnap.data() ?? {};

      final rawRole = userData["role"] ?? userData["Roles"] ?? "user";
      final rawRoleStr = rawRole.toString().trim();
      final rawLower = rawRoleStr.toLowerCase();

      final roleToSave = (rawLower == "collector" || rawRoleStr.isEmpty) ? "user" : rawRoleStr;

      tx.set(userRef, {
        "collectorStatus": "rejected",
        "collectorSubmittedAt": FieldValue.delete(),
        "collectorUpdatedAt": FieldValue.delete(),
        "collectorKyc": FieldValue.delete(),

        "junkshopVerified": FieldValue.delete(),
        "junkshopStatus": FieldValue.delete(),

        "role": roleToSave,
        "Roles": roleToSave,

        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(reqRef, {
        "status": "rejected",
        "acceptedByJunkshopUid": "",
        "acceptedAt": FieldValue.delete(),
        "rejectedByJunkshops": [],
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.delete(kycRef);
    });
  }

  Future<void> _adminApprove(String uid) async {
    final db = FirebaseFirestore.instance;
    final reqRef = db.collection("collectorRequests").doc(uid);
    final userRef = db.collection("Users").doc(uid);

    final batch = db.batch();

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

            final name = (data["publicName"] ?? "Collector").toString();
            final email = (data["emailDisplay"] ?? "").toString();
            final status = (data["status"] ?? "").toString();
            final isPending = status.toLowerCase() == "pending";

            final kycRef = FirebaseFirestore.instance.collection("collectorKYC").doc(uid);

            final imageBlock = FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: kycRef.get(),
              builder: (context, kycSnap) {
                if (kycSnap.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 220,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }

                final kycData = kycSnap.data?.data() ?? {};
                final kycFileName = (kycData["kycFileName"] ?? "").toString();

                if (kycFileName.isEmpty) {
                  return const Text("No ID file uploaded.", style: TextStyle(color: Colors.white70));
                }

                final permitPath = "kyc/$uid/$kycFileName";

                return FutureBuilder<String>(
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
                        "File failed: ${s.error}",
                        style: const TextStyle(color: Colors.redAccent),
                      );
                    }

                    final url = s.data!;
                    final isPdf = kycFileName.toLowerCase().endsWith(".pdf");

                    if (isPdf) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("KYC file is a PDF.", style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: () => _showImageDialog(url),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text("Open PDF"),
                          ),
                        ],
                      );
                    }

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
              },
            );

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
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
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
                                    await _rejectCollectorAndRestoreUser(uid);
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
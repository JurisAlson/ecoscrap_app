import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../admin_helpers.dart';
import '../admin_storage_cache.dart';
import '../admin_theme_page.dart';

class CollectorDetailsPage extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> userRef;

  const CollectorDetailsPage({super.key, required this.userRef});

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

  Future<void> _revertCollectorApplicantToUser(String uid) async {
    await FirebaseFirestore.instance.collection("Users").doc(uid).set({
      "Roles": "user",
      "role": "user",

      "collectorStatus": "rejected",
      "adminVerified": false,
      "adminStatus": "rejected",
      "adminReviewedAt": FieldValue.serverTimestamp(),
      "collectorActive": false,

      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
          stream: widget.userRef.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text("Error: ${snap.error}", style: const TextStyle(color: Colors.redAccent)));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2));
            }
            if (!snap.data!.exists) {
              return const Center(child: Text("User not found.", style: TextStyle(color: Colors.white70)));
            }

            final data = snap.data!.data() ?? {};
            final uid = snap.data!.id;

            final name = (data["Name"] ?? data["name"] ?? "Collector").toString();
            final email = (data["emailDisplay"] ?? data["Email"] ?? data["email"] ?? "").toString();

            final kyc = (data["kyc"] is Map) ? (data["kyc"] as Map) : const {};
            final permitPath = (kyc["permitPath"] ?? "").toString();
            final permitUrlOld = (kyc["permitUrl"] ?? "").toString();

            Widget imageBlock;
            if (permitPath.isNotEmpty) {
              imageBlock = FutureBuilder<String>(
                future: AdminStorageCache.url(permitPath),
                builder: (context, s) {
                  if (s.connectionState == ConnectionState.waiting) {
                    return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                  }
                  if (s.hasError || !s.hasData) {
                    return Text("Image failed: ${s.error}", style: const TextStyle(color: Colors.redAccent));
                  }
                  final url = s.data!;
                  return GestureDetector(
                    onTap: () => _showImageDialog(url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(url, height: 220, width: double.infinity, fit: BoxFit.cover),
                    ),
                  );
                },
              );
            } else if (permitUrlOld.isNotEmpty) {
              imageBlock = GestureDetector(
                onTap: () => _showImageDialog(permitUrlOld),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(permitUrlOld, height: 220, width: double.infinity, fit: BoxFit.cover),
                ),
              );
            } else {
              imageBlock = const Text("No ID image uploaded.", style: TextStyle(color: Colors.white70));
            }

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                  const SizedBox(height: 6),
                  if (email.isNotEmpty) Text(email, style: TextStyle(color: Colors.grey.shade300)),
                  const SizedBox(height: 6),
                  Text("UID: $uid", style: const TextStyle(color: Colors.white54)),
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
                          onPressed: _busy
                              ? null
                              : () async {
                                  final ok = await AdminHelpers.confirm<bool>(
                                    context: context,
                                    title: "Approve collector?",
                                    body: "Approve $name?",
                                    yesValue: true,
                                    yesLabel: "Approve",
                                  );
                                  if (ok != true) return;

                                  setState(() => _busy = true);
                                  try {
                                    await FirebaseFirestore.instance.collection("Users").doc(uid).set({
                                      "Roles": "collector",
                                      "role": "collector",
                                      "collectorStatus": "approved",

                                      "adminVerified": true,
                                      "adminStatus": "approved",
                                      "adminReviewedAt": FieldValue.serverTimestamp(),
                                      "collectorActive": true,

                                      "updatedAt": FieldValue.serverTimestamp(),
                                    }, SetOptions(merge: true));

                                    if (mounted) AdminHelpers.toast(context, "Admin approved $name");
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
                                    body: "Reject $name? This reverts the account back to normal user.",
                                    yesValue: true,
                                    yesLabel: "Reject",
                                  );
                                  if (ok != true) return;

                                  setState(() => _busy = true);
                                  try {
                                    await _deleteStorageIfAny(permitPath);
                                    await _revertCollectorApplicantToUser(uid);

                                    if (mounted) AdminHelpers.toast(context, "Admin rejected $name");
                                    if (mounted) Navigator.pop(context);
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
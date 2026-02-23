import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../admin_helpers.dart';
import '../admin_theme_page.dart';

class PermitDetailsPage extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> requestRef;

  const PermitDetailsPage({super.key, required this.requestRef});

  @override
  State<PermitDetailsPage> createState() => _PermitDetailsPageState();
}

class _PermitDetailsPageState extends State<PermitDetailsPage> {
  bool _busy = false;

  FirebaseFunctions get _fn => FirebaseFunctions.instanceFor(region: "asia-southeast1");

  Future<void> _reviewPermit(String uid, String decision) async {
    final callable = _fn.httpsCallable("reviewPermitRequest");
    await callable.call({
      "uid": uid,
      "decision": decision, // "approved" or "rejected"
    });
  }

  void _showBytesDialog(Uint8List bytes) {
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
                  child: Image.memory(bytes, fit: BoxFit.contain),
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
        title: const Text("Permit Details"),
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

            // docId = uid in your flow, but still safe if uid field exists
            final uid = (data["uid"] ?? snap.data!.id).toString().trim();
            final shopName = (data["shopName"] ?? "Unknown").toString();
            final email = (data["emailDisplay"] ?? data["email"] ?? "").toString();

            // ✅ NEW: store only filename in Firestore
            final permitFileName = (data["permitFileName"] ?? "").toString().trim();
            final hasPermitFile = data["hasPermitFile"] == true;

            // ✅ Reconstruct storage path (NO permitPath stored)
            final permitPath = permitFileName.isEmpty ? "" : "permits/$uid/$permitFileName";

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shopName,
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
                  const SizedBox(height: 16),

                  if (!hasPermitFile || permitFileName.isEmpty)
                    const Text("No permit file uploaded.", style: TextStyle(color: Colors.white70))
                  else
                    FutureBuilder<Uint8List?>(
                      future: FirebaseStorage.instance.ref(permitPath).getData(10 * 1024 * 1024),
                      builder: (context, bytesSnap) {
                        if (bytesSnap.connectionState == ConnectionState.waiting) {
                          return const SizedBox(
                            height: 220,
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        if (bytesSnap.hasError || bytesSnap.data == null) {
                          return Text(
                            "File failed to load: ${bytesSnap.error}",
                            style: const TextStyle(color: Colors.redAccent),
                          );
                        }

                        final bytes = bytesSnap.data!;
                        return GestureDetector(
                          onTap: () => _showBytesDialog(bytes),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.memory(
                              bytes,
                              height: 220,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),

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
                          label: const Text("Approve & Verify"),
                          onPressed: _busy
                              ? null
                              : () async {
                                  final ok = await AdminHelpers.confirm<bool>(
                                    context: context,
                                    title: "Approve permit?",
                                    body: "Approve $shopName and verify the junkshop?",
                                    yesValue: true,
                                    yesLabel: "Approve",
                                  );
                                  if (ok != true) return;

                                  setState(() => _busy = true);
                                  try {
                                    await _reviewPermit(uid, "approved");
                                    if (mounted) AdminHelpers.toast(context, "Approved $shopName");
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
                                    title: "Reject permit?",
                                    body: "Reject $shopName? This keeps the account as a normal user.",
                                    yesValue: true,
                                    yesLabel: "Reject",
                                  );
                                  if (ok != true) return;

                                  setState(() => _busy = true);
                                  try {
                                    await _reviewPermit(uid, "rejected");
                                    if (mounted) AdminHelpers.toast(context, "Rejected. File deleted.");
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

                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
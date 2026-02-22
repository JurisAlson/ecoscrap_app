import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../admin_helpers.dart';
import '../admin_storage_cache.dart';
import '../admin_theme_page.dart';

class PermitDetailsPage extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> requestRef;

  const PermitDetailsPage({super.key, required this.requestRef});

  @override
  State<PermitDetailsPage> createState() => _PermitDetailsPageState();
}

class _PermitDetailsPageState extends State<PermitDetailsPage> {
  bool _busy = false;

  FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: "asia-southeast1");

  Future<void> _callVerifyJunkshop(String uid) async {
    final callable = _fn.httpsCallable("verifyJunkshop");
    await callable.call({"uid": uid});
  }

  Future<void> _deleteStorageIfAny(String path) async {
    if (path.trim().isEmpty) return;
    try {
      await FirebaseStorage.instance.ref(path).delete();
    } catch (_) {}
  }

  /// ✅ Clean revert: do NOT touch user profile fields.
  /// Only reset role + tracking fields so user remains a normal user.
  Future<void> _revertApplicantToUserClean(String uid) async {
    await FirebaseFirestore.instance.collection("Users").doc(uid).set({
      // Keep the user as a user
      "role": "user",
      // If your app still reads this legacy field, keep it too:
      "Roles": "user",

      // Tracking fields only
      "junkshopStatus": "rejected", // pending|approved|rejected
      "activePermitRequestId": FieldValue.delete(),

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
            final uid = (data["uid"] ?? snap.data!.id).toString().trim();
            final shopName = (data["shopName"] ?? "Unknown").toString();
            final email = (data["emailDisplay"] ?? data["email"] ?? "").toString();
            final permitPath = (data["permitPath"] ?? "").toString();

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
                  if (email.isNotEmpty)
                    Text(email, style: TextStyle(color: Colors.grey.shade300)),
                  const SizedBox(height: 6),
                  Text("UID: $uid", style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 16),

                  if (permitPath.isEmpty)
                    const Text("No permit image path.", style: TextStyle(color: Colors.white70))
                  else
                    FutureBuilder<String>(
                      future: AdminStorageCache.url(permitPath),
                      builder: (context, urlSnap) {
                        if (urlSnap.connectionState == ConnectionState.waiting) {
                          return const SizedBox(
                            height: 220,
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        if (urlSnap.hasError || !urlSnap.hasData) {
                          return Text(
                            "Image failed: ${urlSnap.error}",
                            style: const TextStyle(color: Colors.redAccent),
                          );
                        }
                        final url = urlSnap.data!;
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
                                    final reviewedBy = FirebaseAuth.instance.currentUser?.uid;

                                    // ✅ Use a batch so request + user update is consistent
                                    final userRef = FirebaseFirestore.instance.collection("Users").doc(uid);
                                    final batch = FirebaseFirestore.instance.batch();

                                    batch.set(widget.requestRef, {
                                      "status": "approved",
                                      "approved": true,
                                      "reviewedAt": FieldValue.serverTimestamp(),
                                      "reviewedByUid": reviewedBy,
                                      "updatedAt": FieldValue.serverTimestamp(),
                                    }, SetOptions(merge: true));

                                    batch.set(userRef, {
                                      "role": "junkshop",
                                      "Roles": "junkshop", // keep if legacy
                                      "junkshopStatus": "approved",
                                      "activePermitRequestId": FieldValue.delete(), // optional but clean
                                      "updatedAt": FieldValue.serverTimestamp(),
                                    }, SetOptions(merge: true));

                                    await batch.commit();

                                    // Optional: call CF after commit (or before—your choice)
                                    if (uid.isNotEmpty) {
                                      await _callVerifyJunkshop(uid);
                                    }

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
                                    final reviewedBy = FirebaseAuth.instance.currentUser?.uid;

                                    // ✅ Keep the request doc for history (do NOT delete)
                                    await widget.requestRef.set({
                                      "status": "rejected",
                                      "approved": false,
                                      "reviewedAt": FieldValue.serverTimestamp(),
                                      "reviewedByUid": reviewedBy,
                                      "updatedAt": FieldValue.serverTimestamp(),
                                      // optional:
                                      // "rejectionReason": "Incomplete documents",
                                    }, SetOptions(merge: true));

                                    // Optional: delete the permit file on reject
                                    await _deleteStorageIfAny(permitPath);

                                    if (uid.isNotEmpty) {
                                      await _revertApplicantToUserClean(uid);
                                    }

                                    if (mounted) AdminHelpers.toast(context, "Rejected. User restored.");
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

                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      label: const Text("Delete Request", style: TextStyle(color: Colors.redAccent)),
                      onPressed: _busy
                          ? null
                          : () async {
                              final ok = await AdminHelpers.confirm<bool>(
                                context: context,
                                title: "Delete request?",
                                body: "This deletes the request document only.",
                                yesValue: true,
                                yesLabel: "Delete",
                              );
                              if (ok != true) return;

                              setState(() => _busy = true);
                              try {
                                await widget.requestRef.delete();
                                if (mounted) AdminHelpers.toast(context, "Deleted request");
                                if (mounted) Navigator.pop(context);
                              } catch (e) {
                                if (mounted) AdminHelpers.toast(context, "Delete failed: $e");
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            },
                    ),
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
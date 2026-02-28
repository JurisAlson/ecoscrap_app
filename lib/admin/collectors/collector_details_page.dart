import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../admin_helpers.dart';
import '../admin_theme_page.dart';

// 🔐 Crypto (ADMIN APP)
import 'package:ecoscrap_app/security/admin_keys.dart';
import 'package:ecoscrap_app/security/kyc_cyrpto.dart';
import 'package:ecoscrap_app/security/kyc_shared_key.dart';

class CollectorDetailsPage extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> requestRef;
  const CollectorDetailsPage({super.key, required this.requestRef});

  @override
  State<CollectorDetailsPage> createState() => _CollectorDetailsPageState();
}

class _CollectorDetailsPageState extends State<CollectorDetailsPage> {
  bool _busy = false;

  // ✅ Reject:
  // DO NOT delete Storage here (encrypted file).
  // Just mark statuses, and let your retention/cleanup handle actual deletion.
Future<void> _rejectCollectorAndRestoreUser(String uid) async {
  final db = FirebaseFirestore.instance;

  final userRef = db.collection("Users").doc(uid);
  final reqRef = db.collection("collectorRequests").doc(uid);

  await db.runTransaction((tx) async {
    tx.set(userRef, {
      "role": "user",
      "Roles": "user",

      "adminVerified": false,
      "adminStatus": "rejected",
      "adminRejectedAt": FieldValue.serverTimestamp(),

      "collectorActive": false,
      "collectorStatus": "rejected",
      "collectorUpdatedAt": FieldValue.serverTimestamp(),

      // remove assignment so chat + collector access won't persist
      "junkshopId": FieldValue.delete(),
      "junkshopName": FieldValue.delete(),
      "assignedJunkshopUid": FieldValue.delete(),
      "assignedJunkshopName": FieldValue.delete(),

      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    tx.set(reqRef, {
      "status": "rejected",
      "adminRejectedAt": FieldValue.serverTimestamp(),
      "adminStatus": "rejected",
      "adminVerified": false,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  });
}

  Future<void> approveCollector(DocumentReference reqRef) async {
    await reqRef.set({
      "status": "adminApproved",
      "adminApprovedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> rejectCollector(DocumentReference reqRef, {String reason = ""}) async {
    await reqRef.set({
      "status": "rejected",
      "adminRejectedAt": FieldValue.serverTimestamp(),
      "adminRejectReason": reason, // optional
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

Future<void> _adminApprove(String uid) async {
  final db = FirebaseFirestore.instance;

  final reqRef = db.collection("collectorRequests").doc(uid);
  final userRef = db.collection("Users").doc(uid);

  await db.runTransaction((tx) async {
    final reqSnap = await tx.get(reqRef);
    if (!reqSnap.exists) throw Exception("collectorRequests/$uid not found");

    final req = reqSnap.data() ?? {};

    final junkshopId = (req["junkshopId"] ?? "").toString().trim();
    final junkshopName = (req["junkshopName"] ?? "").toString().trim();

    if (junkshopId.isEmpty) {
      throw Exception("Missing junkshopId in collectorRequests/$uid (needed for chat).");
    }

    // 1) request status
    tx.set(reqRef, {
      "status": "adminApproved",
      "adminReviewedAt": FieldValue.serverTimestamp(),
      "adminStatus": "approved",
      "adminVerified": true,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 2) user becomes collector immediately
    tx.set(userRef, {
      "role": "collector",
      "Roles": "collector",

      "adminReviewedAt": FieldValue.serverTimestamp(),
      "adminStatus": "approved",
      "adminVerified": true,

      "collectorActive": true,
      "collectorStatus": "approved",

      // ✅ keep chat the same
      "junkshopId": junkshopId,
      "junkshopName": junkshopName,

      // optional compatibility if anything still reads these:
      "assignedJunkshopUid": junkshopId,
      "assignedJunkshopName": junkshopName,

      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  });
}
  // =====================================================
  // 🔓 ADMIN: download encrypted bytes -> decrypt -> return bytes
  // Works for JPG/PNG. For PDF you still get bytes, but preview needs a PDF widget.
  // =====================================================
  Future<_DecryptedKyc?> _downloadAndDecryptKyc(String uid) async {
    final db = FirebaseFirestore.instance;
    final kycSnap = await db.collection("collectorKYC").doc(uid).get();
    final kyc = kycSnap.data() ?? {};

    final storagePath = (kyc["storagePath"] ?? "").toString();
    if (storagePath.isEmpty) return null;

    final originalFileName = (kyc["originalFileName"] ?? "").toString();

    final ephPubKeyB64 = (kyc["ephPubKeyB64"] ?? "").toString();
    final saltB64 = (kyc["saltB64"] ?? "").toString();
    final nonceB64 = (kyc["nonceB64"] ?? "").toString();
    final macB64 = (kyc["macB64"] ?? "").toString();

    if (ephPubKeyB64.isEmpty || saltB64.isEmpty || nonceB64.isEmpty || macB64.isEmpty) {
      throw Exception("Missing crypto metadata in collectorKYC/$uid");
    }

    // 1) download encrypted blob
    final ref = FirebaseStorage.instance.ref(storagePath);

    // max 12MB (your rules allow 10MB; add small buffer)
    final encryptedBytes = await ref.getData(12 * 1024 * 1024);
    if (encryptedBytes == null) throw Exception("Failed to download encrypted file.");

    // 2) derive AES key using Admin private + collector ephemeral public
    final collectorEphPubBytes = base64Decode(ephPubKeyB64);
    final salt = base64Decode(saltB64);

    final aesKey = await KycSharedKey.deriveForAdmin(
      adminPrivateKeyB64: AdminKeys.adminPrivateKeyB64,
      collectorEphemeralPubKeyBytes: Uint8List.fromList(collectorEphPubBytes),
      salt: salt,
    );

    // 3) decrypt
    final nonce = Uint8List.fromList(base64Decode(nonceB64));
    final macBytes = Uint8List.fromList(base64Decode(macB64));

    final plain = await KycCrypto.decryptBytes(
      cipherText: Uint8List.fromList(encryptedBytes),
      macBytes: macBytes,
      nonce: nonce,
      key: aesKey,
      aad: utf8.encode(uid),
    );

    return _DecryptedKyc(
      bytes: plain,
      originalFileName: originalFileName,
      storagePath: storagePath,
    );
  }

  void _showDecryptedImageDialog(Uint8List bytes) {
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
        title: const Text("Collector Details"),
      ),
      body: AdminTheme.background(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.requestRef.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Text("Error: ${snap.error}",
                    style: const TextStyle(color: Colors.redAccent)),
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

            // ✅ This block now DECRYPTS (no AdminStorageCache.url)
            final kycBlock = FutureBuilder<_DecryptedKyc?>(
              future: _downloadAndDecryptKyc(uid),
              builder: (context, kycSnap) {
                if (kycSnap.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 220,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                if (kycSnap.hasError) {
                  return Text(
                    "KYC decrypt failed: ${kycSnap.error}",
                    style: const TextStyle(color: Colors.redAccent),
                  );
                }

                final kyc = kycSnap.data;
                if (kyc == null) {
                  return const Text("No ID file uploaded.",
                      style: TextStyle(color: Colors.white70));
                }

                final fname = kyc.originalFileName.toLowerCase();
                final isPdf = fname.endsWith(".pdf");

                if (isPdf) {
                  // NOTE: You still have decrypted bytes here.
                  // To preview PDF inside Flutter, add a PDF viewer package.
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text("KYC file is a PDF (decrypted).",
                          style: TextStyle(color: Colors.white70)),
                      SizedBox(height: 8),
                      Text(
                        "PDF preview needs a PDF viewer widget/package.\n"
                        "If you want, I can give you the exact PDF viewer code next.",
                        style: TextStyle(color: Colors.white54, height: 1.3),
                      ),
                    ],
                  );
                }

                // ✅ Preview image (JPG/PNG)
                return GestureDetector(
                  onTap: () => _showDecryptedImageDialog(kyc.bytes),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      kyc.bytes,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
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
                  Text("Status: $status", style: const TextStyle(color: Colors.white70)),
                  const SizedBox(height: 16),

                  kycBlock,
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

class _DecryptedKyc {
  final Uint8List bytes;
  final String originalFileName;
  final String storagePath;

  _DecryptedKyc({
    required this.bytes,
    required this.originalFileName,
    required this.storagePath,
  });
}
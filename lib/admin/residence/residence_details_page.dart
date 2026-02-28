import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../admin_helpers.dart';
import '../admin_theme_page.dart';

// 🔐 Crypto (ADMIN APP) - reuse your existing libs
import 'package:ecoscrap_app/security/admin_keys.dart';
import 'package:ecoscrap_app/security/kyc_cyrpto.dart';
import 'package:ecoscrap_app/security/kyc_shared_key.dart';

class ResidentDetailsPage extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> requestRef;
  const ResidentDetailsPage({super.key, required this.requestRef});

  @override
  State<ResidentDetailsPage> createState() => _ResidentDetailsPageState();
}

class _ResidentDetailsPageState extends State<ResidentDetailsPage> {
  bool _busy = false;

  // ===== UI tokens (match your admin pages) =====
  static const Color _primary = Color(0xFF1FA9A7);

  // ---------- admin actions (UNCHANGED) ----------
  Future<void> _adminApproveResident(String uid) async {
    final db = FirebaseFirestore.instance;

    final reqRef = db.collection("residentRequests").doc(uid);
    final userRef = db.collection("Users").doc(uid);

    await db.runTransaction((tx) async {
      final reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) throw Exception("residentRequests/$uid not found");

      tx.set(reqRef, {
        "status": "adminApproved",
        "adminReviewedAt": FieldValue.serverTimestamp(),
        "adminStatus": "approved",
        "adminVerified": true,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(userRef, {
        "role": "user",
        "Roles": "user",
        "adminReviewedAt": FieldValue.serverTimestamp(),
        "adminStatus": "approved",
        "adminVerified": true,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> _adminRejectResident(String uid, {String reason = ""}) async {
    final db = FirebaseFirestore.instance;

    final reqRef = db.collection("residentRequests").doc(uid);
    final userRef = db.collection("Users").doc(uid);

    await db.runTransaction((tx) async {
      tx.set(reqRef, {
        "status": "rejected",
        "adminRejectedAt": FieldValue.serverTimestamp(),
        "adminRejectReason": reason,
        "adminStatus": "rejected",
        "adminVerified": false,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(userRef, {
        "role": "user",
        "Roles": "user",
        "adminVerified": false,
        "adminStatus": "rejected",
        "adminRejectedAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  // === decrypt residentKYC exactly like collectorKYC ===
  Future<_DecryptedKyc?> _downloadAndDecryptResidentKyc(String uid) async {
    final db = FirebaseFirestore.instance;
    final kycSnap = await db.collection("residentKYC").doc(uid).get();
    final kyc = kycSnap.data() ?? {};

    final storagePath = (kyc["storagePath"] ?? "").toString();
    if (storagePath.isEmpty) return null;

    final originalFileName = (kyc["originalFileName"] ?? "").toString();

    final ephPubKeyB64 = (kyc["ephPubKeyB64"] ?? "").toString();
    final saltB64 = (kyc["saltB64"] ?? "").toString();
    final nonceB64 = (kyc["nonceB64"] ?? "").toString();
    final macB64 = (kyc["macB64"] ?? "").toString();

    if (ephPubKeyB64.isEmpty || saltB64.isEmpty || nonceB64.isEmpty || macB64.isEmpty) {
      throw Exception("Missing crypto metadata in residentKYC/$uid");
    }

    final ref = FirebaseStorage.instance.ref(storagePath);
    final encryptedBytes = await ref.getData(12 * 1024 * 1024);
    if (encryptedBytes == null) throw Exception("Failed to download encrypted file.");

    final residentEphPubBytes = base64Decode(ephPubKeyB64);
    final salt = base64Decode(saltB64);

    final aesKey = await KycSharedKey.deriveForAdmin(
      adminPrivateKeyB64: AdminKeys.adminPrivateKeyB64,
      collectorEphemeralPubKeyBytes: Uint8List.fromList(residentEphPubBytes),
      salt: salt,
    );

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

  // ---------- UI helpers (uniform style) ----------
  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: child,
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withOpacity(0.55),
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _pill(String text, {Color? bg, Color? fg, IconData? icon}) {
    final b = bg ?? Colors.white.withOpacity(0.05);
    final f = fg ?? Colors.white.withOpacity(0.85);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: b,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: f),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(color: f, fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _primaryActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    Color background = _primary,
    Color foreground = Colors.white,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _outlineActionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        icon: Icon(icon),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withOpacity(0.14)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Color _statusAccent(String status) {
    final s = status.toLowerCase();
    if (s == "pending") return Colors.orangeAccent;
    if (s == "adminapproved" || s == "approved") return Colors.greenAccent;
    if (s == "rejected") return Colors.redAccent;
    return Colors.white54;
  }

  // ---------- page ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text("Resident Details"),
      ),
      body: AdminTheme.background(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.requestRef.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Text("Error: ${snap.error}", style: const TextStyle(color: Colors.redAccent)),
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

            final name = (data["publicName"] ?? "Resident").toString();
            final email = (data["emailDisplay"] ?? "").toString();
            final status = (data["status"] ?? "").toString();
            final isPending = status.toLowerCase() == "pending";
            final accent = _statusAccent(status);

            // KYC block (same logic, improved presentation)
            final kycBlock = FutureBuilder<_DecryptedKyc?>(
              future: _downloadAndDecryptResidentKyc(uid),
              builder: (context, kycSnap) {
                if (kycSnap.connectionState == ConnectionState.waiting) {
                  return _panel(
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
                    child: const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  );
                }
                if (kycSnap.hasError) {
                  return _panel(
                    child: Text(
                      "ID decrypt failed: ${kycSnap.error}",
                      style: const TextStyle(color: Colors.redAccent, height: 1.3),
                    ),
                  );
                }

                final kyc = kycSnap.data;
                if (kyc == null) {
                  return _panel(
                    child: Row(
                      children: [
                        Icon(Icons.badge_outlined, color: Colors.white.withOpacity(0.6)),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            "No ID file uploaded.",
                            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final fname = kyc.originalFileName.toLowerCase();
                final isPdf = fname.endsWith(".pdf");

                if (isPdf) {
                  return _panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.picture_as_pdf_outlined, color: Colors.white.withOpacity(0.75)),
                            const SizedBox(width: 10),
                            const Text(
                              "Government ID (PDF)",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "PDF decrypted successfully.\n\n"
                          "To preview it here, add a PDF viewer widget/package (e.g. syncfusion_flutter_pdfviewer or flutter_pdfview).",
                          style: TextStyle(color: Colors.white.withOpacity(0.65), height: 1.35),
                        ),
                      ],
                    ),
                  );
                }

                // ✅ Image preview inside a “document card”
                // ✅ CHANGE: removed filename display (per your request)
                return _panel(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.badge_outlined, color: Colors.white.withOpacity(0.75)),
                          const SizedBox(width: 10),
                          _pill(
                            "Tap to zoom",
                            bg: Colors.white.withOpacity(0.04),
                            fg: Colors.white.withOpacity(0.8),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => _showDecryptedImageDialog(kyc.bytes),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AspectRatio(
                            aspectRatio: 16 / 10,
                            child: Image.memory(
                              kyc.bytes,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                      // ✅ removed:
                      // const SizedBox(height: 10),
                      // Text(kyc.originalFileName, ...)
                    ],
                  ),
                );
              },
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ “Profile header” panel to match your admin style
                  _panel(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _primary.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _primary.withOpacity(0.22)),
                          ),
                          child: const Icon(Icons.home_outlined, color: _primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (email.isNotEmpty)
                                Text(
                                  email,
                                  style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12),
                                ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _pill(
                                    "STATUS: ${status.isEmpty ? "unknown" : status}",
                                    bg: accent.withOpacity(0.14),
                                    fg: accent,
                                    icon: Icons.circle,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  _sectionLabel("Government ID"),
                  kycBlock,

                  const SizedBox(height: 12),

                  // ✅ CHANGE: replace old note with ethical/security responsibility note (per your request)
                  _panel(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.security, color: Colors.blueAccent.withOpacity(0.95), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Confidentiality Notice (Admin Responsibility)\n"
                            "This ID contains sensitive personal information and must be handled with care. "
                            "Access it only for residency verification and never share, screenshot, download, "
                            "or distribute it outside official review procedures. "
                            "You are ethically responsible for maintaining privacy and protecting resident data.",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              height: 1.35,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  if (_busy)
                    _panel(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: const Row(
                        children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 10),
                          Text("Processing...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),

                  if (_busy) const SizedBox(height: 12),

                  _sectionLabel("Admin Actions"),

                  Row(
                    children: [
                      Expanded(
                        child: _primaryActionButton(
                          icon: Icons.check,
                          label: "Approve",
                          onTap: (_busy || !isPending)
                              ? null
                              : () async {
                                  final ok = await AdminHelpers.confirm<bool>(
                                    context: context,
                                    title: "Approve resident?",
                                    body: "Approve $name for Barangay Pulo access?",
                                    yesValue: true,
                                    yesLabel: "Approve",
                                  );
                                  if (ok != true) return;

                                  setState(() => _busy = true);
                                  try {
                                    await _adminApproveResident(uid);
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
                        child: _outlineActionButton(
                          icon: Icons.close,
                          label: "Reject",
                          onTap: (_busy || !isPending)
                              ? null
                              : () async {
                                  final ok = await AdminHelpers.confirm<bool>(
                                    context: context,
                                    title: "Reject resident?",
                                    body: "Reject $name? They will remain blocked until re-submit.",
                                    yesValue: true,
                                    yesLabel: "Reject",
                                  );
                                  if (ok != true) return;

                                  setState(() => _busy = true);
                                  try {
                                    await _adminRejectResident(uid);
                                    if (mounted) {
                                      AdminHelpers.toast(context, "Rejected $name.");
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
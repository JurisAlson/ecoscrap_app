import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../admin_helpers.dart';
import '../admin_theme_page.dart';

// 🔐 Crypto (ADMIN APP)
import 'package:ecoscrap_app/security/admin_keys.dart';
import 'package:ecoscrap_app/security/kyc_cyrpto.dart';
import 'package:ecoscrap_app/security/kyc_shared_key.dart';

class CollectorDetailsPage extends StatefulWidget {
  final DocumentReference<Map<String, dynamic>> requestRef;

  const CollectorDetailsPage({
    super.key,
    required this.requestRef,
  });

  @override
  State<CollectorDetailsPage> createState() => _CollectorDetailsPageState();
}

class _CollectorDetailsPageState extends State<CollectorDetailsPage> {
  bool _busy = false;

  static const Color _primary = Color(0xFF1FA9A7);

  Future<void> _rejectCollectorAndRestoreUser(String uid) async {
    final db = FirebaseFirestore.instance;

    final userRef = db.collection("Users").doc(uid);
    final reqRef = db.collection("collectorRequests").doc(uid);

    await db.runTransaction((tx) async {
      tx.set(
        userRef,
        {
          "role": "user",
          "Roles": "user",
          "collectorVerified": false,
          "collectorStatus": "rejected",
          "collectorActive": false,
          "collectorUpdatedAt": FieldValue.serverTimestamp(),
          "junkshopId": FieldValue.delete(),
          "junkshopName": FieldValue.delete(),
          "assignedJunkshopUid": FieldValue.delete(),
          "assignedJunkshopName": FieldValue.delete(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        reqRef,
        {
          "status": "rejected",
          "adminRejectedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> _adminApprove(String uid) async {
    final db = FirebaseFirestore.instance;

    final reqRef = db.collection("collectorRequests").doc(uid);
    final userRef = db.collection("Users").doc(uid);

    await db.runTransaction((tx) async {
      final reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) {
        throw Exception("Collector request not found");
      }

      tx.set(
        reqRef,
        {
          "status": "adminApproved",
          "adminApprovedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.set(
        userRef,
        {
          "role": "collector",
          "Roles": "collector",
          "collectorStatus": "adminApproved",
          "collectorActive": true,
          "collectorVerified": true,
          "collectorUpdatedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<_DecryptedEquipmentPhoto?> _downloadAndDecryptEquipmentPhoto(
    String uid,
  ) async {
    final db = FirebaseFirestore.instance;
    final snap = await db.collection("collectorEquipment").doc(uid).get();
    final data = snap.data() ?? {};

    final photo = Map<String, dynamic>.from(data["photo"] ?? {});

    final storagePath = (photo["storagePath"] ?? "").toString();
    if (storagePath.isEmpty) return null;

    final originalFileName = (photo["originalFileName"] ?? "").toString();
    final ephPubKeyB64 = (photo["ephPubKeyB64"] ?? "").toString();
    final saltB64 = (photo["saltB64"] ?? "").toString();
    final nonceB64 = (photo["nonceB64"] ?? "").toString();
    final macB64 = (photo["macB64"] ?? "").toString();

    if (ephPubKeyB64.isEmpty ||
        saltB64.isEmpty ||
        nonceB64.isEmpty ||
        macB64.isEmpty) {
      throw Exception("Missing required encryption metadata");
    }

    final ref = FirebaseStorage.instance.ref(storagePath);
    final encryptedBytes = await ref.getData(12 * 1024 * 1024);

    if (encryptedBytes == null) {
      throw Exception("Failed to download encrypted file");
    }

    final collectorEphPubBytes = base64Decode(ephPubKeyB64);
    final salt = base64Decode(saltB64);

    final aesKey = await KycSharedKey.deriveForAdmin(
      adminPrivateKeyB64: AdminKeys.adminPrivateKeyB64,
      collectorEphemeralPubKeyBytes: Uint8List.fromList(collectorEphPubBytes),
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

    return _DecryptedEquipmentPhoto(
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

  Widget _panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
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
            style: TextStyle(
              color: f,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.bg,
      appBar: AppBar(
        backgroundColor: AdminTheme.bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text("Collector Details"),
      ),
      body: AdminTheme.background(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.requestRef.snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(
                child: Text(
                  "Failed to load request.",
                  style: TextStyle(color: Colors.redAccent),
                ),
              );
            }

            if (!snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }

            if (!snap.data!.exists) {
              return const Center(
                child: Text(
                  "Request not found.",
                  style: TextStyle(color: Colors.white70),
                ),
              );
            }

            final data = snap.data!.data() ?? {};
            final uid = snap.data!.id;

            final name = (data["publicName"] ??
                    data["residentName"] ??
                    data["name"] ??
                    "Collector")
                .toString();

            final email = (data["emailDisplay"] ?? "").toString();
            final status = (data["status"] ?? "").toString();
            final isPending = status.toLowerCase() == "pending";
            final accent = _statusAccent(status);

            final equipmentBlock = FutureBuilder<_DecryptedEquipmentPhoto?>(
              future: _downloadAndDecryptEquipmentPhoto(uid),
              builder: (context, photoSnap) {
                if (photoSnap.connectionState == ConnectionState.waiting) {
                  return _panel(
                    padding: const EdgeInsets.symmetric(
                      vertical: 18,
                      horizontal: 14,
                    ),
                    child: const SizedBox(
                      height: 180,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }

                if (photoSnap.hasError) {
                  return _panel(
                    child: const Text(
                      "Equipment photo could not be opened.",
                      style: TextStyle(
                        color: Colors.redAccent,
                        height: 1.3,
                      ),
                    ),
                  );
                }

                final photo = photoSnap.data;
                if (photo == null) {
                  return _panel(
                    child: Row(
                      children: [
                        Icon(
                          Icons.photo_outlined,
                          color: Colors.white.withOpacity(0.6),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            "No equipment photo uploaded.",
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return _panel(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.photo_camera_outlined,
                            color: Colors.white.withOpacity(0.75),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              "Collection Device Photo",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _pill(
                            "Tap to zoom",
                            bg: Colors.white.withOpacity(0.04),
                            fg: Colors.white.withOpacity(0.8),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => _showDecryptedImageDialog(photo.bytes),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AspectRatio(
                            aspectRatio: 16 / 10,
                            child: Image.memory(
                              photo.bytes,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
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
                            border: Border.all(
                              color: _primary.withOpacity(0.22),
                            ),
                          ),
                          child: const Icon(
                            Icons.local_shipping_outlined,
                            color: _primary,
                          ),
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
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.65),
                                    fontSize: 12,
                                  ),
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
                  equipmentBlock,
                  const SizedBox(height: 12),
                  _panel(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.security,
                          color: Colors.blueAccent.withOpacity(0.95),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Confidentiality Notice (Admin Responsibility)\n"
                            "This uploaded equipment photo is provided for collector verification only. "
                            "Review it only for official approval purposes and do not share it outside the admin workflow. "
                            "Never distribute, repost, or misuse submitted images. "
                            "You are responsible for protecting applicant data during review.",
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Processing...",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
                                  final ok =
                                      await AdminHelpers.confirm<bool>(
                                    context: context,
                                    title: "Approve collector?",
                                    body:
                                        "Approve $name? (This makes the collector visible to junkshops)",
                                    yesValue: true,
                                    yesLabel: "Approve",
                                  );

                                  if (ok != true) return;

                                  setState(() => _busy = true);
                                  try {
                                    await _adminApprove(uid);
                                    if (mounted) {
                                      AdminHelpers.toast(
                                        context,
                                        "Approved $name",
                                      );
                                    }
                                    if (mounted) Navigator.pop(context);
                                  } catch (_) {
                                    if (mounted) {
                                      AdminHelpers.toast(
                                        context,
                                        "Approve failed. Please try again.",
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _busy = false);
                                    }
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
                                  final ok =
                                      await AdminHelpers.confirm<bool>(
                                    context: context,
                                    title: "Reject collector?",
                                    body:
                                        "Reject $name? This restores the account to a normal user and allows re-submit.",
                                    yesValue: true,
                                    yesLabel: "Reject",
                                  );

                                  if (ok != true) return;

                                  setState(() => _busy = true);
                                  try {
                                    final callable = FirebaseFunctions
                                        .instanceFor(
                                          region: "asia-southeast1",
                                        )
                                        .httpsCallable("rejectCollector");

                                    await callable.call({
                                      "uid": uid,
                                      "reason":
                                          "Your collector application was rejected by the admin.",
                                    });

                                    await _rejectCollectorAndRestoreUser(uid);

                                    if (mounted) {
                                      AdminHelpers.toast(
                                        context,
                                        "Rejected $name. User restored.",
                                      );
                                      Navigator.pop(context);
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      AdminHelpers.toast(
                                        context,
                                        "Reject failed. Please try again.",
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _busy = false);
                                    }
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

class _DecryptedEquipmentPhoto {
  final Uint8List bytes;
  final String originalFileName;
  final String storagePath;

  _DecryptedEquipmentPhoto({
    required this.bytes,
    required this.originalFileName,
    required this.storagePath,
  });
}
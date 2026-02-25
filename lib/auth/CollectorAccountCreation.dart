import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:ecoscrap_app/security/kyc_cyrpto.dart';
import 'package:ecoscrap_app/security/kyc_shared_key.dart';
import 'package:ecoscrap_app/security/admin_public_key.dart';

class CollectorAccountCreation extends StatefulWidget {
  const CollectorAccountCreation({super.key});

  @override
  State<CollectorAccountCreation> createState() => _CollectorAccountCreationState();
}

class _CollectorAccountCreationState extends State<CollectorAccountCreation> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  PlatformFile? _pickedFile; // optional ID file
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : const Color(0xFF1FA9A7),
      ),
    );
  }

  Future<void> _showInfoDialog({
    required String title,
    required String message,
    IconData icon = Icons.info_outline,
  }) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        actionsPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: const Color(0xFF1FA9A7)),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _pickIdFile() async {
    // Show reminder BEFORE opening picker
    await _showInfoDialog(
      title: "Upload Government ID (Optional)",
      icon: Icons.verified_user_outlined,
      message:
          "Accepted IDs:\n"
          "• Driver’s License\n"
          "• National ID\n"
          "• Voter’s ID\n"
          "• Other valid Government-issued ID\n\n"
          "Accepted file types: JPG, PNG, PDF (max 10MB).\n"
          "Please upload a clear photo/scan.",
    );

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) {
      _toast("Invalid file. Please try again.", error: true);
      return;
    }

    // client-side size limit: 10MB (still enforce on Storage rules)
    if (file.size > 10 * 1024 * 1024) {
      _toast("File too large (Max 10MB).", error: true);
      return;
    }

    final ext = (file.extension ?? "").toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'pdf'].contains(ext)) {
      _toast("Invalid file type. Use JPG/PNG/PDF only.", error: true);
      return;
    }

    setState(() => _pickedFile = file);

    // Show confirmation AFTER picking
    await _showInfoDialog(
      title: "File Selected",
      icon: Icons.check_circle_outline,
      message:
          "Selected: ${file.name}\n\n"
          "Security note:\n"
          "Your ID will be encrypted and used ONLY for verification.\n"
          "We do not use it for any other purpose.",
    );
  }

  String _randId([int len = 16]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // =====================================================
  // ✅ Encrypt + Upload KYC (Storage gets only encrypted bytes)
  // Saves decrypt metadata to collectorKYC/{uid} (admin-only)
  // =====================================================
  Future<void> _uploadEncryptedKyc({
    required String uid,
    required Uint8List fileBytes,
    required String originalFileName, // e.g. kyc_xxx.jpg
  }) async {
    final eph = await KycSharedKey.newEphemeral();
    final ephPubBytes = await KycSharedKey.publicKeyBytes(eph);

    final salt = KycSharedKey.randomSalt16();
    final nonce = KycCrypto.randomNonce12();

    final aesKey = await KycSharedKey.deriveForCollector(
      ephKeyPair: eph,
      adminPublicKeyB64: AdminPublicKey.adminPublicKeyB64,
      salt: salt,
    );

    final enc = await KycCrypto.encryptBytes(
      plain: fileBytes,
      key: aesKey,
      nonce12: nonce,
      aad: utf8.encode(uid),
    );

    final encryptedName = "$originalFileName.enc";
    final storagePath = "kyc/$uid/$encryptedName";

    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(
      enc.cipherText,
      SettableMetadata(contentType: "application/octet-stream"),
    );

    final db = FirebaseFirestore.instance;
    await db.collection("collectorKYC").doc(uid).set({
      "uid": uid,
      "status": "pending",
      "hasKycFile": true,
      "storagePath": storagePath,
      "originalFileName": originalFileName,
      "ephPubKeyB64": base64Encode(ephPubBytes),
      "saltB64": base64Encode(Uint8List.fromList(salt)),
      "nonceB64": base64Encode(enc.nonce),
      "macB64": base64Encode(enc.macBytes),
      "submittedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _submitCollector() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    Reference? uploadedEncryptedRef;

    try {
      final uid = user.uid;
      final email = user.email ?? "";

      final db = FirebaseFirestore.instance;
      final userRef = db.collection("Users").doc(uid);
      final reqRef = db.collection("collectorRequests").doc(uid);
      final kycRef = db.collection("collectorKYC").doc(uid);

      final snap0 = await userRef.get();
      final existing0 = snap0.data() ?? {};
      final status0 = (existing0["collectorStatus"] ?? "").toString().toLowerCase();
      final isActive0 =
          status0 == "pending" || status0 == "adminapproved" || status0 == "junkshopaccepted";
      if (isActive0) {
        _toast("You already have an active request ($status0).", error: true);
        return;
      }

      String? kycFileName;

      if (_pickedFile != null) {
        final ext = (_pickedFile!.extension ?? "").toLowerCase();
        if (!['jpg', 'jpeg', 'png', 'pdf'].contains(ext)) {
          _toast("Invalid file type. Use JPG/PNG/PDF only.", error: true);
          return;
        }

        final normalizedExt = (ext == "jpeg") ? "jpg" : ext;
        final rid = _randId();
        kycFileName = "kyc_$rid.$normalizedExt";

        final bytes = await File(_pickedFile!.path!).readAsBytes();

        await _uploadEncryptedKyc(
          uid: uid,
          fileBytes: Uint8List.fromList(bytes),
          originalFileName: kycFileName,
        );

        final storagePath = "kyc/$uid/$kycFileName.enc";
        uploadedEncryptedRef = FirebaseStorage.instance.ref(storagePath);
      }

      await db.runTransaction((tx) async {
        final userSnap = await tx.get(userRef);
        final existing = userSnap.data() ?? {};

        final status = (existing["collectorStatus"] ?? "").toString().toLowerCase();
        final isActive =
            status == "pending" || status == "adminapproved" || status == "junkshopaccepted";
        if (isActive) throw Exception("Already has active request ($status)");

        tx.set(
          userRef,
          {
            "uid": uid,
            "emailDisplay": email,
            "name": _name.text.trim(),
            "collectorStatus": "pending",
            "collectorSubmittedAt": FieldValue.serverTimestamp(),
            "collectorUpdatedAt": FieldValue.serverTimestamp(),
            if (!existing.containsKey("createdAt")) "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        // ✅ PUBLIC doc — DO NOT show email publicly if you want:
        tx.set(
          reqRef,
          {
            "collectorUid": uid,
            "publicName": _name.text.trim(),
            // REMOVE email from public doc:
            // "emailDisplay": email,

            "hasKycFile": kycFileName != null,
            "status": "pending",
            "submittedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),

            "acceptedByJunkshopUid": "",
            "acceptedAt": FieldValue.delete(),
            "rejectedByJunkshops": [],
          },
          SetOptions(merge: true),
        );

        if (kycFileName == null) {
          tx.delete(kycRef);
        } else {
          tx.set(
            kycRef,
            {
              "status": "pending",
              "updatedAt": FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      });

      _toast("Submitted! Pending admin review.");
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (uploadedEncryptedRef != null) {
        try {
          await uploadedEncryptedRef.delete();
        } catch (_) {}
      }
      _toast("Failed: $e", error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1220),
        elevation: 0,
        title: const Text("Plastic Collector Registration"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroHeader(),
                const SizedBox(height: 14),

                _InfoCard(
                  title: "Why Plastic Collectors are important",
                  icon: Icons.recycling,
                  children: const [
                    Text(
                      "Plastic collectors help keep communities clean, reduce waste in rivers and oceans, and support responsible recycling.",
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                    SizedBox(height: 10),
                    _Bullet(text: "Cleaner barangays & streets"),
                    _Bullet(text: "Less plastic pollution"),
                    _Bullet(text: "Better recycling and recovery"),
                  ],
                ),

                const SizedBox(height: 12),

                _SectionTitle("Your Details"),
                const SizedBox(height: 10),
                _buildTextField(_name, "Full Name", Icons.person),

                const SizedBox(height: 14),

                _SectionTitle("Verification (Optional)"),
                const SizedBox(height: 10),

                _InfoCard(
                  title: "Accepted Government IDs",
                  icon: Icons.badge_outlined,
                  children: const [
                    _Bullet(text: "Driver’s License"),
                    _Bullet(text: "National ID"),
                    _Bullet(text: "Voter’s ID"),
                    _Bullet(text: "Other valid Government-issued ID"),
                    SizedBox(height: 10),
                    Text(
                      "File types: JPG, PNG, PDF (max 10MB). Upload a clear photo/scan.",
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                _InfoCard(
                  title: "Your Security is our Priority",
                  icon: Icons.lock_outline,
                  children: const [
                    Text(
                      "Your ID is encrypted and will be used ONLY for verification purposes. "
                      "It will not be used for any other purpose or shared publicly.",
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                _UploadTile(
                  pickedFileName: _pickedFile?.name,
                  onTap: _loading ? null : _pickIdFile,
                  onRemove: _loading || _pickedFile == null
                      ? null
                      : () => setState(() => _pickedFile = null),
                ),

                const SizedBox(height: 18),

                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1FA9A7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    onPressed: _loading ? null : _submitCollector,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                          )
                        : const Text(
                            "Submit Application",
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),

                const SizedBox(height: 10),

                const Text(
                  "By submitting, you confirm that the information provided is true and correct.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: const Color(0xFF1FA9A7)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1FA9A7), width: 1.6),
        ),
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
    );
  }
}

// =========================
// UI Components
// =========================

class _HeroHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1FA9A7).withOpacity(0.25),
            Colors.white.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF1FA9A7).withOpacity(0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.recycling, color: Color(0xFF7CF5F2)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Join as a Plastic Collector",
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 6),
                Text(
                  "Help collect, recover, and recycle plastic responsibly — and get verified for safer transactions.",
                  style: TextStyle(color: Colors.white70, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF1FA9A7)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: Colors.white54),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  final String? pickedFileName;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _UploadTile({
    required this.pickedFileName,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasFile = pickedFileName != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF1FA9A7).withOpacity(0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                hasFile ? Icons.check_circle_outline : Icons.upload_file,
                color: hasFile ? const Color(0xFF7CF5F2) : const Color(0xFF1FA9A7),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasFile ? "Government ID selected" : "Upload Government ID (optional)",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasFile ? pickedFileName! : "JPG / PNG / PDF • Max 10MB",
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            if (hasFile)
              IconButton(
                onPressed: onRemove,
                tooltip: "Remove",
                icon: const Icon(Icons.close, color: Colors.white70),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}
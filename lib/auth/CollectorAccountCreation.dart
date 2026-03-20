import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:ecoscrap_app/security/admin_public_key.dart';
import 'package:ecoscrap_app/security/kyc_cyrpto.dart';
import 'package:ecoscrap_app/security/kyc_shared_key.dart';

class CollectorAccountCreation extends StatefulWidget {
  const CollectorAccountCreation({super.key});

  @override
  State<CollectorAccountCreation> createState() =>
      _CollectorAccountCreationState();
}

class _CollectorAccountCreationState extends State<CollectorAccountCreation> {
  PlatformFile? _equipmentPhoto;
  bool _loading = false;

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

  Future<void> _pickEquipmentPhoto() async {
    await _showInfoDialog(
      title: "Upload Collection Device Photo",
      icon: Icons.photo_camera_back_outlined,
      message:
          "Please upload 1 clear photo of your collection device.\n\n"
          "The photo must:\n"
          "• Show the whole device\n"
          "• Show the capacity/container area\n"
          "• Clearly show that it can carry at least 20KG of plastic materials\n\n"
          "Accepted examples:\n"
          "• Kulong-kulong\n"
          "• Sidecar\n"
          "• Kariton\n"
          "• Other collection device\n\n"
          "Accepted file types: JPG, PNG (max 10MB).",
    );

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) {
      _toast("Invalid file. Please try again.", error: true);
      return;
    }

    if (file.size > 10 * 1024 * 1024) {
      _toast("File too large (Max 10MB).", error: true);
      return;
    }

    final ext = (file.extension ?? "").toLowerCase();
    if (!['jpg', 'jpeg', 'png'].contains(ext)) {
      _toast("Invalid file type. Use JPG/PNG only.", error: true);
      return;
    }

    setState(() => _equipmentPhoto = file);

    await _showInfoDialog(
      title: "Photo Selected",
      icon: Icons.check_circle_outline,
      message:
          "Selected: ${file.name}\n\n"
          "Your photo will be used only for verification.",
    );
  }

  String _randId([int len = 16]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _readRegisteredName(Map<String, dynamic> data) {
    return (data["name"] ??
            data["Name"] ??
            data["fullName"] ??
            data["FullName"] ??
            data["residentName"] ??
            data["ResidentName"] ??
            data["displayName"] ??
            data["DisplayName"] ??
            "")
        .toString()
        .trim();
  }

  Future<Map<String, dynamic>> _uploadEncryptedEquipmentPhoto({
    required String uid,
    required Uint8List fileBytes,
    required String originalFileName,
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
    final storagePath = "collector_equipment/$uid/$encryptedName";

    debugPrint("UPLOAD PATH: $storagePath");
    debugPrint("UPLOAD SIZE: ${enc.cipherText.length}");
    debugPrint("UPLOAD TYPE: application/octet-stream");

    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putData(
      enc.cipherText,
      SettableMetadata(contentType: "application/octet-stream"),
    );

    debugPrint("UPLOAD DONE");

    return {
      "storagePath": storagePath,
      "originalFileName": originalFileName,
      "ephPubKeyB64": base64Encode(ephPubBytes),
      "saltB64": base64Encode(Uint8List.fromList(salt)),
      "nonceB64": base64Encode(enc.nonce),
      "macB64": base64Encode(enc.macBytes),
      "uploadedAt": FieldValue.serverTimestamp(),
    };
  }

  Future<void> _submitCollector() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_equipmentPhoto == null) {
      _toast("Please upload the required device photo.", error: true);
      return;
    }

    setState(() => _loading = true);

    Reference? uploadedEncryptedRef;

    try {
      debugPrint("SUBMIT START");

      final uid = user.uid;
      final email = user.email ?? "";

      final db = FirebaseFirestore.instance;
      final userRef = db.collection("Users").doc(uid);
      final reqRef = db.collection("collectorRequests").doc(uid);
      final equipmentRef = db.collection("collectorEquipment").doc(uid);

      final snap0 = await userRef.get();
      final existing0 = snap0.data() ?? {};
      debugPrint("USER DOC DATA: $existing0");

      final status0 =
          (existing0["collectorStatus"] ?? "").toString().toLowerCase();

      if (status0 == "pending") {
        debugPrint("STOP: already pending");
        _toast("You already have a pending collector request.", error: true);
        return;
      }

      final registeredName = _readRegisteredName(existing0);
      debugPrint("REGISTERED NAME: $registeredName");

      if (registeredName.isEmpty) {
        debugPrint("STOP: registered name empty");
        _toast(
          "Registered resident name not found. Please complete your resident profile first.",
          error: true,
        );
        return;
      }

      final ext = (_equipmentPhoto!.extension ?? "").toLowerCase();
      final normalizedExt = ext == "jpeg" ? "jpg" : ext;
      final rid = _randId();
      final photoFileName = "equipment_$rid.$normalizedExt";

      final bytes = await File(_equipmentPhoto!.path!).readAsBytes();

      debugPrint("STEP 1: upload encrypted photo");
      final photoMeta = await _uploadEncryptedEquipmentPhoto(
        uid: uid,
        fileBytes: Uint8List.fromList(bytes),
        originalFileName: photoFileName,
      );
      debugPrint("STEP 1 OK");

      uploadedEncryptedRef =
          FirebaseStorage.instance.ref(photoMeta["storagePath"] as String);

      debugPrint("STEP 2: write collectorEquipment");
      await equipmentRef.set(
        {
          "uid": uid,
          "residentName": registeredName,
          "status": "pending",
          "minimumRequiredCapacityKg": 20,
          "photo": photoMeta,
          "submittedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint("STEP 2 OK");

      debugPrint("STEP 3: write collectorRequests");
      await reqRef.set(
        {
          "collectorUid": uid,
          "publicName": registeredName,
          "emailDisplay": email,
          "hasEquipmentPhoto": true,
          "minimumRequiredCapacityKg": 20,
          "status": "pending",
          "submittedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint("STEP 3 OK");

      debugPrint("STEP 4: write Users");
      await userRef.set(
        {
          "uid": uid,
          "emailDisplay": email,
          "name": registeredName,
          "collectorVerified": false,
          "collectorStatus": "pending",
          "collectorSubmittedAt": FieldValue.serverTimestamp(),
          "collectorUpdatedAt": FieldValue.serverTimestamp(),
          "collectorActive": false,
          if (!existing0.containsKey("createdAt") &&
              !existing0.containsKey("CreatedAt"))
            "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      debugPrint("STEP 4 OK");

      _toast("Submitted! Pending admin review.");
      if (mounted) Navigator.pop(context);
    } catch (e, st) {
      debugPrint("SUBMIT ERROR: $e");
      debugPrint("STACK: $st");

      if (e is FirebaseException) {
        debugPrint("FIREBASE CODE: ${e.code}");
        debugPrint("FIREBASE MESSAGE: ${e.message}");
      }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1220),
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text("Plastic Collector Registration"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeroHeader(),
              const SizedBox(height: 14),
              _InfoCard(
                title: "Why Plastic Collectors are Important",
                icon: Icons.recycling,
                children: const [
                  Text(
                    "Plastic collectors help keep communities clean, reduce waste in rivers and oceans, and support responsible recycling.",
                    style: TextStyle(color: Colors.white70, height: 1.35),
                  ),
                  SizedBox(height: 10),
                  _Bullet(text: "Cleaner barangays and streets"),
                  _Bullet(text: "Less plastic pollution"),
                  _Bullet(text: "Better recycling and recovery"),
                ],
              ),
              const SizedBox(height: 12),
              const _SectionTitle("Collection Device Verification"),
              const SizedBox(height: 10),
              const _InfoCard(
                title: "Required Device Capacity",
                icon: Icons.scale_outlined,
                children: [
                  Text(
                    "The collection device must be able to carry at least 20KG of plastic materials.",
                    style: TextStyle(color: Colors.white70, height: 1.35),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _InfoCard(
                title: "How to Take the Picture",
                icon: Icons.camera_alt_outlined,
                children: [
                  _Bullet(text: "Take 1 clear picture of your collection device"),
                  _Bullet(text: "(kulong-kulong, kariton, sidecar, or similar)"),
                  _Bullet(text: "Make sure the whole device is visible"),
                  _Bullet(
                    text:
                        "Take the photo from an angle where the size can be seen clearly",
                  ),
                  _Bullet(
                    text:
                        "Avoid dark, blurry, or cropped photos for faster verification",
                  ),
                ],
              ),
              const SizedBox(height: 12),
             Container(
  height: 190,
  decoration: BoxDecoration(
    color: Colors.white.withOpacity(0.04),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: Colors.white.withOpacity(0.08),
    ),
  ),
  clipBehavior: Clip.antiAlias,
  child: Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/collector/images.jpg',
        fit: BoxFit.cover,
      ),
      Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.10),
              Colors.black.withOpacity(0.45),
            ],
          ),
        ),
      ),
      const Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            "Example of a valid collection device photo",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ],
  ),
),
              const SizedBox(height: 12),
              const _InfoCard(
                title: "Accepted Device Examples",
                icon: Icons.local_shipping_outlined,
                children: [
                  _Bullet(text: "Kulong-kulong"),
                  _Bullet(text: "Sidecar"),
                  _Bullet(text: "Kariton"),
                  _Bullet(text: "Other collection device"),
                ],
              ),
              const SizedBox(height: 12),
              _UploadTile(
                title: "Upload Device Photo (Required)",
                subtitle: _equipmentPhoto?.name ??
                    "JPG / PNG • Max 10MB • Whole device must be visible",
                pickedFileName: _equipmentPhoto?.name,
                onTap: _loading ? null : _pickEquipmentPhoto,
                onRemove: _loading || _equipmentPhoto == null
                    ? null
                    : () => setState(() => _equipmentPhoto = null),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1FA9A7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _loading ? null : _submitCollector,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.4,
                          ),
                        )
                      : const Text(
                          "Submit Application",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "By submitting, you confirm that this is the collection device you will use and that it can carry at least 20KG of plastic materials.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================= UI Components =========================

class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

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
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  "Upload a clear photo of your collection device for admin verification.",
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
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
  final String title;
  final String subtitle;
  final String? pickedFileName;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _UploadTile({
    required this.title,
    required this.subtitle,
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
                color: hasFile
                    ? const Color(0xFF7CF5F2)
                    : const Color(0xFF1FA9A7),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasFile ? pickedFileName! : subtitle,
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
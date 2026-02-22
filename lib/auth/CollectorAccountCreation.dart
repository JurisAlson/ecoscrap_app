import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CollectorAccountCreation extends StatefulWidget {
  const CollectorAccountCreation({super.key});

  @override
  State<CollectorAccountCreation> createState() =>
      _CollectorAccountCreationState();
}

class _CollectorAccountCreationState extends State<CollectorAccountCreation> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  File? _idImage;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickId() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _idImage = File(picked.path));
  }

  /// ✅ Upload under /permits/{uid}/... (matches your current storage rules)
  /// ✅ Return STORAGE PATH (not URL)
  Future<String?> _uploadIdPermitPath(String uid) async {
    if (_idImage == null) return null;

    final path =
        'permits/$uid/collector_id_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref().child(path);

    await ref.putFile(
      _idImage!,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    return path;
  }

  Future<void> _submitCollector() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  if (!_formKey.currentState!.validate()) return;

  setState(() => _loading = true);

  try {
    final permitPath = await _uploadIdPermitPath(user.uid);
    final userRef = FirebaseFirestore.instance.collection("Users").doc(user.uid);

    final existingSnap = await userRef.get();
    final existing = existingSnap.data() ?? {};

    final hasCreatedAt = existing.containsKey("createdAt");
    final hasCreatedAtCaps = existing.containsKey("CreatedAt");

    final existingJunkshopId = (existing["junkshopId"] ?? "").toString();
    final existingJunkshopName = (existing["junkshopName"] ?? "").toString();
    final existingJunkshopVerified = existing["junkshopVerified"] == true;
    final existingJunkshopStatus = (existing["junkshopStatus"] ?? "").toString();

    final existingAdminVerified = existing["adminVerified"] == true;
    final existingAdminStatus = (existing["adminStatus"] ?? "").toString();
    final existingAdminReviewedAt = existing["adminReviewedAt"];

    final existingCollectorStatus =
        (existing["collectorStatus"] ?? "").toString().trim().toLowerCase();

    final alreadyDecided = existingCollectorStatus == "approved" || existingCollectorStatus == "rejected";
    final collectorStatusToSave = alreadyDecided ? existingCollectorStatus : "pending";

    // ✅ Protect approved collectors: don't downgrade their role on resubmit
    final existingRole = (existing["Roles"] ?? existing["role"] ?? "user").toString().trim().toLowerCase();
    final rolesToSave = (collectorStatusToSave == "approved") ? (existingRole.isEmpty ? "collector" : existingRole) : "user";

    await userRef.set({
      "UserID": user.uid,
      "Email": user.email ?? "",
      "Name": _name.text.trim(),

      // ✅ user until approved
      "Roles": rolesToSave,
      "role": rolesToSave,

      // ✅ pending list uses this
      "collectorStatus": collectorStatusToSave,

      // ✅ admin review fields (do not reset if already decided)
      "adminVerified": existingAdminVerified,
      "adminStatus": existingAdminStatus.isNotEmpty ? existingAdminStatus : "pending",
      "adminReviewedAt": existingAdminReviewedAt,

      // ✅ inactive until approved
      "collectorActive": existing["collectorActive"] ?? false,

      // ✅ keep assignment fields
      "junkshopId": existingJunkshopId,
      "junkshopName": existingJunkshopName,
      "junkshopVerified": existingJunkshopVerified,
      "junkshopStatus": existingJunkshopStatus.isNotEmpty ? existingJunkshopStatus : "unassigned",

      // ✅ KYC
      if (permitPath != null)
        "kyc": {
          "permitPath": permitPath,
          "status": "pending",
          "submittedAt": FieldValue.serverTimestamp(),
          "type": "valid_id",
        }
      else if (existing["kyc"] != null)
        "kyc": existing["kyc"],

      if (!hasCreatedAt) "createdAt": FieldValue.serverTimestamp(),
      if (!hasCreatedAtCaps) "CreatedAt": FieldValue.serverTimestamp(),
      "updatedAt": FieldValue.serverTimestamp(),

      "isOnline": existing["isOnline"] ?? false,
      "lastSeen": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Submitted! Pending admin review.")),
    );
    Navigator.pop(context);
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Failed: $e")),
    );
  } finally {
    if (mounted) setState(() => _loading = false);
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("Collector Registration"),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const Text(
                "Collector Account",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),
              _buildTextField(_name, "Full Name", Icons.person),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _loading ? null : _pickId,
                icon: Icon(
                    _idImage == null ? Icons.badge_outlined : Icons.check_circle),
                label: Text(_idImage == null
                    ? "Upload Valid ID (optional)"
                    : "ID Selected (Tap to Change)"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white10,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1FA9A7),
                  ),
                  onPressed: _loading ? null : _submitCollector,
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Submit (Pending)",
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: const Color(0xFF1FA9A7)),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF1FA9A7)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF1FA9A7), width: 2),
        ),
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
    );
  }
}
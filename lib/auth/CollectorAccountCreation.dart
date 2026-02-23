import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

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
        backgroundColor: error ? Colors.redAccent : Colors.green,
      ),
    );
  }

  Future<void> _pickIdFile() async {
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

    setState(() => _pickedFile = file);
  }

  String _guessContentType(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'application/octet-stream';
    }
  }

Future<void> _submitCollector() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  if (!_formKey.currentState!.validate()) return;

  setState(() => _loading = true);

  Reference? uploadedRef;

  try {
    final uid = user.uid;
    final email = user.email ?? "";

    final db = FirebaseFirestore.instance;
    final userRef = db.collection("Users").doc(uid);
    final reqRef = db.collection("collectorRequests").doc(uid);
    final kycRef = db.collection("collectorKYC").doc(uid);

    // Block if active
    final snap0 = await userRef.get();
    final existing0 = snap0.data() ?? {};
    final status0 = (existing0["collectorStatus"] ?? "").toString().toLowerCase();
    final isActive0 = status0 == "pending" || status0 == "adminapproved" || status0 == "junkshopaccepted";
    if (isActive0) {
      _toast("You already have an active request ($status0).", error: true);
      return;
    }

    // Upload optional ID (NO URL stored; only stable filename)
    String? kycFileName; // e.g. collector_id.jpg
    if (_pickedFile != null) {
      final ext = (_pickedFile!.extension ?? "").toLowerCase();
      if (!['jpg', 'jpeg', 'png', 'pdf'].contains(ext)) {
        _toast("Invalid file type. Use JPG/PNG/PDF only.", error: true);
        return;
      }

      // Normalize extension
      final normalizedExt = (ext == "jpeg") ? "jpg" : ext;

      // Deterministic file name (overwrite on resubmit)
      kycFileName = "collector_id.$normalizedExt";

      // Deterministic path (NO timestamp needed)
      final path = "kyc/$uid/$kycFileName";

      uploadedRef = FirebaseStorage.instance.ref(path);

      await uploadedRef.putFile(
        File(_pickedFile!.path!),
        SettableMetadata(contentType: _guessContentType(normalizedExt)),
      );
    }

    // Firestore transaction: Users + collectorRequests + collectorKYC
    await db.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final existing = (userSnap.data() as Map<String, dynamic>?) ?? {};

      final status = (existing["collectorStatus"] ?? "").toString().toLowerCase();
      final isActive = status == "pending" || status == "adminapproved" || status == "junkshopaccepted";
      if (isActive) throw Exception("Already has active request ($status)");

      // Users doc (role stays USER until accepted by junkshop)
      tx.set(userRef, {
        "uid": uid,
        "emailDisplay": email,
        "name": _name.text.trim(),

        "collectorStatus": "pending",
        "collectorSubmittedAt": FieldValue.serverTimestamp(),
        "collectorUpdatedAt": FieldValue.serverTimestamp(),

        if (!existing.containsKey("createdAt")) "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // collectorRequests (junkshop-visible, public fields ONLY)
      tx.set(reqRef, {
        "collectorUid": uid,
        "publicName": _name.text.trim(),
        "emailDisplay": email,

        "hasKycFile": kycFileName != null, // ✅ boolean only
        "status": "pending",
        "submittedAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),

        "acceptedByJunkshopUid": "",
        "acceptedAt": FieldValue.delete(),
        "rejectedByJunkshops": [],
      }, SetOptions(merge: true));

      // collectorKYC (admin-only)
      // Store ONLY filename, NOT URL, NOT path.
      if (kycFileName != null) {
        tx.set(kycRef, {
          "uid": uid,
          "hasKycFile": true,
          "kycFileName": kycFileName, // ✅ only ID reference
          "submittedAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        // If no file: keep doc absent or mark hasKycFile false (your choice)
        tx.delete(kycRef);
      }
    });

    _toast("Submitted! Pending admin review.");
    if (mounted) Navigator.pop(context);
  } catch (e) {
    // rollback uploaded file if Firestore failed
    if (uploadedRef != null) {
      try { await uploadedRef.delete(); } catch (_) {}
    }
    _toast("Failed: $e", error: true);
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
                onPressed: _loading ? null : _pickIdFile,
                icon: Icon(_pickedFile == null ? Icons.badge_outlined : Icons.check_circle),
                label: Text(
                  _pickedFile == null
                      ? "Upload Valid ID (optional) - JPG/PNG/PDF"
                      : "Selected: ${_pickedFile!.name}",
                ),
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
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1FA9A7)),
                  onPressed: _loading ? null : _submitCollector,
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Submit (Pending)", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
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
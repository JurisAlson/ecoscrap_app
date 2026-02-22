import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class CollectorAccountCreation extends StatefulWidget {
  const CollectorAccountCreation({super.key});

  @override
  State<CollectorAccountCreation> createState() => _CollectorAccountCreationState();
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

  Future<void> _submitCollector() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    Reference? uploadedRef;

    try {
      final uid = user.uid;
      final email = user.email ?? "";
      final userRef = FirebaseFirestore.instance.collection("Users").doc(uid);
      final reqRef = FirebaseFirestore.instance.collection("collectorRequests").doc(uid);

      // quick check (transaction will re-check)
      final snap = await userRef.get();
      final existing0 = snap.data() ?? {};
      final status0 = (existing0["collectorStatus"] ?? "").toString();

      final isActive0 =
          status0 == "pending" || status0 == "adminApproved" || status0 == "junkshopAccepted";

      if (isActive0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("You already have an active request ($status0).")),
        );
        return;
      }

      // Upload optional ID
      String? permitPath;
      if (_idImage != null) {
        final path = 'permits/$uid/collector_id_${DateTime.now().millisecondsSinceEpoch}.jpg';
        uploadedRef = FirebaseStorage.instance.ref(path);
        await uploadedRef.putFile(_idImage!, SettableMetadata(contentType: 'image/jpeg'));
        permitPath = path;
      }

      // Write Users + collectorRequests atomically
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final userSnap = await tx.get(userRef);
        final existing = (userSnap.data() as Map<String, dynamic>?) ?? {};

        final status = (existing["collectorStatus"] ?? "").toString();
        final isActive = status == "pending" || status == "adminApproved" || status == "junkshopAccepted";
        if (isActive) throw Exception("Already has active request ($status)");

        tx.set(userRef, {
          "uid": uid,
          "emailDisplay": email,
          "name": _name.text.trim(),

          "collectorStatus": "pending",
          "collectorSubmittedAt": FieldValue.serverTimestamp(),
          "collectorUpdatedAt": FieldValue.serverTimestamp(),

          if (permitPath != null)
            "collectorKyc": {
              "permitPath": permitPath,
              "submittedAt": FieldValue.serverTimestamp(),
            },

          if (!existing.containsKey("createdAt")) "createdAt": FieldValue.serverTimestamp(),
          "updatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

          tx.set(reqRef, {
            "publicName": _name.text.trim(),
            "emailDisplay": email,

            "status": "pending",
            "submittedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),

            // ✅ ALWAYS reset routing fields (critical for resubmit)
            "acceptedByJunkshopUid": "",
            "acceptedAt": FieldValue.delete(),
            "rejectedByJunkshops": [],

            // ✅ clear stale permit if user didn't upload a new one
            if (permitPath != null) "permitPath": permitPath else "permitPath": FieldValue.delete(),
          }, SetOptions(merge: true));
          });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Submitted! Pending admin review.")),
      );
      Navigator.pop(context);
    } catch (e) {
      // rollback file if transaction failed
      if (uploadedRef != null) {
        try {
          await uploadedRef.delete();
        } catch (_) {}
      }
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
                icon: Icon(_idImage == null ? Icons.badge_outlined : Icons.check_circle),
                label: Text(_idImage == null ? "Upload Valid ID (optional)" : "ID Selected (Tap to Change)"),
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
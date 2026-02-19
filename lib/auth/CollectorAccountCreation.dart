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
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _idImage = File(picked.path));
  }

  // ✅ FIXED: uploads to /permits/{uid}/... (matches your Storage rules)
  Future<String?> _uploadId(String uid) async {
    if (_idImage == null) return null;

    final ref = FirebaseStorage.instance
        .ref()
        .child('permits')
        .child(uid)
        .child('collector_id_${DateTime.now().millisecondsSinceEpoch}.jpg');

    await ref.putFile(
      _idImage!,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    return await ref.getDownloadURL();
  }

  Future<void> _submitPendingCollector() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final idUrl = await _uploadId(user.uid);

      await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
        "UserID": user.uid,
        "Email": user.email ?? "",
        "Name": _name.text.trim(),
        "Roles": "collector",

        // ✅ pending + verified boolean (you can keep Status too)
        "Status": "pending",
        "verified": false,

        "createdAt": FieldValue.serverTimestamp(),
        "isOnline": false,
        "lastSeen": FieldValue.serverTimestamp(),

        // ✅ store for admin viewing
        if (idUrl != null) "permitUrl": idUrl,

        // (optional) keep your old field too if you want backward compatibility
        if (idUrl != null) "idImageUrl": idUrl,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Submitted! Collector account is now pending.")),
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
      appBar: AppBar(
        title: const Text("Collector Account Creation"),
        backgroundColor: const Color(0xFF1FA9A7),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: "Full Name"),
                validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _pickId,
                      icon: const Icon(Icons.badge_outlined),
                      label: Text(_idImage == null ? "Upload ID (optional)" : "Change ID"),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submitPendingCollector,
                  child: Text(_loading ? "Submitting..." : "Submit (Pending)"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

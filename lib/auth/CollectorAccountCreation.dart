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

  String? _preferredShopId;
  String? _preferredShopName;

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

  // uploads to /permits/{uid}/...
  Future<String?> _uploadId(String uid) async {
    if (_idImage == null) return null;

    final ref = FirebaseStorage.instance
        .ref()
        .child('permits')
        .child(uid)
        .child('collector_id_${DateTime.now().millisecondsSinceEpoch}.jpg');

    await ref.putFile(_idImage!, SettableMetadata(contentType: 'image/jpeg'));
    return await ref.getDownloadURL();
  }

  Future<void> _submitCollector() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (!_formKey.currentState!.validate()) return;

    // ✅ require preferred junkshop (recommended)
    if (_preferredShopId == null || _preferredShopId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a preferred junkshop.")),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final idUrl = await _uploadId(user.uid);

      final batch = FirebaseFirestore.instance.batch();

      // 1) Users/{uid} -> NO IMAGE here
      final userRef = FirebaseFirestore.instance.collection("Users").doc(user.uid);
      batch.set(userRef, {
        "UserID": user.uid,
        "Email": user.email ?? "",
        "Name": _name.text.trim(),
        "Roles": "collector",

        // routing
        "preferredJunkshopId": _preferredShopId,
        "preferredJunkshopName": _preferredShopName ?? "",

        // 2-step approvals
        "adminVerified": false,
        "adminStatus": "pending",
        "junkshopVerified": false,
        "junkshopStatus": "pending",
        "collectorActive": false,

        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
        "isOnline": false,
        "lastSeen": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2) collectorKYC/{uid} -> IMAGE URL here (ADMIN reads this)
      if (idUrl != null) {
        final kycRef = FirebaseFirestore.instance.collection("collectorKYC").doc(user.uid);
        batch.set(kycRef, {
          "collectorUid": user.uid,
          "permitUrl": idUrl,
          "createdAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Submitted! Collector application is now pending admin review.")),
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

  // Load verified junkshops for dropdown
  Stream<QuerySnapshot<Map<String, dynamic>>> _junkshopsStream() {
    return FirebaseFirestore.instance
        .collection("Junkshop")
        .where("verified", isEqualTo: true)
        .snapshots();
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

              // ✅ Preferred Junkshop dropdown
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _junkshopsStream(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text("Junkshop load error: ${snap.error}");
                  }
                  if (!snap.hasData) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 8),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  final docs = snap.data!.docs;

                  if (docs.isEmpty) {
                    return const Text("No verified junkshops available yet.");
                  }

                  return DropdownButtonFormField<String>(
                    value: _preferredShopId,
                    decoration: const InputDecoration(
                      labelText: "Preferred Junkshop",
                      border: OutlineInputBorder(),
                    ),
                    items: docs.map((d) {
                      final data = d.data();
                      final name = (data["shopName"] ?? d.id).toString();
                      return DropdownMenuItem<String>(
                        value: d.id,
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: _loading
                        ? null
                        : (val) {
                            if (val == null) return;
                            final chosen = docs.firstWhere((x) => x.id == val);
                            final chosenName = (chosen.data()["shopName"] ?? chosen.id).toString();

                            setState(() {
                              _preferredShopId = val;
                              _preferredShopName = chosenName;
                            });
                          },
                    validator: (v) => (v == null || v.isEmpty) ? "Select a junkshop" : null,
                  );
                },
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
                  onPressed: _loading ? null : _submitCollector,
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

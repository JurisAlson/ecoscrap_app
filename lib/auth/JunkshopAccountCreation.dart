import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';

class JunkshopAccountCreationPage extends StatefulWidget {
  const JunkshopAccountCreationPage({super.key});

  @override
  State<JunkshopAccountCreationPage> createState() =>
      _JunkshopAccountCreationPageState();
}

class _JunkshopAccountCreationPageState
    extends State<JunkshopAccountCreationPage> {
  final TextEditingController _shopNameController = TextEditingController();

  PlatformFile? _pickedFile;
  bool _isLoading = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() => _pickedFile = result.files.first);
    }
  }

  Future<void> _registerJunkshop() async {
    final user = _auth.currentUser;
    if (user == null) {
      _showToast("Please login first to apply as junkshop.", isError: true);
      return;
    }

    final uid = user.uid;
    final email = user.email ?? "";
    final shopName = _shopNameController.text.trim();

    if (email.isEmpty) {
      _showToast(
        "Your account has no email. Please login with email/password.",
        isError: true,
      );
      return;
    }

    if (_pickedFile == null || _pickedFile!.path == null || shopName.isEmpty) {
      _showToast("Please enter shop name and upload a permit", isError: true);
      return;
    }

    // 10MB client-side limit (still enforce in Storage rules)
    if (_pickedFile!.size > 10 * 1024 * 1024) {
      _showToast("File too large (Max 10MB)", isError: true);
      return;
    }

    final ext = (_pickedFile!.extension ?? '').toLowerCase();
    if (!['pdf', 'jpg', 'jpeg', 'png'].contains(ext)) {
      _showToast("Invalid file type. Use PDF/JPG/PNG only.", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    Reference? storageRef;

    try {
      // 1) Upload permit to Storage (private folder)
      final fileName = "${DateTime.now().millisecondsSinceEpoch}.$ext";
      final storagePath = 'permits/$uid/$fileName';
      storageRef = FirebaseStorage.instance.ref(storagePath);

      await storageRef.putFile(
        File(_pickedFile!.path!),
        SettableMetadata(contentType: _guessContentType(ext)),
      );

      // 2) Create/merge permit request doc (doc id = uid prevents duplicates)
      final requestRef = _firestore.collection('permitRequests').doc(uid);
      await requestRef.set({
        'uid': uid,
        'shopName': shopName,
        'emailDisplay': email, // ✅ always from Auth
        'approved': false,
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'permitPath': storagePath,
        'originalFileName': _pickedFile!.name,
      }, SetOptions(merge: true));

      await _firestore.collection('Users').doc(uid).set({
        'uid': uid,
        'shopName': shopName,
        'emailDisplay': email,

        // ✅ KEEP as user until approved
        'Roles': 'user',
        'role': 'user',

        // application tracking only
        'verified': false,
        'junkshopStatus': 'pending',
        'activePermitRequestId': requestRef.id,

        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      _showToast("Submitted! Admin will verify your permit.");
      Navigator.pop(context);
    } catch (e) {
      // rollback uploaded file if any
      if (storageRef != null) {
        try {
          await storageRef.delete();
        } catch (_) {}
      }
      _showToast("Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authEmail = FirebaseAuth.instance.currentUser?.email ?? "";

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("Junkshop Application"),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        child: Column(
          children: [
            const Text(
              "Apply as Junkshop",
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),

            _buildTextField(_shopNameController, "Shop Name", Icons.store),
            const SizedBox(height: 16),

            // ✅ shows the account email that will be used
            _buildReadOnlyField(authEmail, "Account Email", Icons.email),
            const SizedBox(height: 30),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _pickFile,
              icon: Icon(
                _pickedFile == null ? Icons.upload_file : Icons.check_circle,
              ),
              label: Text(
                _pickedFile == null
                    ? "Upload Business Permit (PDF/Image)"
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1FA9A7),
                ),
                onPressed: _isLoading ? null : _registerJunkshop,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "Submit Application",
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return TextField(
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
          borderSide: BorderSide(color: Color(0xFF1FA9A7)),
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String value, String label, IconData icon) {
    return TextField(
      readOnly: true,
      controller: TextEditingController(text: value),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: const Color(0xFF1FA9A7)),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF1FA9A7)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF1FA9A7)),
        ),
      ),
    );
  }
}
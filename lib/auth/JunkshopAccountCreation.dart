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
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

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
    if (_pickedFile == null ||
        _pickedFile!.path == null ||
        _emailController.text.trim().isEmpty ||
        _shopNameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      _showToast("Please fill all fields and upload a permit", isError: true);
      return;
    }

    // 10MB client-side limit (Storage rules should enforce too)
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
      // 1) Create Auth user
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final user = userCredential.user!;
      await user.getIdToken(true); 
      final uid = user.uid;

      // 2) Upload file to Storage (private folder)
      final fileName = "${DateTime.now().millisecondsSinceEpoch}.$ext";
      final storagePath = 'permits/$uid/$fileName';
      storageRef = FirebaseStorage.instance.ref(storagePath);

      final file = File(_pickedFile!.path!);

      await storageRef.putFile(
        file,
        SettableMetadata(contentType: _guessContentType(ext)),
      );

      // 3) Create permit request doc
      final requestRef = _firestore.collection('permitRequests').doc();
      await requestRef.set({
        'uid': uid,
        'shopName': _shopNameController.text.trim(),
        'email': _emailController.text.trim(),
        'approved': false,
        'submittedAt': FieldValue.serverTimestamp(),
        'permitPath': storagePath,
        'originalFileName': _pickedFile!.name,
      });

      // 4) Create junkshop profile doc
      await _firestore.collection('Junkshop').doc(uid).set({
        'uid': uid,
        'shopName': _shopNameController.text.trim(),
        'email': _emailController.text.trim(),
        'role': 'junkshop',
        'verified': false, // ✅ MUST BE verified
        'activePermitRequestId': requestRef.id,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _showToast("Submitted! Admin will verify your permit.");
      await _auth.signOut();
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      // If auth succeeded but something later failed, you may want to
      // delete the user account as well (optional, requires re-auth).
      _showToast(e.message ?? "Auth Error", isError: true);
    } catch (e) {
      // Rollback uploaded file if Firestore write fails after upload
      if (storageRef != null) {
        try {
          await storageRef.delete();
        } catch (_) {
          // ignore rollback errors
        }
      }
      _showToast("Error: ${e.toString()}", isError: true);
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
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("Junkshop Registration"),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        child: Column(
          children: [
            const Text(
              "Business Account",
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 30),
            _buildTextField(_shopNameController, "Shop Name", Icons.store),
            const SizedBox(height: 16),
            _buildTextField(_emailController, "Business Email", Icons.email),
            const SizedBox(height: 16),
            _buildTextField(_passwordController, "Password", Icons.lock,
                isPass: true),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: Icon(_pickedFile == null
                  ? Icons.upload_file
                  : Icons.check_circle),
              label: Text(_pickedFile == null
                  ? "Upload Business Permit (PDF/Image)"
                  : "Selected: ${_pickedFile!.name}"),
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
                    backgroundColor: const Color(0xFF1FA9A7)),
                onPressed: _isLoading ? null : _registerJunkshop,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Register Business",
                        style: TextStyle(color: Colors.white)),
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
    IconData icon, {
    bool isPass = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPass,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: const Color(0xFF1FA9A7)),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF1FA9A7)),
        ),
      ),
    );
  }
}

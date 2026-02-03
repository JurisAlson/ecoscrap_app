import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cloud_functions/cloud_functions.dart';

class JunkshopAccountCreationPage extends StatefulWidget {
  const JunkshopAccountCreationPage({super.key});

  @override
  State<JunkshopAccountCreationPage> createState() =>
      _JunkshopAccountCreationPageState();
}

class _JunkshopAccountCreationPageState extends State<JunkshopAccountCreationPage> {
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

    if (result != null) {
      setState(() => _pickedFile = result.files.first);
    }
  }

  String _guessContentType(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return 'application/octet-stream';
    }
  }

  Uint8List _randomBytes(int length) {
    final r = Random.secure();
    final b = Uint8List(length);
    for (int i = 0; i < length; i++) {
      b[i] = r.nextInt(256);
    }
    return b;
  }

  /// Encrypts the file bytes with AES-256-GCM.
  /// Returns ciphertext (cipher + tag), iv, and raw dek.
  Future<({
    Uint8List ciphertext,
    Uint8List iv,
    Uint8List dek,
  })> _encryptBytesAesGcm(Uint8List plainBytes) async {
    final dek = _randomBytes(32); // 256-bit key
    final iv = _randomBytes(12);  // 96-bit nonce for GCM

    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(dek);

    final secretBox = await algorithm.encrypt(
      plainBytes,
      secretKey: secretKey,
      nonce: iv,
    );

    // ciphertext + auth tag together
    final combined = Uint8List.fromList([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes, // usually 16 bytes
    ]);

    return (ciphertext: combined, iv: iv, dek: dek);
  }

  /// Wrap the DEK on backend using your Firebase Functions Secret MASTER_KEY_B64.
  Future<Map<String, dynamic>> _wrapDekOnServer(Uint8List dek) async {
    // Your function is in asia-southeast1
    final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
    final callable = functions.httpsCallable('wrapDek');

    final res = await callable.call({'dekB64': base64Encode(dek)});
    return Map<String, dynamic>.from(res.data);
  }

  Future<void> _registerJunkshop() async {
    if (_pickedFile == null ||
        _pickedFile!.path == null ||
        _emailController.text.isEmpty ||
        _shopNameController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields and upload a permit")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1) Create Auth user
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final uid = userCredential.user!.uid;

      // 2) Create request doc id (used for both storage path and firestore)
      final requestRef = _firestore.collection('permitRequests').doc();
      final requestId = requestRef.id;

      // 3) Read selected file bytes
      final ext = (_pickedFile!.extension ?? 'bin').toLowerCase();
      final originalMimeType = _guessContentType(ext);
      final plainBytes = await File(_pickedFile!.path!).readAsBytes();

      // 4) Encrypt bytes on-device
      final enc = await _encryptBytesAesGcm(Uint8List.fromList(plainBytes));

      // 5) Wrap DEK via backend (Firebase-only secret)
      final wrap = await _wrapDekOnServer(enc.dek);

      // 6) Upload ciphertext to Storage (always .bin)
      final permitPath = 'permits/$uid/$requestId.bin';
      final storageRef = FirebaseStorage.instance.ref(permitPath);

      await storageRef.putData(
        enc.ciphertext,
        SettableMetadata(contentType: 'application/octet-stream'),
      );

      // 7) Create permit request doc (no URL stored)
      await requestRef.set({
        'uid': uid,
        'shopName': _shopNameController.text.trim(),
        'email': _emailController.text.trim(),

        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),

        // encrypted storage data
        'permitPath': permitPath,
        'ivB64': base64Encode(enc.iv),

        // wrapped DEK metadata (REQUIRED to decrypt later)
        'wrappedDekB64': wrap['wrappedDekB64'],
        'wrapIvB64': wrap['wrapIvB64'],
        'wrapTagB64': wrap['wrapTagB64'],
        'wrapAlg': wrap['wrapAlg'],

        'cipherAlg': 'AES-256-GCM',
        'gcmTagBytes': 16,

        // so admin knows how to render after decrypt
        'originalExt': ext,
        'originalMimeType': originalMimeType,
        'originalFileName': _pickedFile!.name,
      });

      // 8) Create junkshop profile doc
      await _firestore.collection('Junkshop').doc(uid).set({
        'UserID': uid,
        'ShopName': _shopNameController.text.trim(),
        'Email': _emailController.text.trim(),
        'Roles': 'Junkshop',
        'Verified': false,
        'activePermitRequestId': requestId,
        'CreatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _showToast("Submitted! Admin will verify your permit.");
      await _auth.signOut();
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      _showToast(e.message ?? "Auth Error", isError: true);
    } catch (e) {
      _showToast("Error: ${e.toString()}", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            _buildTextField(_passwordController, "Password", Icons.lock, isPass: true),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: Icon(_pickedFile == null ? Icons.upload_file : Icons.check_circle),
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
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1FA9A7)),
                onPressed: _isLoading ? null : _registerJunkshop,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Register Business", style: TextStyle(color: Colors.white)),
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

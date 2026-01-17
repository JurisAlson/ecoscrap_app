import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';


class JunkshopAccountCreationPage extends StatefulWidget {
  const JunkshopAccountCreationPage({super.key});

  @override
  State<JunkshopAccountCreationPage> createState() => _JunkshopAccountCreationPageState();
}

class _JunkshopAccountCreationPageState extends State<JunkshopAccountCreationPage> {
  // Controllers
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  PlatformFile? _pickedFile;
  bool _isLoading = false;

  // Function to pick the PDF
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'png'],
    );

    if (result != null) {
      setState(() {
        _pickedFile = result.files.first;
      });
    }
  }


final FirebaseAuth _auth = FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // The main registration logic
Future<void> _registerJunkshop() async {
  if (_pickedFile == null || _emailController.text.isEmpty || _shopNameController.text.isEmpty || _passwordController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Please fill all fields and upload a permit")),
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    String uid = userCredential.user!.uid;

    File file = File(_pickedFile!.path!);
    UploadTask uploadTask = FirebaseStorage.instance
        .ref('permits/$uid.pdf')
        .putFile(file);
    
    TaskSnapshot snapshot = await uploadTask;
    String downloadUrl = await snapshot.ref.getDownloadURL();

    // MATCHING THE LOGIN PAGE: Collection 'Junkshop' and Field 'Verified'
    await _firestore.collection('Junkshop').doc(uid).set({
      'UserID': uid,
      'ShopName': _shopNameController.text.trim(),
      'Email': _emailController.text.trim(),
      'PermitUrl': downloadUrl,
      'Roles': 'Junkshop', 
      'Verified': false, // Admin must change this to true manually in Firebase
      'CreatedAt': FieldValue.serverTimestamp(),
    });

    if (mounted) {
      _showToast("Submitted! Admin will verify your permit.");
      await _auth.signOut();
      Navigator.pop(context); // Go back to selection
    }
    

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
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            
            // Shop Name
            _buildTextField(_shopNameController, "Shop Name", Icons.store),
            const SizedBox(height: 16),
            
            // Email
            _buildTextField(_emailController, "Business Email", Icons.email),
            const SizedBox(height: 16),
            
            // Password
            _buildTextField(_passwordController, "Password", Icons.lock, isPass: true),
            
            const SizedBox(height: 30),

            // File Picker Button
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: Icon(_pickedFile == null ? Icons.upload_file : Icons.check_circle),
              label: Text(_pickedFile == null 
                  ? "Upload Business Permit (PDF)" 
                  : "Selected: ${_pickedFile!.name}"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),

            const SizedBox(height: 40),

            // Submit Button
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

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPass = false}) {
    return TextField(
      controller: controller,
      obscureText: isPass,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: const Color(0xFF1FA9A7)),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF1FA9A7))),
      ),
    );
  }
}
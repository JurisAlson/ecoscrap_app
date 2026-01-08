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
  // 1. Validation Check
  if (_pickedFile == null || _emailController.text.isEmpty || _shopNameController.text.isEmpty || _passwordController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Please fill all fields and upload a permit")),
    );
    return;
  }

  setState(() => _isLoading = true);

  try {
    // 2. Create the Auth Account
    UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    String uid = userCredential.user!.uid;

    // 3. Upload the Permit to Firebase Storage
    // Use the file path from the picker
    File file = File(_pickedFile!.path!);
    UploadTask uploadTask = FirebaseStorage.instance
        .ref('permits/$uid.pdf')
        .putFile(file);
    
    TaskSnapshot snapshot = await uploadTask;
    String downloadUrl = await snapshot.ref.getDownloadURL();

    // 4. Save to Firestore (Matching your 'userid' collection and 'Role' case)
    await _firestore.collection('userid').doc(uid).set({
      'userid': uid,
      'ShopName': _shopNameController.text.trim(),
      'email': _emailController.text.trim(),
      'permit_url': downloadUrl,
      'Role': 'Junkshop', 
      'verified': false, 
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 5. Success UI
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Submitted! Admin will verify your permit.")),
      );
      
      // 6. Final Step: Sign out and go back
      //await _auth.signOut();
      //Navigator.pop(context);
    }

  } on FirebaseAuthException catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.message ?? "Auth Error")),
    );
  } catch (e) {
    // This catches Firestore or Storage errors
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Error: ${e.toString()}")),
    );
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
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
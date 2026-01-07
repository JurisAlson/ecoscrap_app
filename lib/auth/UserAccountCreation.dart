import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserAccountCreationPage extends StatefulWidget {
  const UserAccountCreationPage({super.key});

  @override
  State<UserAccountCreationPage> createState() => _UserAccountCreationPageState();
}

class _UserAccountCreationPageState extends State<UserAccountCreationPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (_isLoading) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showSnackBar("All fields are required");
      return;
    }
    if (password != confirmPassword) {
      _showSnackBar("Passwords do not match");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      await userCredential.user?.updateDisplayName(name);
      await userCredential.user?.sendEmailVerification();

      _showSnackBar("Account created! Please verify your email before logging in.");

      await FirebaseAuth.instance.signOut();
      
      // Returns to the selection page, then selection page can pop to login
      if (mounted) Navigator.pop(context); 
    } on FirebaseAuthException catch (e) {
      _showSnackBar(e.message ?? "Account creation failed");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Matches your theme
      appBar: AppBar(
        title: const Text("User Registration"),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildTextField(_nameController, "Full Name", Icons.person_outline),
            const SizedBox(height: 15),
            _buildTextField(_emailController, "Email", Icons.email_outlined),
            const SizedBox(height: 15),
            _buildTextField(_passwordController, "Password", Icons.lock_outline, isObscure: true),
            const SizedBox(height: 15),
            _buildTextField(_confirmPasswordController, "Confirm Password", Icons.lock_reset, isObscure: true),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1FA9A7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isLoading ? null : _createAccount,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Create User Account", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isObscure = false}) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: const Color(0xFF1FA9A7)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1FA9A7)),
        ),
      ),
    );
  }
}
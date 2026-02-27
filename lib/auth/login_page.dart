import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../junkshop/junkshop_dashboard.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'forgot_password.dart';
import 'UserAccountCreation.dart';
import '../role_gate.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _ensureUserProfile(User u) async {
    final ref = FirebaseFirestore.instance.collection('Users').doc(u.uid);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        "uid": u.uid,
        "emailDisplay": u.email ?? "",
        "Roles": "user",
        "role": "user",
        "verified": false,
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final data = snap.data() ?? {};
    final updates = <String, dynamic>{
      "updatedAt": FieldValue.serverTimestamp(),
    };

    if ((data["uid"] ?? "").toString().isEmpty) updates["uid"] = u.uid;

    if ((data["emailDisplay"] ?? "").toString().isEmpty && (u.email ?? "").isNotEmpty) {
      updates["emailDisplay"] = u.email;
    }

    final roles = (data["Roles"] ?? data["roles"] ?? "").toString().trim();
    final role = (data["role"] ?? "").toString().trim();
    if (roles.isEmpty && role.isNotEmpty) updates["Roles"] = role;
    if (role.isEmpty && roles.isNotEmpty) updates["role"] = roles;

    if (updates.length > 1) {
      await ref.set(updates, SetOptions(merge: true));
    }
  }


Future<void> saveFcmToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  await FirebaseMessaging.instance.requestPermission();

  final token = await FirebaseMessaging.instance.getToken();
  if (token == null) return;

  await FirebaseFirestore.instance.collection("Users").doc(user.uid).set({
    "fcmToken": token,
    "updatedAt": FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  // keep token fresh
  FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection("Users").doc(user.uid).set({
      "fcmToken": token,
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  });
}

  Future<void> _login() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showToast("Email and password are required.", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (cred.user == null) return;
      final u = cred.user!;
      debugPrint("LOGIN OK UID=${u.uid} EMAIL=${u.email}");
      debugPrint("PROJECT=${Firebase.app().options.projectId}");

      // ✅ Ensure Users/{uid} exists so RoleGate won't block with "profile missing"
      await _ensureUserProfile(u);

      // Optional debug:
      try {
        final snap = await FirebaseFirestore.instance.collection('Users').doc(u.uid).get();
        debugPrint("ROLE DOC exists=${snap.exists} data=${snap.data()}");
      } catch (e) {
        debugPrint("ROLE READ FAILED: $e");
      }

      if (!mounted) return;

// Read role from Users/{uid}
final snap = await FirebaseFirestore.instance.collection('Users').doc(u.uid).get();
final data = snap.data() ?? {};
final role = (data['Roles'] ?? data['role'] ?? data['roles'] ?? '')
    .toString().trim().toLowerCase();
    
if (!mounted) return;

if (role == 'junkshop' || role == 'junkshops') {
  final shopName = (data['Name'] ?? data['name'] ?? data['shopName'] ?? 'Junkshop')
      .toString().trim();

  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => JunkshopDashboardPage(
        shopID: u.uid,
        shopName: shopName.isNotEmpty ? shopName : 'Junkshop',
      ),
    ),
  );
  return;
}

// only for non-junkshop users
// await _ensureUserProfile(u);

// then go RoleGate
// Navigator.pushReplacement(
//   context,
//   MaterialPageRoute(builder: (_) => const RoleGate()),
// );

// default: go through RoleGate (admin/user/collector)
Navigator.pushReplacement(
  context,
  MaterialPageRoute(builder: (_) => const RoleGate()),
);
return;

    } on FirebaseAuthException catch (e) {
      _showToast(e.message ?? "Login failed", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? Colors.redAccent : const Color(0xFF1FA9A7),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF475569)),
          prefixIcon: Icon(icon, color: const Color(0xFF475569)),
          suffixIcon: isPassword
              ? IconButton(
                  onPressed: onToggleVisibility,
                  icon: Icon(
                    obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    color: const Color(0xFF475569),
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                color: const Color(0xFF1FA9A7).withOpacity(0.20),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
                child: Container(),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -120,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                color: Colors.greenAccent.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 120, sigmaY: 120),
                child: Container(),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 80),
                  Transform.rotate(
                    angle: -0.1,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1FA9A7), Color(0xFF10B981)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.recycling, color: Colors.white, size: 40),
                    ),
                  ),
                  const SizedBox(height: 25),
                  const Text(
                    "EcoScrap",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    "Join the green movement",
                    style: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 40),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          "Sign In",
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Welcome back 🌿 enter your details",
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildTextField(
                    controller: _emailController,
                    hint: "Email Address",
                    icon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _passwordController,
                    hint: "Password",
                    icon: Icons.lock_outline,
                    isPassword: true,
                    obscureText: _obscurePassword,
                    onToggleVisibility: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
                      ),
                      child: const Text(
                        "Forgot Password?",
                        style: TextStyle(color: Color(0xFF1FA9A7), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1FA9A7),
                        foregroundColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isLoading ? null : _login,
                      child: _isLoading
                          ? const CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF0F172A))
                          : const Text(
                              "Continue",
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?", style: TextStyle(color: Color(0xFF94A3B8))),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const UserAccountCreationPage()),
                          );
                        },
                        child: const Text(
                          "Create one",
                          style: TextStyle(color: Color(0xFF1FA9A7), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
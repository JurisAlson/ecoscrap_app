import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'login_page.dart';
import '../role_gate.dart';

class EmailVerificationPage extends StatefulWidget {
  final User user;

  const EmailVerificationPage({super.key, required this.user});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  bool _sending = false;
  bool _checking = false;

  Future<void> _resendVerification() async {
    if (_sending) return;

    setState(() => _sending = true);

    await widget.user.sendEmailVerification();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Verification email sent.")),
    );

    setState(() => _sending = false);
  }

  Future<void> _checkVerification() async {
    if (_checking) return;

    setState(() => _checking = true);

    await widget.user.reload();
    final refreshedUser = FirebaseAuth.instance.currentUser;

    if (refreshedUser != null && refreshedUser.emailVerified) {
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const RoleGate()),
        (_) => false,
      );
      return;
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Email still not verified.")),
    );

    setState(() => _checking = false);
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.user.email ?? "";

    return Scaffold(
      appBar: AppBar(title: const Text("Verify Email")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mark_email_read, size: 64),
              const SizedBox(height: 16),
              const Text(
                "Email verification required",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                "A verification email was sent to:\n$email\n\n"
                "Please check your inbox and verify your account.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _sending ? null : _resendVerification,
                child: Text(_sending
                    ? "Sending..."
                    : "Resend Verification Email"),
              ),

              const SizedBox(height: 12),

              ElevatedButton(
                onPressed: _checking ? null : _checkVerification,
                child: Text(_checking
                    ? "Checking..."
                    : "I Already Verified"),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: _logout,
                child: const Text("Logout"),
              )
            ],
          ),
        ),
      ),
    );
  }
}
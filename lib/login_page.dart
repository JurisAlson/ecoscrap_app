import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dashboard.dart';
import 'create_account.dart';
import 'forgot_password.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Function to log in the user
  Future<void> _login() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // Basic validation
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Email and password are required")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Attempt to sign in
      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;

      if (user != null) {
        // Check if email is verified
        if (user.emailVerified) {
          // If verified → go to dashboard
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DashboardPage()),
          );
        } else {
          // If not verified → block access and sign out
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Please verify your email before logging in."),
            ),
          );
          await FirebaseAuth.instance.signOut();
        }
      }
    } on FirebaseAuthException catch (e) {
      // Handle common Firebase login errors
      String message = "Login failed";

      if (e.code == 'user-not-found') {
        message = "No user found for that email.";
      } else if (e.code == 'wrong-password') {
        message = "Incorrect password.";
      } else if (e.code == 'invalid-email') {
        message = "Invalid email format.";
      } else if (e.code == 'user-disabled') {
        message = "This account has been disabled.";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Something went wrong")),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo
            Image.asset("assets/images/ecoscrap_logo.png", width: 130),
            const SizedBox(height: 20),

            // Email input
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: "Email",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 15),

            // Password input
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                hintText: "Password",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Login button
            SizedBox(
              width: 120,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1FA9A7),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _isLoading ? null : _login,
                child: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Log in", style: TextStyle(fontSize: 16)),
              ),
            ),

            const SizedBox(height: 20),

            // Forgot password link
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
                );
              },
              child: const Text(
                "Forgot Password?",
                style: TextStyle(decoration: TextDecoration.underline),
              ),
            ),

            const SizedBox(height: 5),

            // Create account link
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("No account? "),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreateAccountPage(),
                      ),
                    );
                  },
                  child: const Text(
                    "Create one!",
                    style: TextStyle(
                      color: Color(0xFF1FA9A7),
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

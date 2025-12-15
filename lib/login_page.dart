import 'package:flutter/material.dart';
import 'dashboard.dart';
import 'forgot_password.dart';
import 'create_account.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            // Logo
            Image.asset(
              "assets/images/ecoscrap_logo.png",
              width: 130,
            ),

            const SizedBox(height: 20),

            // Username field
            TextField(
              decoration: InputDecoration(
                hintText: "username",
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
              ),
            ),

            const SizedBox(height: 15),

            // Password field
            TextField(
              obscureText: true,
              decoration: InputDecoration(
                hintText: "password",
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 15),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Login button
            SizedBox(
              width: 120,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1FA9A7), // teal color
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                  MaterialPageRoute(
                    builder: (context) => const DashboardPage(),
                    ),
                  );
                },
                child: const Text(
                  "Log in",
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Forgot Password (TAPABLE)
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ForgotPasswordPage(),
                  ),
                );
              },
              child: const Text(
                "Forgot Password?",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),

            const SizedBox(height: 5),

            // Create Account
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "No account? ",
                  style: TextStyle(fontSize: 14),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateAccountPage(),
                      ),
                    );
                  },
                  child: const Text(
                    "Create one!",
                    style: TextStyle(
                      fontSize: 14,
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

import 'package:flutter/material.dart';
import 'JunkshopAccountCreation.dart';
import 'UserAccountCreation.dart';

class AccountCreationPage extends StatelessWidget {
  const AccountCreationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("Select Account Type"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSelectionBox(
              context,
              title: "User Registration",
              subtitle: "For households and individuals",
              icon: Icons.person_outline,
              destination: const UserAccountCreationPage(),
            ),
            const SizedBox(height: 20),
            _buildSelectionBox(
              context,
              title: "Junkshop Registration",
              subtitle: "For business owners and scrap yards",
              icon: Icons.storefront_outlined,
              destination: const JunkshopAccountCreationPage(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBox(BuildContext context, 
      {required String title, required String subtitle, required IconData icon, required Widget destination}) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => destination)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF1FA9A7).withOpacity(0.5)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF1FA9A7),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }
}
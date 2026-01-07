import 'package:flutter/material.dart';

class JunkshopAccountCreationPage extends StatefulWidget {
  const JunkshopAccountCreationPage({super.key});

  @override
  State<JunkshopAccountCreationPage> createState() => _JunkshopAccountCreationPageState();
}

class _JunkshopAccountCreationPageState extends State<JunkshopAccountCreationPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text("Junkshop Registration"),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Business Account",
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _usernameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Username",
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF1FA9A7))),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: "Password",
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF1FA9A7))),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () => print("PDF Picker logic goes here"),
              icon: const Icon(Icons.upload_file),
              label: const Text("Upload Business Permit (PDF)"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white10,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1FA9A7)),
                onPressed: () => print("Registering Junkshop..."),
                child: const Text("Register Business", style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
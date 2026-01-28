import 'package:flutter/material.dart';
import 'receipt_screen.dart'; // ✅ import because we navigate to it

class TransactionScreen extends StatelessWidget {
  const TransactionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text("Transactions"),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReceiptScreen()),
            );
          },
          child: const Text("NEW RECEIPT"),
        ),
      ),
    );
  }
}

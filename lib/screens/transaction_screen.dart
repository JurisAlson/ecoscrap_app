import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'receipt_screen.dart';

class TransactionScreen extends StatelessWidget {
  final String shopID;

  const TransactionScreen({super.key, required this.shopID});

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        title: const Text("Transactions"),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReceiptScreen(shopID: shopID),
            ),
          );
        },
        backgroundColor: Colors.greenAccent,
        icon: const Icon(Icons.add, color: Colors.black),
        label: const Text("NEW RECEIPT", style: TextStyle(color: Colors.black)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('Junkshop')
            .doc(shopID)
            .collection('transaction')
            .orderBy('transactionDate', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text("No transactions yet", style: TextStyle(color: Colors.grey)),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;

              final customerName = (data['customerNameDisplay'] ??
                      data['customerName'] ??
                      '') as String;

              final total = (data['totalAmountDisplay'] as num?)?.toDouble() ??
                  (data['totalAmount'] as num?)?.toDouble() ??
                  0.0;

              final ts = data['transactionDate'] as Timestamp?;
              final date = ts?.toDate();

              return ListTile(
                title: Text(
                  customerName.trim().isEmpty ? "Walk-in customer" : customerName,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  date != null ? date.toString() : '',
                  style: const TextStyle(color: Colors.grey),
                ),
                trailing: Text(
                  "₱${total.toStringAsFixed(2)}",
                  style: const TextStyle(color: Colors.greenAccent),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'receipt_screen.dart';

class TransactionScreen extends StatelessWidget {
  final String shopID;
  const TransactionScreen({super.key, required this.shopID});

  @override
  Widget build(BuildContext context) {
    final bgColor = const Color(0xFF0F172A);

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

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;

              final customerName = (data['customerName'] ?? '').toString();
              final totalAmount = (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
              final ts = data['transactionDate'] as Timestamp?;
              final dateText = ts == null
                  ? '—'
                  : "${ts.toDate().toLocal()}".split('.').first;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customerName.isEmpty ? "Walk-in Customer" : customerName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateText,
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      "₱${totalAmount.toStringAsFixed(2)}",
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard"),
      ),
     body: StreamBuilder<QuerySnapshot>(
  stream: FirebaseFirestore.instance
      .collection('permitRequests')
      .where('approved', isEqualTo: false)
      .snapshots(),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    // ✅ SHOW PERMISSION / NETWORK ERRORS
    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            "Firestore error:\n\n${snapshot.error}",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
      return const Center(child: Text("No pending permits."));
    }

    final permits = snapshot.data!.docs;

    return ListView.builder(
      itemCount: permits.length,
      itemBuilder: (context, index) {
        final doc = permits[index];
        final data = doc.data() as Map<String, dynamic>;

        final shopName = (data['shopName'] ?? 'Unknown').toString();
        final email = (data['email'] ?? '').toString();
        final permitId = doc.id;

        return Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shopName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(email),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () => _approvePermit(context, permitId),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      child: const Text("Approve"),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () => _rejectPermit(context, permitId),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text("Reject"),
                    ),
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _approvePermit(
      BuildContext context, String permitId) async {
    await FirebaseFirestore.instance
        .collection('permitRequests')
        .doc(permitId)
        .update({
      'approved': true,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Permit Approved")),
    );
  }

  Future<void> _rejectPermit(
      BuildContext context, String permitId) async {
    await FirebaseFirestore.instance
        .collection('permitRequests')
        .doc(permitId)
        .delete();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Permit Rejected")),
    );
  }
}

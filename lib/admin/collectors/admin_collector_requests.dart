import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../admin_theme_page.dart';
import 'collector_details_page.dart';

class AdminCollectorRequestsTab extends StatefulWidget {
  const AdminCollectorRequestsTab({super.key});

  @override
  State<AdminCollectorRequestsTab> createState() => _AdminCollectorRequestsTabState();
}

class _AdminCollectorRequestsTabState extends State<AdminCollectorRequestsTab> {
  String _query = ""; // unused (safe to keep)

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection("collectorRequests")
        .where("status", isEqualTo: "pending")
        .snapshots();

    return Scaffold(
      backgroundColor: AdminTheme.bg,
      body: AdminTheme.background(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.local_shipping, color: Colors.white),
                  SizedBox(width: 10),
                  Text(
                    "Collector Requests",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: stream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Text(
                        "Error: ${snap.error}",
                        style: const TextStyle(color: Colors.redAccent),
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }

                    final docs = snap.data!.docs.toList();
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text(
                          "No New Collector Requests",
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    // newest first by submittedAt (not createdAt)
                    docs.sort((a, b) {
                      final ta = a.data()["submittedAt"];
                      final tb = b.data()["submittedAt"];
                      final da = (ta is Timestamp) ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                      final db = (tb is Timestamp) ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
                      return db.compareTo(da);
                    });

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (_, i) {
                        final d = docs[i];
                        final data = d.data();

                        final name = (data["publicName"] ?? "Collector").toString();
                        final email = (data["emailDisplay"] ?? "").toString();

                        return Card(
                          color: Colors.white.withOpacity(0.06),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: ListTile(
                            title: Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              email.isNotEmpty ? email : "Tap to review",
                              style: TextStyle(color: Colors.grey.shade300),
                            ),
                            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CollectorDetailsPage(requestRef: d.reference),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
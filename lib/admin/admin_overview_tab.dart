import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'admin_theme_page.dart';

class AdminOverviewTab extends StatelessWidget {
  const AdminOverviewTab({super.key});

  Stream<int> _countStream(Query query) {
    return query.snapshots().map((s) => s.size);
  }

  @override
  Widget build(BuildContext context) {
    final permitsPending = _countStream(
      FirebaseFirestore.instance
          .collection("permitRequests")
          .where("status", isEqualTo: "pending"),
    );

    final collectorsPending = _countStream(
      FirebaseFirestore.instance
          .collection("Users")
          .where("collectorStatus", isEqualTo: "pending"),
    );

    final totalUsers = _countStream(FirebaseFirestore.instance.collection("Users"));

    final totalJunkshops = _countStream(
      FirebaseFirestore.instance.collection("Users").where("Roles", isEqualTo: "junkshop"),
    );

    final totalCollectors = _countStream(
      FirebaseFirestore.instance.collection("Users").where("Roles", isEqualTo: "collector"),
    );

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
                  Icon(Icons.dashboard, color: Colors.white),
                  SizedBox(width: 10),
                  Text(
                    "Admin Overview",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(
                  children: [
                    _statCard("Pending Permit Requests", permitsPending, icon: Icons.store),
                    const SizedBox(height: 10),
                    _statCard("Pending Collector Requests", collectorsPending, icon: Icons.local_shipping),
                    const SizedBox(height: 18),
                    _statCard("Total Users", totalUsers, icon: Icons.people),
                    const SizedBox(height: 10),
                    _statCard("Total Junkshops", totalJunkshops, icon: Icons.storefront),
                    const SizedBox(height: 10),
                    _statCard("Total Collectors", totalCollectors, icon: Icons.local_shipping),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statCard(String title, Stream<int> stream, {required IconData icon}) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snap) {
        final value = snap.data ?? 0;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              Text(
                "$value",
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      },
    );
  }
}
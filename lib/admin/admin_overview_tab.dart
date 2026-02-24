import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminOverviewTab extends StatelessWidget {
  const AdminOverviewTab({super.key});

  Stream<int> _countStream(Query query) {
    return query.snapshots().map((s) => s.size);
  }

  @override
  Widget build(BuildContext context) {
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
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
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1FA9A7).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: const Color(0xFF1FA9A7)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
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
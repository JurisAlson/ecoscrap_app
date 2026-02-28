import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';

class AdminOverviewTab extends StatelessWidget {
  const AdminOverviewTab({super.key});

  static const Color _primary = Color(0xFF1FA9A7);

  Stream<int> _countStream(Query query) => query.snapshots().map((s) => s.size);

  static const residenceRoles = [
    "residence",
    "resident",
    "user",
    "users",
    "household",
    "households",
  ];

  @override
  Widget build(BuildContext context) {
    // PENDING
    final collectorsPending = _countStream(
      FirebaseFirestore.instance.collection("Users").where("collectorStatus", isEqualTo: "pending"),
    );

    final residencesPending = _countStream(
      FirebaseFirestore.instance.collection("residentRequests").where("status", isEqualTo: "pending"),
    );

    // TOTALS
    final totalCollectors = _countStream(
      FirebaseFirestore.instance.collection("Users").where("Roles", isEqualTo: "collector"),
    );

    final totalResidences = _countStream(
      FirebaseFirestore.instance
          .collection("Users")
          .where("Roles", whereIn: residenceRoles)
          .where("adminVerified", isEqualTo: true)
          .where("adminStatus", isEqualTo: "approved"),
    );

    final totalUsers = Rx.combineLatest2<int, int, int>(
      totalCollectors,
      totalResidences,
      (collectors, residences) => collectors + residences,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),

          // ✅ Simple title row (no “header card”)
          const Row(
            children: [
              Icon(Icons.dashboard, color: Colors.white),
              SizedBox(width: 10),
              Text(
                "Admin Overview",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ✅ Small section label (not a big card)
          _sectionLabel("Pending Requests", "Not counted as residents/users yet"),

          const SizedBox(height: 10),

          // ✅ Compact grid for pending (reduces vertical chaos)
          Row(
            children: [
              Expanded(
                child: _miniStatCard(
                  title: "Collectors",
                  stream: collectorsPending,
                  icon: Icons.local_shipping,
                  accent: const Color(0xFF7CF5F2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _miniStatCard(
                  title: "Residences",
                  stream: residencesPending,
                  icon: Icons.home_outlined,
                  accent: Colors.orangeAccent,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // ✅ Totals section
          _sectionLabel("Totals", "Approved / verified only"),

          const SizedBox(height: 10),

          _statCard(
            "Total Users",
            "Verified residents + collectors",
            totalUsers,
            icon: Icons.people,
            accent: _primary,
          ),
          const SizedBox(height: 10),
          _statCard(
            "Total Residences",
            "Approved residents only",
            totalResidences,
            icon: Icons.home,
            accent: Colors.greenAccent,
          ),
          const SizedBox(height: 10),
          _statCard(
            "Total Collectors",
            "Collectors in Users collection",
            totalCollectors,
            icon: Icons.local_shipping,
            accent: Colors.cyanAccent,
          ),
        ],
      ),
    );
  }

  // ---------- UI: section label ----------
  Widget _sectionLabel(String title, String subtitle) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ---------- UI: compact pending cards ----------
  Widget _miniStatCard({
    required String title,
    required Stream<int> stream,
    required IconData icon,
    required Color accent,
  }) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snap) {
        final value = snap.data ?? 0;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.045),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // top row: icon + title
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accent.withOpacity(0.18)),
                    ),
                    child: Icon(icon, color: accent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // big number
              Text(
                "$value",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Pending",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------- UI: normal stat cards ----------
  Widget _statCard(
    String title,
    String subtitle,
    Stream<int> stream, {
    required IconData icon,
    required Color accent,
  }) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snap) {
        final value = snap.data ?? 0;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.045),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: accent.withOpacity(0.18)),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.62),
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "$value",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
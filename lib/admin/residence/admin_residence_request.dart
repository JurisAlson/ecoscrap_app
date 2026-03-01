import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../admin_theme_page.dart';
import '../residence/residence_details_page.dart';

class AdminResidentRequestsTab extends StatefulWidget {
  const AdminResidentRequestsTab({super.key});

  @override
  State<AdminResidentRequestsTab> createState() => _AdminResidentRequestsTabState();
}

class _AdminResidentRequestsTabState extends State<AdminResidentRequestsTab> {
  static const Color _primary = Color(0xFF1FA9A7);

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: child,
    );
  }

  Widget _pill(String text, {Color? bg, Color? fg, IconData? icon}) {
    final b = bg ?? Colors.white.withOpacity(0.05);
    final f = fg ?? Colors.white.withOpacity(0.85);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: b,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: f),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(color: f, fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: _panel(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _primary.withOpacity(0.22)),
              ),
              child: const Icon(Icons.inbox_outlined, color: _primary),
            ),
            const SizedBox(height: 12),
            const Text(
              "No New Resident Requests",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              "Pending requests will appear here for admin review.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.62), height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection("residentRequests")
        .where("status", isEqualTo: "pending")
        .snapshots();

    return Scaffold(
      backgroundColor: AdminTheme.bg,
      body: AdminTheme.background(
        child: Padding(
          // ✅ match the new style padding
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              const Row(
                children: [
                  Icon(Icons.home_outlined, color: Colors.white),
                  SizedBox(width: 10),
                  Text(
                    "Resident Requests",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ✅ Small info header (uniform dashboard feel)
              _panel(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _primary.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _primary.withOpacity(0.22)),
                      ),
                      child: const Icon(Icons.verified_user_outlined, color: _primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Pending Requests",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "Review submissions to confirm resident information before approving access.",
                            style: TextStyle(color: Colors.white.withOpacity(0.62), height: 1.25),
                          ),
                          const SizedBox(height: 10),
                          _pill(
                            "RESIDENT VERIFICATION",
                            bg: _primary.withOpacity(0.14),
                            fg: _primary,
                            icon: Icons.home_work_outlined,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: stream,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _panel(
                        child: Text(
                          "Error: ${snap.error}",
                          style: const TextStyle(color: Colors.redAccent, height: 1.3),
                        ),
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    }

                    final docs = snap.data!.docs.toList();
                    if (docs.isEmpty) return _emptyState();

                    // newest first by submittedAt
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

                        final name = (data["publicName"] ?? "Resident").toString();
                        final email = (data["emailDisplay"] ?? "").toString();

                        // Optional: show unit/block/phase/etc if your request doc contains it
                        final unit = (data["unit"] ?? data["unitNo"] ?? "").toString().trim();

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ResidentDetailsPage(requestRef: d.reference),
                                ),
                              );
                            },
                            child: _panel(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  // left icon
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: _primary.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: _primary.withOpacity(0.20)),
                                    ),
                                    child: const Icon(Icons.home_outlined, color: _primary),
                                  ),
                                  const SizedBox(width: 12),

                                  // name/email/status
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          email.isNotEmpty ? email : "Tap to review",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.62),
                                            fontSize: 12,
                                          ),
                                        ),
                                        if (unit.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            "Unit: $unit",
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.55),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 10),
                                        _pill(
                                          "PENDING REVIEW",
                                          bg: _primary.withOpacity(0.14),
                                          fg: _primary,
                                          icon: Icons.hourglass_bottom_rounded,
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(width: 10),

                                  // trailing chevron
                                  Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.65)),
                                ],
                              ),
                            ),
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
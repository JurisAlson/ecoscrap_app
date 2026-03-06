import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HouseholdOrderPage extends StatelessWidget {
  const HouseholdOrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(
        child: Text("Not logged in.", style: TextStyle(color: Colors.white)),
      );
    }

    final query = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('householdId', isEqualTo: user.uid)
        .where('active', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .limit(1);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Error loading order: ${snap.error}",
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const _EmptyOrderState();
        }

        final d = docs.first;
        final data = d.data() as Map<String, dynamic>;

        return _OrderCard(
          requestId: d.id,
          data: data,
        );
      },
    );
  }
}

class _EmptyOrderState extends StatelessWidget {
  const _EmptyOrderState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          "No active pickup order.\n\nCreate one from the Maps Page.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;

  const _OrderCard({
    required this.requestId,
    required this.data,
  });

  static const List<String> rejectionReasons = [
    "No longer needed",
    "Wrong schedule selected",
    "Wrong pickup details",
    "Collector taking too long",
    "Changed my mind",
    "Other",
  ];

  @override
  Widget build(BuildContext context) {
    final bgColor = const Color(0xFF0F172A);

    final collectorName = (data['collectorName'] ?? '—').toString();
    final status = (data['status'] ?? '—').toString().toLowerCase();
    final pickupType = (data['pickupType'] ?? '—').toString().toLowerCase();

    final arrived = (data['arrived'] == true);
    final arrivedAt =
        data['arrivedAt'] is Timestamp ? data['arrivedAt'] as Timestamp : null;

    final scheduledAt =
        data['scheduledAt'] is Timestamp ? data['scheduledAt'] as Timestamp : null;
    final windowStart =
        data['windowStart'] is Timestamp ? data['windowStart'] as Timestamp : null;
    final windowEnd =
        data['windowEnd'] is Timestamp ? data['windowEnd'] as Timestamp : null;

    final canReject =
        !arrived && !['completed', 'cancelled', 'declined', 'rejected'].contains(status);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Current Order",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            _kv("Collector", collectorName),
            _kv("Pickup Type", pickupType),
            _kv("Status", status),
            _kv("Arrived", arrived ? "Yes" : "No"),
            if (arrived && arrivedAt != null)
              _kv("Arrived At", _formatDateTime(arrivedAt)),

            if ((data['reason'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              _kv("Reason", (data['reason'] ?? '').toString()),
            ],

            const SizedBox(height: 10),

            if (pickupType == 'window' && windowStart != null && windowEnd != null)
              _kv("Window", "${_formatTime(windowStart)} - ${_formatTime(windowEnd)}")
            else if (scheduledAt != null)
              _kv("Scheduled", _formatDateTime(scheduledAt)),

            const SizedBox(height: 16),

            if (canReject) ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _rejectOrder(context, bgColor),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text("Reject Order"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  arrived
                      ? "Collector has arrived. Rejection is no longer available."
                      : "This order can no longer be rejected.",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],

            const SizedBox(height: 10),
            Text(
              "Note: Rejecting updates your request in Firestore (requests) and saves the reason field.",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              k,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickRejectionReason(BuildContext context, Color bgColor) async {
    String selectedReason = rejectionReasons.first;

    return showDialog<String>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setD) {
            return AlertDialog(
              backgroundColor: bgColor,
              title: const Text(
                "Select reason",
                style: TextStyle(color: Colors.white),
              ),
              content: DropdownButtonFormField<String>(
                value: selectedReason,
                dropdownColor: bgColor,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.10)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                items: rejectionReasons
                    .map(
                      (reason) => DropdownMenuItem<String>(
                        value: reason,
                        child: Text(
                          reason,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setD(() => selectedReason = value);
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, selectedReason),
                  child: const Text(
                    "Submit",
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _rejectOrder(BuildContext context, Color bgColor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: bgColor,
        title: const Text(
          "Reject pickup?",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Are you sure you want to reject your current pickup request?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No", style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final reason = await _pickRejectionReason(context, bgColor);
    if (reason == null || reason.trim().isEmpty) return;

    try {
      debugPrint("🟡 Rejecting requests/$requestId");

      await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .update({
        'status': 'rejected',
        'active': false,
        'reason': reason.trim(),
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pickup order rejected.")),
      );
    } on FirebaseException catch (e, st) {
      debugPrint("🔴 Reject failed (FirebaseException)");
      debugPrint("code=${e.code}");
      debugPrint("message=${e.message}");
      debugPrint(st.toString());

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Reject failed: ${e.code} • ${e.message ?? ''}")),
      );
    } catch (e, st) {
      debugPrint("🔴 Reject failed (unknown): $e");
      debugPrint(st.toString());

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Reject failed: $e")),
      );
    }
  }

  String _formatDateTime(Timestamp ts) {
    final dt = ts.toDate();
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ];
    final m = months[dt.month - 1];
    int hour = dt.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    final mm = dt.minute.toString().padLeft(2, '0');
    return "${dt.day} $m ${dt.year} • $hour:$mm $ampm";
  }

  String _formatTime(Timestamp ts) {
    final dt = ts.toDate();
    int hour = dt.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    final mm = dt.minute.toString().padLeft(2, '0');
    return "$hour:$mm $ampm";
  }
}
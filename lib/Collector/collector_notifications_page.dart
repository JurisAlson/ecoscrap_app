import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'collector_pickup_map_page.dart';

class CollectorNotificationsPage extends StatelessWidget {
  const CollectorNotificationsPage({super.key});

  Future<void> _accept(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final data = doc.data();
    final gp = data['pickupLocation'] as GeoPoint?;

    if (gp == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pickup has no location.")),
      );
      return;
    }

    try {
      await doc.reference.update({
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });


      if (!context.mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CollectorPickupMapPage(
            requestId: doc.id,
            pickupLat: gp.latitude,
            pickupLng: gp.longitude,
            pickupAddress: (data['pickupAddress'] ?? '').toString(),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Accept failed: $e")),
      );
    }
  }

  Future<void> _decline(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await doc.reference.update({
        'declinedBy': FieldValue.arrayUnion([user.uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Declined.")),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Decline failed: $e")),
      );
    }
  }

  Future<void> _prompt(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    final address = (data['pickupAddress'] ?? 'Unknown address').toString();

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Pickup Request"),
        content: Text("Address:\n$address\n\nAccept this pickup?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, "decline"), child: const Text("Decline")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, "accept"), child: const Text("Accept")),
        ],
      ),
    );

    if (choice == "accept") {
      await _accept(context, doc);
    } else if (choice == "decline") {
      await _decline(context, doc);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        title: const Text("Notifications"),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
        .collection('pickupRequests')
        .where('collectorId', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .where('status', whereIn: ['pending', 'scheduled'])
        .snapshots(),

        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Text(
                "Failed to load pickups:\n${snap.error}",
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            );
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text("No pending pickup requests.", style: TextStyle(color: Colors.white)),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i];
              final data = d.data();
              final address = (data['pickupAddress'] ?? 'Unknown address').toString();

              return InkWell(
                onTap: () => _prompt(context, d),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
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
                          color: Colors.green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.local_shipping_outlined, color: Colors.green),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "New pickup request",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.grey.shade500),
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
}
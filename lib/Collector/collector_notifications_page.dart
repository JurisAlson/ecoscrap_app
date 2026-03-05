import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../chat/services/chat_services.dart';
import '../chat/screens/chat_page.dart';
import '../../constants/app_constants.dart';

class CollectorNotificationsPage extends StatefulWidget {
  const CollectorNotificationsPage({super.key});

  @override
  State<CollectorNotificationsPage> createState() => _CollectorNotificationsPageState();
}

class _CollectorNotificationsPageState extends State<CollectorNotificationsPage> {
  static const Color primaryColor = Color(0xFF1FA9A7);
  static const Color bgColor = Color(0xFF0F172A);

  final ChatService _chat = ChatService();

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    _markCollectorNotifsSeen();
  }

  Future<void> _markCollectorNotifsSeen() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
      'lastNotifSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _acceptPickup(String requestId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('requests').doc(requestId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw "Request not found";

        final data = snap.data() as Map<String, dynamic>;
        final cid = (data['collectorId'] ?? '').toString().trim();
        final active = data['active'] == true;
        final status = (data['status'] ?? '').toString().toLowerCase();

        if (!active) throw "Request not active";
        if (!(status == "pending" || status == "scheduled")) throw "Not acceptable";
        if (cid.isNotEmpty && cid != user.uid) throw "Already assigned";

        final update = <String, dynamic>{
          'status': 'accepted',
          'active': true,
          'acceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // only set collectorId if empty
        if (cid.isEmpty) {
          update['collectorId'] = user.uid;
        }

        tx.update(ref, update);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pickup accepted.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Accept failed: $e")),
      );
    }
  }

  Future<void> _declinePickup(String requestId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
        'status': 'declined',
        'active': false,
        'declinedBy': FieldValue.arrayUnion([user.uid]),
        'declinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Declined.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Decline failed: $e")),
      );
    }
  }

  Future<void> _promptPickupAction({
    required BuildContext context,
    required String requestId,
    required Map<String, dynamic> data,
  }) async {
    final address = (data['pickupAddress'] ?? 'Unknown address').toString();
    final household = (data['householdName'] ?? 'Household').toString();
    final bagLabel = (data['bagLabel'] ?? '').toString();
    final bagKgNum = (data['bagKg'] is num) ? (data['bagKg'] as num).toDouble() : null;

    final distanceKm = (data['distanceKm'] is num) ? (data['distanceKm'] as num).toDouble() : null;
    final etaMinutes = (data['etaMinutes'] is num) ? (data['etaMinutes'] as num).toInt() : null;

    final scheduleText = _formatPickupSchedule(data);
    final source = (data['pickupSource'] ?? '').toString();

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Pickup Request"),
        content: SingleChildScrollView(
          child: Text(
            "Household: $household\n"
            "Address: $address\n"
            "${bagLabel.isNotEmpty ? "Bag: $bagLabel${bagKgNum != null ? " (${bagKgNum.toStringAsFixed(1)} kg)" : ""}\n" : ""}"
            "${distanceKm != null ? "Distance: ${distanceKm.toStringAsFixed(2)} km\n" : ""}"
            "${etaMinutes != null ? "ETA: $etaMinutes min\n" : ""}"
            "Schedule: $scheduleText\n"
            "${source.isNotEmpty ? "Pickup Source: $source\n" : ""}",
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, "decline"),
            child: const Text("DECLINE"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, "accept"),
            child: const Text("ACCEPT"),
          ),
        ],
      ),
    );

    if (choice == "accept") {
      await _acceptPickup(requestId);
    } else if (choice == "decline") {
      await _declinePickup(requestId);
    }
  }

  String _formatPickupSchedule(Map<String, dynamic> data) {
    final type = (data['pickupType'] ?? '').toString();
    if (type == 'now') return "Now (ASAP)";

    Timestamp? ts(dynamic v) => v is Timestamp ? v : null;

    final startTs = ts(data['windowStart']) ?? ts(data['scheduledAt']);
    final endTs = ts(data['windowEnd']);

    if (startTs == null) return "Scheduled";

    String hm(DateTime d) {
      int hour = d.hour % 12;
      if (hour == 0) hour = 12;
      final ampm = d.hour >= 12 ? "PM" : "AM";
      return "$hour:${_two(d.minute)} $ampm";
    }

    final s = startTs.toDate();
    final date = "${s.year}-${_two(s.month)}-${_two(s.day)}";

    if (endTs == null) return "$date • ${hm(s)}";

    final e = endTs.toDate();
    return "$date • ${hm(s)}–${hm(e)}";
  }

  Future<void> _openJunkshopChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final junkshopUid = AppConstants.primaryJunkshopUid;

    if (junkshopUid.isEmpty || junkshopUid == "07Wi7N8fALh2yqNdt1CQgIYVGE43") {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Junkshop UID is not configured.")),
      );
      return;
    }

    final chatId = await _chat.ensureJunkshopChatForActivePickup(
      junkshopUid: junkshopUid,
      collectorUid: user.uid,
    );

    if (chatId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat is only available during an active pickup.")),
      );
      return;
    }

    String junkshopName = "Junkshop";
    try {
      final jDoc = await FirebaseFirestore.instance.collection("Users").doc(junkshopUid).get();
      final j = jDoc.data() ?? {};
      junkshopName = (j["shopName"] ?? j["name"] ?? "Junkshop").toString();
    } catch (_) {}

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          chatId: chatId,
          title: junkshopName,
          otherUserId: junkshopUid,
        ),
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _notifTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primaryColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                if (trailing != null) ...[
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerLeft, child: trailing),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }
  

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: bgColor,
        body: Center(child: Text("Not logged in", style: TextStyle(color: Colors.white))),
      );
    }

    final unassignedQuery = FirebaseFirestore.instance
      .collection('requests')
      .where('type', isEqualTo: 'pickup')
      .where('active', isEqualTo: true)
      .where('collectorId', isEqualTo: "") // ✅ REQUIRED
      .where('status', whereIn: ['pending', 'scheduled'])
      .orderBy('updatedAt', descending: true);

    final mineQuery = FirebaseFirestore.instance
      .collection('requests')
      .where('type', isEqualTo: 'pickup')
      .where('collectorId', isEqualTo: user.uid)
      .where('status', whereIn: ['pending', 'scheduled'])
      .orderBy('updatedAt', descending: true);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Pickup Requests",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: unassignedQuery.snapshots(),
                builder: (context, aSnap) {
                  if (aSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (aSnap.hasError) {
                    return Center(
                      child: Text(
                        "Failed to load pickups:\n${aSnap.error}",
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: mineQuery.snapshots(),
                    builder: (context, bSnap) {
                      if (bSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (bSnap.hasError) {
                        return Center(
                          child: Text(
                            "Failed to load pickups:\n${bSnap.error}",
                            style: const TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      final uid = user.uid;

                      // ---- merge + de-dup by doc.id ----
                      final Map<String, QueryDocumentSnapshot> byId = {};

                      for (final d in (aSnap.data?.docs ?? [])) {
                        final data = d.data() as Map<String, dynamic>;
                        final cid = (data['collectorId'] ?? '').toString().trim();

                        // keep only UNASSIGNED from this query
                        if (cid.isEmpty) byId[d.id] = d;
                      }
                      for (final d in (bSnap.data?.docs ?? [])) {
                        byId[d.id] = d; // mine overrides if duplicates
                      }

                      // ---- filter out ones I declined ----
                      final docs = byId.values.where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        final declinedBy = (data['declinedBy'] as List?) ?? [];
                        return !declinedBy.contains(uid);
                      }).toList();

                      // ---- sort newest first (updatedAt fallback createdAt) ----
                      Timestamp? ts(dynamic v) => v is Timestamp ? v : null;
                      docs.sort((x, y) {
                        final dx = x.data() as Map<String, dynamic>;
                        final dy = y.data() as Map<String, dynamic>;
                        final tx = ts(dx['updatedAt']) ?? ts(dx['createdAt']);
                        final ty = ts(dy['updatedAt']) ?? ts(dy['createdAt']);
                        final ax = tx?.toDate().millisecondsSinceEpoch ?? 0;
                        final ay = ty?.toDate().millisecondsSinceEpoch ?? 0;
                        return ay.compareTo(ax);
                      });

                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            "No pending pickup requests.",
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final doc = docs[i];
                          final data = doc.data() as Map<String, dynamic>;

                          // ✅ (keep your existing tile UI below)
                          final household = (data['householdName'] ?? 'Household').toString();
                          final address = (data['pickupAddress'] ?? '').toString();

                          final bagLabel = (data['bagLabel'] ?? '').toString();
                          final bagKg = (data['bagKg'] is num) ? (data['bagKg'] as num).toInt() : null;

                          final distanceKm = (data['distanceKm'] is num)
                              ? (data['distanceKm'] as num).toDouble()
                              : null;
                          final etaMinutes = (data['etaMinutes'] is num)
                              ? (data['etaMinutes'] as num).toInt()
                              : null;

                          final scheduleText = _formatPickupSchedule(data);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () => _promptPickupAction(
                                    context: context,
                                    requestId: doc.id,
                                    data: data,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: primaryColor.withOpacity(0.18),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: const Icon(Icons.local_shipping_outlined, color: Colors.white),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              household,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              address.isEmpty ? "No address" : address,
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
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _pill("Schedule: $scheduleText"),
                                    if (bagLabel.isNotEmpty)
                                      _pill("Bag: $bagLabel${bagKg != null ? " • ${bagKg}kg" : ""}"),
                                    if (distanceKm != null)
                                      _pill("Distance: ${distanceKm.toStringAsFixed(2)} km"),
                                    if (etaMinutes != null) _pill("ETA: $etaMinutes min"),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _declinePickup(doc.id),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: BorderSide(color: Colors.white.withOpacity(0.18)),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: const Text(
                                          "DECLINE",
                                          style: TextStyle(fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => _acceptPickup(doc.id),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: primaryColor,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                        ),
                                        child: const Text(
                                          "ACCEPT",
                                          style: TextStyle(fontWeight: FontWeight.w900),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            _notifTile(
              icon: Icons.message_outlined,
              title: "Need help?",
              subtitle: "Chat your assigned junkshop anytime.",
              trailing: TextButton(
                onPressed: () async => await _openJunkshopChat(),
                child: const Text("OPEN CHAT"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
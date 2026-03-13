import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../chat/services/chat_services.dart';
import '../chat/screens/chat_page.dart';
import '../../constants/app_constants.dart';

class CollectorNotificationsPage extends StatefulWidget {
  const CollectorNotificationsPage({super.key});

  @override
  State<CollectorNotificationsPage> createState() =>
      _CollectorNotificationsPageState();
}

class _CollectorNotificationsPageState
    extends State<CollectorNotificationsPage> {
  static const Color primaryColor = Color(0xFF1FA9A7);
  static const Color bgColor = Color(0xFF0F172A);

  static const List<String> declineReasons = [
    "Too far from my location",
    "Already handling another pickup",
    "Cannot complete right now",
    "Other",
  ];

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

    final db = FirebaseFirestore.instance;
    final ref = db.collection('requests').doc(requestId);

    try {
      await db.runTransaction((tx) async {
        final currentSnap = await tx.get(ref);
        if (!currentSnap.exists) throw "Request not found";

        final currentData = currentSnap.data() as Map<String, dynamic>;
        final currentCollectorId =
            (currentData['collectorId'] ?? '').toString().trim();
        final currentStatus =
            (currentData['status'] ?? '').toString().toLowerCase();
        final currentActive = currentData['active'] == true;

        if (!currentActive) throw "Request not active";
        if (!(currentStatus == 'pending' || currentStatus == 'scheduled')) {
          throw "Request is no longer available";
        }
        if (currentCollectorId.isNotEmpty && currentCollectorId != user.uid) {
          throw "Already assigned";
        }


        final update = <String, dynamic>{
          'collectorId': user.uid,
          'status': 'accepted',
          'active': true,
          'acceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

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

  Future<void> _declinePickup(String requestId, {required String reason}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('requests').doc(requestId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw "Request not found";

        final data = snap.data() as Map<String, dynamic>;
        final householdId = (data['householdId'] ?? '').toString().trim();
        final collectorName = (data['collectorName'] ?? 'Collector').toString();
        final pickupAddress = (data['fullAddress'] ?? data['pickupAddress'] ?? '').toString();

        tx.update(ref, {
          'status': 'declined',
          'active': false,
          'declinedBy': FieldValue.arrayUnion([user.uid]),
          'collectorDeclineReason': reason.trim(),
          'collectorDeclinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (householdId.isNotEmpty) {
          final notifRef = FirebaseFirestore.instance
              .collection('userNotifications')
              .doc(householdId)
              .collection('items')
              .doc();

          tx.set(notifRef, {
            'type': 'collector_declined_pickup',
            'title': 'Pickup declined',
            'message': '$collectorName declined the pickup request.',
            'reason': reason.trim(),
            'requestId': requestId,
            'pickupAddress': pickupAddress,
            'status': 'unread',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pickup declined.")),
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
    final address = (data['fullAddress'] ?? data['pickupAddress'] ?? 'Unknown address')
        .toString();
    final household = (data['householdName'] ?? 'Household').toString();
    final bagLabel = (data['bagLabel'] ?? '').toString();
    final bagKgNum =
        (data['bagKg'] is num) ? (data['bagKg'] as num).toDouble() : null;

    final distanceKm = (data['distanceKm'] is num)
        ? (data['distanceKm'] as num).toDouble()
        : null;
    final etaMinutes =
        (data['etaMinutes'] is num) ? (data['etaMinutes'] as num).toInt() : null;

    final scheduleText = _formatPickupSchedule(data);
    final source = (data['pickupSource'] ?? '').toString();
    final phoneNumber = (data['phoneNumber'] ?? '').toString();

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Pickup Request"),
        content: SingleChildScrollView(
          child: Text(
            "Household: $household\n"
            "${phoneNumber.isNotEmpty ? "Mobile: $phoneNumber\n" : ""}"
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
      await _confirmAndDeclinePickup(requestId);
    }
  }

  String _formatNotifTime(Timestamp ts) {
    final dt = ts.toDate();
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return "now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m";
    if (diff.inHours < 24) return "${diff.inHours}h";
    if (diff.inDays < 7) return "${diff.inDays}d";

    return "${dt.month}/${dt.day}";
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

  Future<String?> _pickDeclineReason(BuildContext context, Color bgColor) async {
    String selectedReason = declineReasons.first;

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
                initialValue: selectedReason,
                dropdownColor: bgColor,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.10)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: Colors.white.withOpacity(0.25)),
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                items: declineReasons
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

  Future<void> _confirmAndDeclinePickup(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: bgColor,
        title: const Text(
          "Decline request?",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Are you sure you want to decline this pickup request?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              "No",
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Yes",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final reason = await _pickDeclineReason(context, bgColor);
    if (reason == null || reason.trim().isEmpty) return;

    await _declinePickup(requestId, reason: reason);
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
        const SnackBar(
          content: Text("Chat is only available during an active pickup."),
        ),
      );
      return;
    }

    String junkshopName = "Junkshop";
    try {
      final jDoc = await FirebaseFirestore.instance
          .collection("Users")
          .doc(junkshopUid)
          .get();
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
    required String title,
    required String subtitle,
    required String timeText,
    required String status,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final isUnread = status != "read";

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUnread
            ? primaryColor.withOpacity(0.06)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isUnread
              ? primaryColor.withOpacity(0.18)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            offset: isUnread ? Offset.zero : const Offset(-0.25, 0),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: isUnread ? 1 : 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: isUnread ? 8 : 0,
                height: 8,
                margin: EdgeInsets.only(right: isUnread ? 10 : 0, top: 6),
                decoration: const BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: Colors.white.withOpacity(isUnread ? 1 : 0.92),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (timeText.isNotEmpty)
                      Text(
                        timeText,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(isUnread ? 0.72 : 0.62),
                    fontSize: 13,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: trailing,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return tile;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Text(
            "Not logged in",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final notifStream = FirebaseFirestore.instance
        .collection('userNotifications')
        .doc(user.uid)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .snapshots();

    debugPrint('COLLECTOR PAGE UID=${user.uid}');

    final unassignedQuery = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('active', isEqualTo: true)
        .where('collectorId', isEqualTo: "")
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
          "Notifications",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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

                        return StreamBuilder<QuerySnapshot>(
                          stream: notifStream,
                          builder: (context, snap) {
                            final uid = user.uid;
                            final Map<String, QueryDocumentSnapshot> byId = {};

                            for (final d in (aSnap.data?.docs ?? [])) {
                              final data = d.data() as Map<String, dynamic>;
                              final cid =
                                  (data['collectorId'] ?? '').toString().trim();
                              if (cid.isEmpty) byId[d.id] = d;
                            }

                            for (final d in (bSnap.data?.docs ?? [])) {
                              byId[d.id] = d;
                            }

                            final pickupDocs = byId.values.where((d) {
                              final data = d.data() as Map<String, dynamic>;
                              final declinedBy = (data['declinedBy'] as List?) ?? [];
                              return !declinedBy.contains(uid);
                            }).toList();

                            Timestamp? ts(dynamic v) => v is Timestamp ? v : null;

                            pickupDocs.sort((x, y) {
                              final dx = x.data() as Map<String, dynamic>;
                              final dy = y.data() as Map<String, dynamic>;
                              final tx = ts(dx['updatedAt']) ?? ts(dx['createdAt']);
                              final ty = ts(dy['updatedAt']) ?? ts(dy['createdAt']);
                              final ax = tx?.toDate().millisecondsSinceEpoch ?? 0;
                              final ay = ty?.toDate().millisecondsSinceEpoch ?? 0;
                              return ay.compareTo(ax);
                            });

                            final notifDocs = snap.data?.docs ?? [];

                            return ListView(
                              padding: const EdgeInsets.only(bottom: 20),
                              children: [
                                if (pickupDocs.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: Text(
                                        "No pending pickup requests.",
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                    ),
                                  )
                                else
                                  ...pickupDocs.map((doc) {
                                    final data =
                                        doc.data() as Map<String, dynamic>;

                                    final household =
                                        (data['householdName'] ?? 'Household')
                                            .toString();
                                    final address =
                                        (data['fullAddress'] ?? data['pickupAddress'] ?? '').toString();
                                    final phoneNumber = (data['phoneNumber'] ?? '').toString();

                                    final bagLabel =
                                        (data['bagLabel'] ?? '').toString();
                                    final bagKg = (data['bagKg'] is num)
                                        ? (data['bagKg'] as num).toInt()
                                        : null;

                                    final distanceKm = (data['distanceKm'] is num)
                                        ? (data['distanceKm'] as num).toDouble()
                                        : null;

                                    final etaMinutes = (data['etaMinutes'] is num)
                                        ? (data['etaMinutes'] as num).toInt()
                                        : null;

                                    final scheduleText =
                                        _formatPickupSchedule(data);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.08),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                                    color: primaryColor
                                                        .withOpacity(0.18),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            14),
                                                  ),
                                                  child: const Icon(
                                                    Icons
                                                        .local_shipping_outlined,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        household,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        address.isEmpty ? "No address" : address,
                                                        maxLines: 2,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: TextStyle(
                                                          color: Colors.grey.shade400,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      if (phoneNumber.isNotEmpty) ...[
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          "Mobile: $phoneNumber",
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: TextStyle(
                                                            color: Colors.grey.shade300,
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.chevron_right,
                                                  color: Colors.grey.shade500,
                                                ),
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
                                                _pill(
                                                  "Bag: $bagLabel${bagKg != null ? " • ${bagKg}kg" : ""}",
                                                ),
                                              if (distanceKm != null)
                                                _pill(
                                                  "Distance: ${distanceKm.toStringAsFixed(2)} km",
                                                ),
                                              if (etaMinutes != null)
                                                _pill("ETA: $etaMinutes min"),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton(
                                                  onPressed: () =>
                                                      _confirmAndDeclinePickup(
                                                          doc.id),
                                                  style:
                                                      OutlinedButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.white,
                                                    side: BorderSide(
                                                      color: Colors.white
                                                          .withOpacity(0.18),
                                                    ),
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    "DECLINE",
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: ElevatedButton(
                                                  onPressed: () =>
                                                      _acceptPickup(doc.id),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        primaryColor,
                                                    foregroundColor:
                                                        Colors.white,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                    ),
                                                  ),
                                                  child: const Text(
                                                    "ACCEPT",
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  }),

                                if (notifDocs.isNotEmpty) ...[
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Divider(
                                            color: Colors.white
                                                .withOpacity(0.10),
                                            thickness: 1,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10),
                                          child: Text(
                                            "NOTIFICATIONS",
                                            style: TextStyle(
                                              color: Colors.white
                                                  .withOpacity(0.55),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 1.1,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Divider(
                                            color: Colors.white
                                                .withOpacity(0.10),
                                            thickness: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ...notifDocs.map((doc) {
                                    final n =
                                        doc.data() as Map<String, dynamic>;

                                    final title =
                                        (n['title'] ?? 'Notification')
                                            .toString();
                                    final message =
                                        (n['message'] ?? '').toString();
                                    final reason = (n['reason'] ??
                                            n['collectorDeclineReason'] ??
                                            'No reason provided.')
                                        .toString();
                                    final status =
                                        (n['status'] ?? 'unread').toString();
                                    final createdAt =
                                        n['createdAt'] as Timestamp?;
                                    final timeText = createdAt != null
                                        ? _formatNotifTime(createdAt)
                                        : "";

                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: _notifTile(
                                        title: title,
                                        subtitle: message,
                                        timeText: timeText,
                                        status: status,
                                        trailing: null,
                                        onTap: () async {
                                          await showDialog(
                                            context: context,
                                            builder: (dialogContext) => Dialog(
                                              backgroundColor:
                                                  Colors.transparent,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(20),
                                                decoration: BoxDecoration(
                                                  color: bgColor,
                                                  borderRadius:
                                                      BorderRadius.circular(22),
                                                  border: Border.all(
                                                    color: Colors.white
                                                        .withOpacity(0.08),
                                                  ),
                                                ),
                                                child: SingleChildScrollView(
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        title,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 22,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          height: 18),
                                                      Text(
                                                        message,
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 15,
                                                          height: 1.4,
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                          height: 18),
                                                      Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          const Text(
                                                            "Reason: ",
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 15,
                                                            ),
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              reason,
                                                              style:
                                                                  const TextStyle(
                                                                color: Colors
                                                                    .white70,
                                                                fontSize: 14,
                                                                height: 1.4,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(
                                                          height: 20),
                                                      Align(
                                                        alignment: Alignment
                                                            .centerRight,
                                                        child: TextButton(
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                  dialogContext),
                                                          child: const Text(
                                                            "Close",
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );

                                          if (status != 'read') {
                                            await doc.reference.update({
                                              'status': 'read',
                                              'readAt':
                                                  FieldValue.serverTimestamp(),
                                            });
                                          }
                                        },
                                      ),
                                    );
                                  }),
                                ],

                                const SizedBox(height: 10),
                                _notifTile(
                                  title: "Need help?",
                                  subtitle:
                                      "Chat your assigned junkshop anytime.",
                                  timeText: "",
                                  status: "read",
                                  trailing: TextButton(
                                    onPressed: () async =>
                                        await _openJunkshopChat(),
                                    child: const Text("OPEN CHAT"),
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
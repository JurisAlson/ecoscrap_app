import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../chat/screens/chat_page.dart';
import '../Collector/collector_tracking_page.dart';

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

  Widget _buildOrderTimeline(String status) {
    final steps = <Map<String, dynamic>>[
      {
        "label": "Order placed",
        "done": ["pending", "scheduled", "accepted", "arrived", "completed"]
            .contains(status),
        "current": status == "pending" || status == "scheduled",
      },
      {
        "label": "Accepted by collector",
        "done": ["accepted", "arrived", "completed"].contains(status),
        "current": status == "accepted",
      },
      {
        "label": "Collector arrived",
        "done": ["arrived", "completed"].contains(status),
        "current": status == "arrived",
      },
      {
        "label": "Completed",
        "done": status == "completed",
        "current": status == "completed",
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Order Progress",
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(steps.length, (i) {
          final step = steps[i];
          final isLast = i == steps.length - 1;
          final done = step["done"] == true;
          final current = step["current"] == true;

          final dotColor =
              done || current ? const Color(0xFF22C55E) : Colors.white24;

          final lineColor =
              done ? const Color(0xFF22C55E) : Colors.white24;

          final textColor = current
              ? Colors.white
              : done
                  ? Colors.white70
                  : Colors.white38;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: current ? Colors.white : dotColor,
                          width: current ? 2 : 1,
                        ),
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 2,
                        height: 42,
                        color: lineColor,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 0),
                  child: Text(
                    step["label"],
                    style: TextStyle(
                      color: textColor,
                      fontSize: 13,
                      fontWeight:
                          current ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Future<void> _markChatRead(String chatId) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (me.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
        'lastReadBy': {
          me: FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("❌ Failed to mark chat read: $e");
    }
  }

  Future<void> _openCollectorChat({
    required BuildContext context,
    required String collectorId,
    required String collectorName,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final chatId = "pickup_$requestId";
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
      final snap = await chatRef.get();

      if (!snap.exists) {
        await chatRef.set({
          "type": "pickup",
          "requestId": requestId,
          "participants": [user.uid, collectorId],
          "householdUid": user.uid,
          "collectorUid": collectorId,
          "householdName": (data['householdName'] ?? 'Household').toString(),
          "collectorName": collectorName,
          "createdAt": FieldValue.serverTimestamp(),
          "lastMessage": "",
          "lastMessageAt": FieldValue.serverTimestamp(),
        });
      }

      await _markChatRead(chatId);

      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            chatId: chatId,
            title: collectorName,
            otherUserId: collectorId,
          ),
        ),
      );
    } catch (e) {
      debugPrint("Chat open error: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Unable to open chat: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = const Color(0xFF0F172A);

    final collectorName = (data['collectorName'] ?? '—').toString();
    final collectorId = (data['collectorId'] ?? '').toString().trim();
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
        !arrived && !['completed', 'cancelled', 'declined', 'rejected']
            .contains(status);

    final canChat =
        collectorId.isNotEmpty &&
        !['completed', 'cancelled', 'declined', 'rejected'].contains(status);

            final canTrack = [
              'accepted',
              'confirmed',
              'ongoing',
              'arrived',
            ].contains(status);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(right: canChat ? 56 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Current Order",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),

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

                  if (pickupType == 'window' &&
                      windowStart != null &&
                      windowEnd != null)
                    _kv(
                      "Window",
                      "${_formatTime(windowStart)} - ${_formatTime(windowEnd)}",
                    )
                  else if (scheduledAt != null)
                    _kv("Scheduled", _formatDateTime(scheduledAt)),

                  const SizedBox(height: 14),
                  _buildOrderTimeline(status),
                  const SizedBox(height: 16),

                  if (canTrack) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CollectorTrackingPage(
                                    requestId: requestId,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.location_on_outlined),
                            label: const Text("Track Collector"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1FA9A7),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (canReject) ...[
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _rejectOrder(context, bgColor),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text("Cancel Order"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
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
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  Text(
                    "Note: Rejecting updates your request in Firestore (requests) and saves the reason field.",
                    style:
                        TextStyle(color: Colors.grey.shade400, fontSize: 11),
                  ),
                ],
              ),
            ),

            if (canChat)
              Positioned(
                top: 0,
                right: 0,
                child: Builder(
                  builder: (context) {
                    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
                    final chatId = "pickup_$requestId";

                    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('chats')
                          .doc(chatId)
                          .snapshots(),
                      builder: (context, snap) {
                        bool hasUnread = false;

                        final chat = snap.data?.data();
                        if (chat != null && me.isNotEmpty) {
                          final lastMessageAt = chat['lastMessageAt'];
                          final lastMessageSenderId =
                              (chat['lastMessageSenderId'] ?? '').toString();

                          final lastReadBy = chat['lastReadBy'];
                          Timestamp? myLastRead;

                          if (lastReadBy is Map && lastReadBy[me] is Timestamp) {
                            myLastRead = lastReadBy[me] as Timestamp;
                          }

                          if (lastMessageAt is Timestamp &&
                              lastMessageSenderId.isNotEmpty &&
                              lastMessageSenderId != me) {
                            if (myLastRead == null ||
                                myLastRead.millisecondsSinceEpoch <
                                    lastMessageAt.millisecondsSinceEpoch) {
                              hasUnread = true;
                            }
                          }
                        }

                        return InkWell(
                          onTap: () => _openCollectorChat(
                            context: context,
                            collectorId: collectorId,
                            collectorName: collectorName,
                          ),
                          borderRadius: BorderRadius.circular(999),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1FA9A7).withOpacity(0.18),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.10),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_outline,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                              if (hasUnread)
                                Positioned(
                                  top: -1,
                                  right: -1,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF243047),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
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

  Future<String?> _pickRejectionReason(
      BuildContext context, Color bgColor) async {
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
          "Cancel pickup?",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "Are you sure you want to cancel your current pickup request?",
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
      debugPrint("🟡 Cancelling requests/$requestId");

      final requestRef =
          FirebaseFirestore.instance.collection('requests').doc(requestId);

      final collectorId = (data['collectorId'] ?? '').toString().trim();
      final householdId = (data['householdId'] ?? '').toString().trim();
      final householdName = (data['householdName'] ?? 'Resident').toString();
      final pickupAddress = (data['pickupAddress'] ?? '').toString();

      debugPrint('collectorId=$collectorId');
      debugPrint('WRITING TO userNotifications/$collectorId/items');

      await requestRef.update({
        'status': 'rejected',
        'active': false,
        'reason': reason.trim(),
        'rejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (collectorId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('userNotifications')
            .doc(collectorId)
            .collection('items')
            .add({
          'type': 'resident_rejected_pickup',
          'title': 'Pickup cancelled',
          'message': '$householdName cancelled the pickup request.',
          'reason': reason.trim(),
          'requestId': requestId,
          'householdName': householdName,
          'pickupAddress': pickupAddress,
          'status': 'unread',
          'createdAt': FieldValue.serverTimestamp(),
        });
        debugPrint('NOTIFICATION WRITE OK');
      }

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
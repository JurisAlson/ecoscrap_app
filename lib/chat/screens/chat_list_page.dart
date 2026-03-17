import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'chat_page.dart';

class ChatListPage extends StatelessWidget {
  final String type; // "pickup" or "junkshop"
  final String title;

  const ChatListPage({
    super.key,
    required this.type,
    required this.title,
  });

  static const Color bgColor = Color(0xFF0F172A);
  static const Color primaryColor = Color(0xFF1FA9A7);

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
      );
    }

    final baseQuery = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: me)
        .orderBy('lastMessageAt', descending: true);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -120,
            right: -120,
            child: _blurCircle(primaryColor.withOpacity(0.14), 320),
          ),
          Positioned(
            bottom: 80,
            left: -120,
            child: _blurCircle(Colors.green.withOpacity(0.10), 360),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: baseQuery.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Text(
                    "Error: ${snap.error}",
                    style: const TextStyle(color: Colors.white70),
                  ),
                );
              }

              final allDocs = snap.data?.docs ?? [];

              final docs = allDocs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final chatType = (data['type'] ?? '').toString();

                if (type == "pickup") {
                  return chatType == "pickup";
                }

                if (type == "junkshop") {
                  return chatType == "junkshop" || chatType == "dropoff";
                }

                return chatType == type;
              }).toList();

              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    "No chats yet.",
                    style: TextStyle(color: Color.fromARGB(179, 255, 255, 255)),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final d = docs[i];
                  final data = d.data() as Map<String, dynamic>;

                  final lastMsg = (data['lastMessage'] ?? "").toString();

                  final dynamic lastAtRaw = data['lastMessageAt'];
                  final dynamic createdAtRaw = data['createdAt'];
                  final dynamic timeTs =
                      (lastAtRaw is Timestamp) ? lastAtRaw : createdAtRaw;

                  final participants =
                      (data['participants'] as List?)?.cast<String>() ?? [];
                  final otherUid = participants.firstWhere(
                    (u) => u != me,
                    orElse: () => "",
                  );

                  final householdUid =
                      (data['householdUid'] ?? '').toString().trim();
                  final collectorUid =
                      (data['collectorUid'] ?? '').toString().trim();
                  final householdName =
                      (data['householdName'] ?? '').toString().trim();
                  final collectorName =
                      (data['collectorName'] ?? '').toString().trim();

                  final junkshopUid =
                      (data['junkshopUid'] ?? '').toString().trim();
                  final junkshopName =
                      (data['junkshopName'] ?? '').toString().trim();

                  final chatType = (data['type'] ?? '').toString().trim();

                  String displayNameFromChat = "";

                  if (chatType == "pickup") {
                    if (me == householdUid && collectorName.isNotEmpty) {
                      displayNameFromChat = collectorName;
                    } else if (me == collectorUid && householdName.isNotEmpty) {
                      displayNameFromChat = householdName;
                    }
                  }

                  if (chatType == "junkshop") {
                    if (me == junkshopUid && collectorName.isNotEmpty) {
                      displayNameFromChat = collectorName;
                    } else if (me == collectorUid && junkshopName.isNotEmpty) {
                      displayNameFromChat = junkshopName;
                    }
                  }

                  if (chatType == "dropoff") {
                    if (me == junkshopUid && householdName.isNotEmpty) {
                      displayNameFromChat = householdName;
                    } else if (me == householdUid && junkshopName.isNotEmpty) {
                      displayNameFromChat = junkshopName;
                    }
                  }

                  if (displayNameFromChat.isNotEmpty || otherUid.isEmpty) {
                    final displayName = displayNameFromChat.isNotEmpty
                        ? displayNameFromChat
                        : otherUid;

                    return _ChatTile(
                      name: displayName,
                      lastMsg: lastMsg,
                      timeText: _formatTime(timeTs),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatPage(
                              chatId: d.id,
                              title: displayName,
                              otherUserId: otherUid,
                            ),
                          ),
                        );
                      },
                    );
                  }

                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('Users')
                        .doc(otherUid)
                        .snapshots(),
                    builder: (context, userSnap) {
                      final u = userSnap.data?.data() ?? {};
                      final displayName = (u['shopName'] ??
                              u['name'] ??
                              u['Name'] ??
                              u['publicName'] ??
                              otherUid)
                          .toString();

                      return _ChatTile(
                        name: displayName,
                        lastMsg: lastMsg,
                        timeText: _formatTime(timeTs),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatPage(
                                chatId: d.id,
                                title: displayName,
                                otherUserId: otherUid,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  static Widget _blurCircle(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(color: Colors.transparent),
      ),
    );
  }

  static String _formatTime(dynamic ts) {
    if (ts is! Timestamp) return "";
    final dt = ts.toDate();
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;

    if (sameDay) {
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour >= 12 ? "PM" : "AM";
      final min = dt.minute.toString().padLeft(2, '0');
      return "$hour:$min $ampm";
    }
    return "${dt.month}/${dt.day}";
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.name,
    required this.lastMsg,
    required this.timeText,
    required this.onTap,
  });

  final String name;
  final String lastMsg;
  final String timeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
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
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lastMsg.isEmpty ? "(no messages yet)" : lastMsg,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.70),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  timeText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
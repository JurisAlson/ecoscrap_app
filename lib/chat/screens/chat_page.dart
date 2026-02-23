import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_services.dart';

class ChatPage extends StatefulWidget {
  final String chatId;
  final String title;
  final String otherUserId; // ✅ ADD THIS

  const ChatPage({
    super.key,
    required this.chatId,
    required this.title,
    required this.otherUserId, // ✅ ADD THIS
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const Color bgColor = Color(0xFF0F172A);
  static const Color primaryColor = Color(0xFF1FA9A7);

  final _chat = ChatService();
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  String? get _me => FirebaseAuth.instance.currentUser?.uid;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    try {
      await _chat.sendText(chatId: widget.chatId, text: text);
      _jumpToBottomSoon();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Send failed: $e")),
      );
    }
  }

  void _jumpToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatTime(dynamic ts) {
    if (ts is! Timestamp) return "";
    final dt = ts.toDate();
    int hour = dt.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    final min = dt.minute.toString().padLeft(2, '0');
    return "$hour:$min $ampm";
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final otherName = widget.title.trim().isEmpty ? "User" : widget.title.trim();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),

        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.otherUserId)
              .snapshots(),
          builder: (context, snap) {
            final otherName =
                widget.title.trim().isEmpty ? "User" : widget.title.trim();

            bool isOnline = false;
            Timestamp? lastSeen;

            if (snap.hasData && snap.data!.data() != null) {
              final data = snap.data!.data()!;
              isOnline = (data['isOnline'] ?? false) as bool;
              lastSeen = data['lastSeen'] as Timestamp?;
            }

            String statusText;
            if (isOnline) {
              statusText = "Online";
            } else if (lastSeen != null) {
              statusText = "Last seen ${_formatTime(lastSeen)}";
            } else {
              statusText = "Offline";
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  otherName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: isOnline ? Colors.greenAccent : Colors.white60,
                  ),
                ),
              ],
            );
          },
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
          Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _chat.messagesStream(widget.chatId),
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

                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text(
                          "No messages yet.",
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    _jumpToBottomSoon();

                    return ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final data = docs[i].data();
                        final text = (data['text'] ?? '').toString();
                        final senderId = (data['senderId'] ?? '').toString();
                        final createdAt = data['createdAt'];

                        final isMe = me != null && senderId == me;

                        // ✅ check previous message sender
                        final prevSenderId = (i > 0) ? (docs[i - 1].data()['senderId'] ?? '').toString() : null;

                        // ✅ show name only when sender changes (start of group), and not me
                        final showName = !isMe && (i == 0 || senderId != prevSenderId);

                        return _MessageBubble(
                          text: text,
                          isMe: isMe,
                          timeText: _formatTime(createdAt),
                          otherName: otherName,
                          showName: showName, // ✅ new
                        );
                      },
                    );
                  },
                ),
              ),

              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                style: const TextStyle(color: Colors.white),
                                cursorColor: primaryColor,
                                decoration: InputDecoration(
                                  hintText: "Type a message...",
                                  hintStyle: TextStyle(color: Colors.grey.shade400),
                                  border: InputBorder.none,
                                ),
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: _send,
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.send, color: Colors.white, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.isMe,
    required this.timeText,
    required this.otherName,
    required this.showName, // ✅ add
  });

  final String text;
  final bool isMe;
  final String timeText;
  final String otherName;
  final bool showName; // ✅ add

  static const Color primaryColor = Color(0xFF1FA9A7);

  @override
  Widget build(BuildContext context) {
    final align = isMe ? Alignment.centerRight : Alignment.centerLeft;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : 6),
      bottomRight: Radius.circular(isMe ? 6 : 18),
    );

    final bubbleColor =
        isMe ? primaryColor.withOpacity(0.95) : Colors.white.withOpacity(0.10);

    return Align(
      alignment: align,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // ✅ show name ONLY if it's the first message in a group AND it's not me
          if (!isMe && showName)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 4),
              child: Text(
                otherName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            margin: EdgeInsets.only(bottom: showName ? 10 : 6), // optional spacing
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: radius,
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(color: Colors.white, height: 1.25),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1, // keeps bubble tight
                  child: Text(
                    timeText,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
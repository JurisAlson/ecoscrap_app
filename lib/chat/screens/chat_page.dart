import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/chat_services.dart';

class ChatPage extends StatefulWidget {
  final String chatId;
  final String title;
  final String otherUserId;

  const ChatPage({
    super.key,
    required this.chatId,
    required this.title,
    required this.otherUserId,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class PendingUploadItem {
  final String id;
  final File file;
  double progress;
  bool failed;
  String? error;

  PendingUploadItem({
    required this.id,
    required this.file,
    this.progress = 0.0,
    this.failed = false,
    this.error,
  });
}

class _FullScreenImagePage extends StatelessWidget {
  const _FullScreenImagePage({
    required this.imageUrl,
  });

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5.0,
            child: Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              },
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white70,
                  size: 42,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
class _CameraPreviewPage extends StatelessWidget {
  final File imageFile;

  const _CameraPreviewPage({
    super.key,
    required this.imageFile,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.file(
              imageFile,
              fit: BoxFit.contain,
            ),
          ),

          Positioned(
            top: 40,
            left: 16,
            child: InkWell(
              onTap: () {
                Navigator.pop(context); // cancel / retake
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: () {
                    Navigator.pop(context); // retake / cancel
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 40),
                InkWell(
                  onTap: () {
                    Navigator.pop(context, imageFile); // return file to chat page
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 30,
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

class _ChatPageState extends State<ChatPage> {
  static const Color bgColor = Color(0xFF0F172A);
  static const Color primaryColor = Color(0xFF1FA9A7);

  final _chat = ChatService();
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  final List<File> _pendingImages = [];
  final List<PendingUploadItem> _uploadingImages = [];

  bool _isMarkingSeen = false;
  String? _lastMarkedUnreadMessageId;

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

  Future<void> _pickImages() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 80);
      if (picked.isEmpty) return;

      if (!mounted) return;
      setState(() {
        _pendingImages.addAll(picked.map((x) => File(x.path)));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Pick images failed: $e")),
      );
    }
  }

  Future<void> _sendPendingImages() async {
    if (_pendingImages.isEmpty) return;

    final imagesToSend = List<File>.from(_pendingImages);

    if (!mounted) return;
    setState(() => _pendingImages.clear());

    for (final file in imagesToSend) {
      await _startSingleImageUpload(file);
    }

    _jumpToBottomSoon();
  }

  Future<void> _takePhoto() async {
  try {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (picked == null) return;
    if (!mounted) return;

    final File? fileToSend = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        builder: (_) => _CameraPreviewPage(
          imageFile: File(picked.path),
        ),
      ),
    );

    if (fileToSend == null) return;
    if (!mounted) return;

    await _startSingleImageUpload(fileToSend);
    _jumpToBottomSoon();
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Camera error: $e")),
    );
  }
}

  

  Future<void> _startSingleImageUpload(File file) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();

    final pending = PendingUploadItem(
      id: id,
      file: file,
    );

    if (!mounted) return;
    setState(() {
      _uploadingImages.add(pending);
    });

    try {
      await _chat.sendImageWithProgress(
        chatId: widget.chatId,
        file: file,
        onProgress: (progress) {
          if (!mounted) return;

          final index = _uploadingImages.indexWhere((e) => e.id == id);
          if (index == -1) return;

          setState(() {
            _uploadingImages[index].progress = progress;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _uploadingImages.removeWhere((e) => e.id == id);
      });
    } catch (e) {
      if (!mounted) return;

      final index = _uploadingImages.indexWhere((e) => e.id == id);
      if (index != -1) {
        setState(() {
          _uploadingImages[index].failed = true;
          _uploadingImages[index].error = e.toString();
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Image send failed: $e")),
      );
    }
  }

  Future<void> _retryUpload(PendingUploadItem item) async {
    if (!mounted) return;
    setState(() {
      _uploadingImages.removeWhere((e) => e.id == item.id);
    });
    await _startSingleImageUpload(item.file);
  }

  void _removeUploadingItem(String id) {
    setState(() {
      _uploadingImages.removeWhere((e) => e.id == id);
    });
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

  Future<void> _markVisibleMessagesAsSeen(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final me = _me;
    if (me == null || _isMarkingSeen || docs.isEmpty) return;

    final unreadIncoming = docs.where((doc) {
      final data = doc.data();
      final senderId = (data['senderId'] ?? '').toString();
      final seenAt = data['seenAt'];
      return senderId != me && seenAt == null;
    }).toList();

    if (unreadIncoming.isEmpty) return;

    final newestUnreadId = unreadIncoming.last.id;
    if (_lastMarkedUnreadMessageId == newestUnreadId) return;

    _isMarkingSeen = true;
    try {
      await _chat.markMessagesAsSeen(
        chatId: widget.chatId,
        currentUserId: me,
      );
      _lastMarkedUnreadMessageId = newestUnreadId;
    } catch (_) {
      // silent on purpose
    } finally {
      _isMarkingSeen = false;
    }
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
            .collection('Users')
            .doc(widget.otherUserId)
            .snapshots(),
        builder: (context, snap) {
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
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                statusText,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
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
          bottom: 100,
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

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _markVisibleMessagesAsSeen(docs);
                  });
                     

                  if (docs.isEmpty && _uploadingImages.isEmpty) {
                    return const Center(
                      child: Text(
                        "No messages yet.",
                        style: TextStyle(color: Colors.white70),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: docs.length + _uploadingImages.length,
                    itemBuilder: (context, i) {
                      if (i < docs.length) {
                        final d = docs[i];
                        final data = d.data();

                        final text = (data['text'] ?? '').toString();
                        final senderId = (data['senderId'] ?? '').toString();
                        final createdAt = data['createdAt'];
                        final seenAt = data['seenAt'];
                        final type = (data['type'] ?? 'text').toString();
                        final imageUrl = (data['imageUrl'] ?? '').toString();

                        final isMe = me != null && senderId == me;

                        final prevSenderId = (i > 0)
                            ? (docs[i - 1].data()['senderId'] ?? '').toString()
                            : null;

                        final showName =
                            !isMe && (i == 0 || senderId != prevSenderId);

                        final isLatestOutgoingMessage =
                            isMe && i == docs.length - 1;

                        final showStatusBelow = isLatestOutgoingMessage;
                        final statusTextBelow =
                            seenAt != null ? 'Seen' : 'Delivered';

                        return _MessageBubble(
                          type: type,
                          imageUrl: imageUrl,
                          text: text,
                          isMe: isMe,
                          timeText: _formatTime(createdAt),
                          otherName: otherName,
                          showName: showName,
                          showStatusBelow: showStatusBelow,
                          statusTextBelow: statusTextBelow,
                        );
                      }

                      final upload = _uploadingImages[i - docs.length];
                      return _UploadingImageBubble(
                        item: upload,
                        onRetry:
                            upload.failed ? () => _retryUpload(upload) : null,
                        onRemove: () => _removeUploadingItem(upload.id),
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
                      padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_pendingImages.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                              child: SizedBox(
                                height: 110,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _pendingImages.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) {
                                    final file = _pendingImages[index];

                                    return Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.file(
                                            file,
                                            height: 110,
                                            width: 110,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        Positioned(
                                          right: 4,
                                          top: 4,
                                          child: InkWell(
                                            onTap: () {
                                              setState(() {
                                                _pendingImages.removeAt(index);
                                              });
                                            },
                                            borderRadius:
                                                BorderRadius.circular(999),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withOpacity(0.6),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: _takePhoto,
                                icon: const Icon(
                                  Icons.camera_alt_outlined,
                                  color: Colors.white,
                                ),
                              ),
                              IconButton(
                                onPressed: _pickImages,
                                icon: const Icon(
                                  Icons.image_outlined,
                                  color: Colors.white,
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  style: const TextStyle(color: Colors.white),
                                  cursorColor: primaryColor,
                                  decoration: InputDecoration(
                                    hintText: _pendingImages.isNotEmpty
                                        ? "Add a caption or press send..."
                                        : "Type a message.",
                                    hintStyle: TextStyle(
                                      color: Colors.grey.shade400,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) {
                                    if (_pendingImages.isNotEmpty) {
                                      _sendPendingImages();
                                    } else {
                                      _send();
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  if (_pendingImages.isNotEmpty) {
                                    _sendPendingImages();
                                  } else {
                                    _send();
                                  }
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.95),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.send,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
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

class _UploadingImageBubble extends StatelessWidget {
  const _UploadingImageBubble({
    required this.item,
    required this.onRemove,
    this.onRetry,
  });

  final PendingUploadItem item;
  final VoidCallback onRemove;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 260),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF1FA9A7).withOpacity(0.22),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      item.file,
                      width: 240,
                      height: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.black.withOpacity(0.28),
                      ),
                    ),
                  ),
                  if (!item.failed)
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                  value: item.progress > 0 && item.progress < 1
                                      ? item.progress
                                      : null,
                                  strokeWidth: 3,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "Sending ${(item.progress * 100).toStringAsFixed(0)}%",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (item.failed)
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.60),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.redAccent,
                                size: 28,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "Upload failed",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (onRetry != null)
                                    TextButton.icon(
                                      onPressed: onRetry,
                                      icon: const Icon(
                                        Icons.refresh,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        "Retry",
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  TextButton.icon(
                                    onPressed: onRemove,
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      "Dismiss",
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 240,
              child: LinearProgressIndicator(
                value: item.failed ? 0 : item.progress,
                minHeight: 4,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: Colors.white.withOpacity(0.10),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFF1FA9A7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.type,
    required this.imageUrl,
    required this.text,
    required this.isMe,
    required this.timeText,
    required this.otherName,
    required this.showName,
    required this.showStatusBelow,
    required this.statusTextBelow,
  });

  final String type;
  final String imageUrl;
  final String text;
  final bool isMe;
  final String timeText;
  final String otherName;
  final bool showName;
  final bool showStatusBelow;
  final String statusTextBelow;

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

    Widget content;
    if (type == 'image' && imageUrl.isNotEmpty) {
      content = GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _FullScreenImagePage(imageUrl: imageUrl),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            imageUrl,
            width: 240,
            height: 180,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                width: 240,
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              width: 240,
              height: 180,
              color: Colors.black26,
              alignment: Alignment.center,
              child: const Icon(
                Icons.broken_image_outlined,
                color: Colors.white70,
                size: 36,
              ),
            ),
          ),
        ),
      );
    } else {
      content = Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14.5,
          height: 1.35,
        ),
      );
    }

    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showName)
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 6, bottom: 4),
                child: Text(
                  otherName,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: EdgeInsets.all(type == 'image' ? 6 : 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: radius,
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  content,
                 if (timeText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    timeText,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 11,
                    ),
                  ),
                ],
                ],
              ),
            ),
            if (showStatusBelow)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 6),
                child: Text(
                  statusTextBelow,
                  style: TextStyle(
                    color: statusTextBelow == 'Seen'
                        ? Colors.lightBlueAccent.withOpacity(0.95)
                        : Colors.white.withOpacity(0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';

class CollectorMessagesPage extends StatefulWidget {
  const CollectorMessagesPage({super.key});

  @override
  State<CollectorMessagesPage> createState() => _CollectorMessagesPageState();
}

class _CollectorMessagesPageState extends State<CollectorMessagesPage> {
  final bgColor = const Color(0xFF0F172A);
  final primaryColor = const Color(0xFF1FA9A7);

  String _search = "";

  final List<_Conversation> _convos = [
    _Conversation(
      name: "Mores Scrap Trading",
      lastMessage: "Okay sir, ready na yung pickup. ✅",
      time: "10:34 AM",
      unread: 2,
      isOnline: true,
    ),
    _Conversation(
      name: "Juan Dela Cruz (Household)",
      lastMessage: "Pwede po ba 5PM nalang? 🙏",
      time: "Yesterday",
      unread: 0,
      isOnline: false,
    ),
    _Conversation(
      name: "Maria Santos (Household)",
      lastMessage: "Thank you po!",
      time: "2d ago",
      unread: 1,
      isOnline: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _convos.where((c) {
      if (_search.trim().isEmpty) return true;
      final q = _search.toLowerCase();
      return c.name.toLowerCase().contains(q) || c.lastMessage.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: const Text("Messages"),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: Colors.grey.shade400),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      style: const TextStyle(color: Colors.white),
                      cursorColor: primaryColor,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: "Search chats...",
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                  ),
                  if (_search.isNotEmpty)
                    InkWell(
                      onTap: () => setState(() => _search = ""),
                      child: Icon(Icons.close, color: Colors.grey.shade400),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Inbox list
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  return _conversationTile(
                    convo: c,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CollectorChatThreadPage(convoName: c.name),
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

  Widget _conversationTile({required _Conversation convo, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white.withOpacity(0.08),
                  child: Text(
                    convo.name.isNotEmpty ? convo.name[0].toUpperCase() : "?",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: convo.isOnline ? Colors.green : Colors.grey.shade600,
                      shape: BoxShape.circle,
                      border: Border.all(color: bgColor, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    convo.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    convo.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(convo.time, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                const SizedBox(height: 8),
                if (convo.unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      "${convo.unread}",
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  )
                else
                  Icon(Icons.done_all, size: 18, color: Colors.grey.shade600),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Conversation {
  final String name;
  final String lastMessage;
  final String time;
  final int unread;
  final bool isOnline;

  _Conversation({
    required this.name,
    required this.lastMessage,
    required this.time,
    required this.unread,
    required this.isOnline,
  });
}

// --- reuse your thread page (you can also move it here) ---
class CollectorChatThreadPage extends StatelessWidget {
  final String convoName;
  const CollectorChatThreadPage({super.key, required this.convoName});

  @override
  Widget build(BuildContext context) {
    // keep your existing thread UI here (or move your StatefulWidget version)
    return Scaffold(
      appBar: AppBar(title: Text(convoName)),
      body: const Center(child: Text("Thread UI here")),
    );
  }
}
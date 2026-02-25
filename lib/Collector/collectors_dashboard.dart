import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'collector_notifications_page.dart';
import 'collector_pickup_map_page.dart';

// ✅ Chat (pickup list + junkshop direct chat)
import '../chat/services/chat_services.dart';
import '../chat/screens/chat_page.dart';

class CollectorsDashboardPage extends StatefulWidget {
  const CollectorsDashboardPage({super.key});

  @override
  State<CollectorsDashboardPage> createState() => _CollectorsDashboardPageState();
}

class _CollectorsDashboardPageState extends State<CollectorsDashboardPage>
    with WidgetsBindingObserver {
  // Theme
  static const Color primaryColor = Color(0xFF1FA9A7);
  static const Color bgColor = Color(0xFF0F172A);

  // ✅ Chat service
  final ChatService _chat = ChatService();

  // ✅ Footer current tab
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnline(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setOnline(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnline(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _setOnline(false);
    }
  }

  Future<void> _setOnline(bool online) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
        'isOnline': online,
        'lastSeen': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("❌ setOnline failed: $e");
    }
  }

  // ✅ Direct collector <-> junkshop chat
  // Needs Users/{collectorUid}.assignedJunkshopUid
  Future<void> _openJunkshopChat() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final db = FirebaseFirestore.instance;

    // 1) Try Users/{collectorUid} first (new/ideal flow)
    final userDoc = await db.collection('Users').doc(user.uid).get();
    final userData = userDoc.data() ?? {};

    String junkshopUid = (userData['assignedJunkshopUid'] ?? "").toString().trim();
    String junkshopName =
        (userData['assignedJunkshopName'] ?? "").toString().trim();

    // 2) Fallback: collectorRequests/{collectorUid} (old flow)
    if (junkshopUid.isEmpty) {
      final reqDoc = await db.collection('collectorRequests').doc(user.uid).get();
      final reqData = reqDoc.data() ?? {};

      // supports either key spelling just in case
      junkshopUid = (reqData['acceptedByJunkshopUid'] ??
              reqData['acceptedByJunkshopUid'] ??
              "")
          .toString()
          .trim();

      // optional: name from request (if you ever store it there)
      junkshopName = (reqData['acceptedByJunkshopName'] ??
              reqData['junkshopName'] ??
              junkshopName)
          .toString()
          .trim();

      // 3) If we found a junkshopUid via request, persist back to Users to fix future runs
      if (junkshopUid.isNotEmpty) {
        await db.collection('Users').doc(user.uid).set({
          'assignedJunkshopUid': junkshopUid,
          'assignedJunkshopName': junkshopName.isEmpty ? "Junkshop" : junkshopName,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    // Still none? show message.
    if (junkshopUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No assigned junkshop yet.")),
      );
      return;
    }

    // Create/open deterministic chat
    final chatId = await _chat.ensureJunkshopChat(
      junkshopUid: junkshopUid,
      collectorUid: user.uid,
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          chatId: chatId,
          title: junkshopName.isEmpty ? "Junkshop" : junkshopName,
          otherUserId: junkshopUid, // ✅ ADD THIS (use the variable you have)
        ),
      ),
    );
  }

  Widget _pendingVerificationScreenNew({
    required String collectorStatus,
    required bool legacyAdminOk,
    required bool legacyJunkshopOk,
    required bool legacyActive,
  }) {
    final s = collectorStatus.toLowerCase();

    String title = "Collector account pending";
    String body = "Your account is not verified yet.\nPlease wait for approval.";

    // NEW FLOW
    if (s == "pending") {
      title = "Collector request submitted";
      body = "Please wait for admin approval.";
    } else if (s == "adminapproved") {
      title = "Admin approved";
      body = "Now wait for a junkshop to accept you (first claim).";
    } else if (s == "rejected") {
      title = "Request rejected";
      body = "Your collector request was rejected.\nYou may submit again.";
    }

    // LEGACY FLOW fallback messaging
    if (collectorStatus.isEmpty) {
      if (!legacyAdminOk) {
        title = "Collector account pending";
        body = "Please wait for admin approval.";
      } else if (!legacyJunkshopOk) {
        title = "Admin approved";
        body = "Now wait for junkshop verification.";
      } else if (!legacyActive) {
        title = "Almost ready";
        body = "Your account is verified but not yet active.";
      }
    }

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, color: Colors.white70, size: 70),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _setOnline(false);
                    await FirebaseAuth.instance.signOut();
                    if (!mounted) return;
                    Navigator.pushReplacementNamed(context, '/login');
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text("Logout"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isCollectorRole(Map<String, dynamic>? data) {
    final rolesRaw =
        (data?['Roles'] ?? data?['role'] ?? "").toString().trim().toLowerCase();
    return rolesRaw == "collector" || rolesRaw == "collectors";
  }

  bool _isJunkshopVerifiedNew(Map<String, dynamic>? data) {
    return data?['junkshopVerified'] == true ||
        (data?['junkshopStatus'] ?? "").toString().toLowerCase() == "verified";
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Text("Not logged in.", style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('Users').doc(user.uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: bgColor,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          return Scaffold(
            backgroundColor: bgColor,
            body: Center(
              child: Text(
                "Error: ${snap.error}",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }

        final data = snap.data?.data() as Map<String, dynamic>?;

        // NEW FLOW checks
        final isCollectorRole = _isCollectorRole(data);
        final junkshopOkNew = _isJunkshopVerifiedNew(data);
        final collectorStatus = (data?['collectorStatus'] ?? "").toString();

        // LEGACY checks
        final legacyAdminOk = data?['adminVerified'] == true;
        final legacyJunkshopOk = data?['junkshopVerified'] == true;
        final legacyActive = data?['collectorActive'] == true;

        final allowDashboard =
            (isCollectorRole && junkshopOkNew) ||
                (legacyAdminOk && legacyJunkshopOk && legacyActive);

        if (!allowDashboard) {
          return Scaffold(
            backgroundColor: bgColor,
            body: _pendingVerificationScreenNew(
              collectorStatus: collectorStatus,
              legacyAdminOk: legacyAdminOk,
              legacyJunkshopOk: legacyJunkshopOk,
              legacyActive: legacyActive,
            ),
          );
        }

        // ✅ Footer pages (same vibe as junkshop dashboard)
        final pages = <Widget>[
          _CollectorHomeTab(
            collectorId: user.uid,
            onOpenProfile: () => _showProfileSheet(context),
          ),
          const CollectorChatListPage(),// ✅ CHATS now = assigned junkshop
          _CollectorMapTab(collectorId: user.uid),
          const CollectorNotificationsPage(),
          _CollectorProfileTab(
            onLogout: () async {
              await _setOnline(false);
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            },
            onOpenJunkshopChat: _openJunkshopChat,
          ),
        ];

        return Scaffold(
          backgroundColor: bgColor,
          body: Stack(
            children: [
              Positioned(
                top: -120,
                right: -120,
                child: _blurCircle(primaryColor.withOpacity(0.15), 320),
              ),
              Positioned(
                bottom: 80,
                left: -120,
                child: _blurCircle(Colors.green.withOpacity(0.10), 360),
              ),
              SafeArea(child: pages[_tabIndex]),
            ],
          ),
          bottomNavigationBar: _collectorFooter(
            currentIndex: _tabIndex,
            onTap: (i) => setState(() => _tabIndex = i),
          ),
        );
      },
    );
  }

  // ================== FOOTER ==================
  Widget _collectorFooter({
    required int currentIndex,
    required ValueChanged<int> onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.white54,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: "HOME"),
          BottomNavigationBarItem(icon: Icon(Icons.forum_outlined), label: "CHATS"),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: "MAP"),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_none), label: "NOTIFS"),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: "PROFILE"),
        ],
      ),
    );
  }

  // ================== UI HELPERS ==================
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

  void _showProfileSheet(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111928),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                const Icon(Icons.person, size: 64, color: Colors.white54),
                const SizedBox(height: 10),
                Text(
                  user?.displayName ?? "Collector",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  user?.email ?? "No email",
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await _setOnline(false);
                      await FirebaseAuth.instance.signOut();
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text("Logout"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ===================== HOME TAB =====================
class _AssignedJunkshopChatTab extends StatelessWidget {
  const _AssignedJunkshopChatTab({required this.openChat});

  final Future<void> Function() openChat;

  static const Color primaryColor = Color(0xFF1FA9A7);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Chats",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Assigned Junkshop",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Message your assigned junkshop here. This is your main communication channel.",
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectorHomeTab extends StatelessWidget {
  const _CollectorHomeTab({
    required this.collectorId,
    required this.onOpenProfile,
  });

  final String collectorId;
  final VoidCallback onOpenProfile;

  static const Color primaryColor = Color(0xFF1FA9A7);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 90), // leave space for footer
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header (no vertical-letter issue)
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [primaryColor, Colors.green]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.person_pin_circle, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Collector Dashboard",
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    ),
                    Text(
                      user?.displayName ?? "Collector",
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onOpenProfile,
                borderRadius: BorderRadius.circular(50),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person_outline, color: Colors.grey.shade300),
                ),
              )
            ],
          ),

          const SizedBox(height: 14),

          _card(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.eco_outlined, color: Colors.green),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Community + Environment",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Every pickup helps the community, supports junkshops, and reduces pollution.",
                        style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          const Text(
            "Logs",
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          // ✅ Your existing logs widget (same file)
          _CollectorLogsHome(collectorId: collectorId),
        ],
      ),
    );
  }

  static Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: child,
    );
  }
}

// ===================== MAP TAB =====================
// Shows "resume active pickup" if available; otherwise a friendly empty state.
class _CollectorMapTab extends StatelessWidget {
  const _CollectorMapTab({required this.collectorId});
  final String collectorId;

  @override
  Widget build(BuildContext context) {
    final resumeQuery = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('collectorId', isEqualTo: collectorId)
        .where('active', isEqualTo: true)
        .where('status', whereIn: ['pending', 'accepted', 'arrived', 'scheduled'])
        .orderBy('updatedAt', descending: true)
        .limit(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Map",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: resumeQuery.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return _emptyCard(
                  title: "No active pickup",
                  body: "When you accept a pickup, you can resume it here.",
                );
              }

              final doc = docs.first;
              final data = doc.data() as Map<String, dynamic>;

              final status = (data['status'] ?? '').toString().toLowerCase();
              final name = (data['householdName'] ?? 'Household').toString();
              final address = (data['pickupAddress'] ?? '').toString();

              return Container(
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
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.green),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Resume current pickup",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "$name • $status",
                            style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                          ),
                          if (address.isNotEmpty)
                            Text(
                              address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                            ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CollectorPickupMapPage(requestId: doc.id),
                          ),
                        );
                      },
                      child: const Text("OPEN"),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _emptyCard({required String title, required String body}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35)),
        ],
      ),
    );
  }
}

// ===================== PROFILE TAB =====================

class _CollectorProfileTab extends StatelessWidget {
  const _CollectorProfileTab({
    required this.onLogout,
    required this.onOpenJunkshopChat,
  });

  final Future<void> Function() onLogout;
  final Future<void> Function() onOpenJunkshopChat;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Profile",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              children: [
                const Icon(Icons.person, size: 64, color: Colors.white54),
                const SizedBox(height: 10),
                Text(
                  user?.displayName ?? "Collector",
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  user?.email ?? "No email",
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async => onLogout(),
                    icon: const Icon(Icons.logout),
                    label: const Text("Logout"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1FA9A7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

// ================= LOGS HOME (your existing widget, unchanged) =================




class _CollectorLogsHome extends StatelessWidget {
  const _CollectorLogsHome({required this.collectorId});
  final String collectorId;

  @override
  Widget build(BuildContext context) {
    final activeQuery = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('collectorId', isEqualTo: collectorId)
        .where('active', isEqualTo: true)
        .orderBy('updatedAt', descending: true)
        .limit(10);

    final historyQuery = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('collectorId', isEqualTo: collectorId)
        .where('active', isEqualTo: false)
        .orderBy('updatedAt', descending: true)
        .limit(25);

    final resumeQuery = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('collectorId', isEqualTo: collectorId)
        .where('active', isEqualTo: true)
        .where('status', whereIn: ['accepted', 'arrived', 'scheduled'])
        .orderBy('updatedAt', descending: true)
        .limit(1);

    return StreamBuilder<QuerySnapshot>(
      stream: activeQuery.snapshots(),
      builder: (context, activeSnap) {
        if (activeSnap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (activeSnap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Error loading logs: ${activeSnap.error}",
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }

        final activeDocs = activeSnap.data?.docs ?? [];

        return StreamBuilder<QuerySnapshot>(
          stream: historyQuery.snapshots(),
          builder: (context, historySnap) {
            if (historySnap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (historySnap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Error loading logs: ${historySnap.error}",
                  style: const TextStyle(color: Colors.white70),
                ),
              );
            }

            final historyDocs = historySnap.data?.docs ?? [];

            if (activeDocs.isEmpty && historyDocs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text("No logs yet.", style: TextStyle(color: Colors.white70)),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: resumeQuery.snapshots(),
                  builder: (context, resumeSnap) {
                    final docs = resumeSnap.data?.docs ?? [];
                    if (docs.isEmpty) return const SizedBox.shrink();

                    final doc = docs.first;
                    final data = doc.data() as Map<String, dynamic>;

                    final status = (data['status'] ?? '').toString().toLowerCase();
                    final name = (data['householdName'] ?? 'Household').toString();
                    final address = (data['pickupAddress'] ?? '').toString();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.10)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.play_arrow_rounded, color: Colors.green),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Resume current pickup",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "$name • $status",
                                  style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                                ),
                                if (address.isNotEmpty)
                                  Text(
                                    address,
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                                  ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CollectorPickupMapPage(requestId: doc.id),
                                ),
                              );
                            },
                            child: const Text("OPEN"),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 6),

                const Text(
                  "Active",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                if (activeDocs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text("No active pickups.", style: TextStyle(color: Colors.white54)),
                  )
                else
                  for (final d in activeDocs) _buildLogCard(d),

                const SizedBox(height: 14),

                const Text(
                  "History",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                if (historyDocs.isEmpty)
                  const Text("No history yet.", style: TextStyle(color: Colors.white54))
                else
                  for (final d in historyDocs) _buildLogCard(d),
              ],
            );
          },
        );
      },
    );
  }

  static Widget _buildLogCard(QueryDocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>;
    final status = (data['status'] ?? '').toString().toLowerCase();

    final name = (data['householdName'] ??
            (data['household'] is Map ? (data['household']['name']) : null) ??
            data['name'] ??
            "Unknown")
        .toString();

    final title = _statusToTitle(status);
    final ts = _pickBestTimestamp(data, status);
    final timeText = _formatTimestamp(ts);

    return _logCard(
      title: title,
      subtitle: "Name: $name",
      time: timeText,
      icon: _statusToIcon(status),
      iconBg: _statusToIconBg(status),
      iconColor: _statusToIconColor(status),
    );
  }

  static String _statusToTitle(String status) {
    switch (status) {
      case 'completed':
        return "Pickup completed";
      case 'accepted':
        return "Pickup request accepted";
      case 'pending':
        return "Pickup request received";
      case 'cancelled':
      case 'canceled':
        return "Pickup cancelled";
      default:
        return status.isEmpty ? "Pickup update" : "Pickup $status";
    }
  }

  static IconData _statusToIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'accepted':
        return Icons.thumb_up_alt_outlined;
      case 'transferred':
        return Icons.local_shipping_outlined;
      case 'pending':
        return Icons.schedule_outlined;
      case 'cancelled':
      case 'canceled':
        return Icons.cancel_outlined;
      default:
        return Icons.receipt_long;
    }
  }

  static Color _statusToIconBg(String status) {
    switch (status) {
      case 'completed':
        return Colors.green.withOpacity(0.15);
      case 'accepted':
        return Colors.blue.withOpacity(0.15);
      case 'transferred':
        return Colors.orange.withOpacity(0.15);
      case 'pending':
        return Colors.white.withOpacity(0.10);
      case 'cancelled':
      case 'canceled':
        return Colors.red.withOpacity(0.15);
      default:
        return Colors.green.withOpacity(0.15);
    }
  }

  static Color _statusToIconColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'accepted':
        return Colors.lightBlueAccent;
      case 'transferred':
        return Colors.orangeAccent;
      case 'pending':
        return Colors.white70;
      case 'cancelled':
      case 'canceled':
        return Colors.redAccent;
      default:
        return Colors.green;
    }
  }

  static Timestamp? _pickBestTimestamp(Map<String, dynamic> data, String status) {
    Timestamp? t(dynamic v) => v is Timestamp ? v : null;

    if (status == 'accepted') {
      return t(data['acceptedAt']) ?? t(data['updatedAt']) ?? t(data['createdAt']);
    }
    if (status == 'completed') {
      return t(data['completedAt']) ?? t(data['updatedAt']) ?? t(data['createdAt']);
    }
    if (status == 'transferred') {
      return t(data['transferredAt']) ?? t(data['updatedAt']) ?? t(data['createdAt']);
    }
    return t(data['updatedAt']) ?? t(data['createdAt']);
  }

  static String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return "—";
    final dt = ts.toDate();
    final now = DateTime.now();

    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = dt.year == now.year && dt.month == now.month && dt.day == now.day - 1;

    String two(int n) => n.toString().padLeft(2, '0');

    int hour = dt.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    final time = "$hour:${two(dt.minute)} $ampm";

    if (sameDay) return "Today • $time";
    if (yesterday) return "Yesterday • $time";

    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    final m = months[dt.month - 1];
    return "$m ${dt.day} • $time";
  }

  static Widget _logCard({
    required String title,
    required String subtitle,
    required String time,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
  }) {
    return Container(
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
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class CollectorChatListPage extends StatelessWidget {
  const CollectorChatListPage({super.key});

  static const Color bgColor = Color(0xFF0F172A);
  static const Color primaryColor = Color(0xFF1FA9A7);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
      );
    }

    final chatService = ChatService();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
         title: const Text(
          "Chats",
          style: TextStyle(
            color: Colors.white,       // ← force white text
            fontWeight: FontWeight.w700,
          ),
        ),
        
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('Users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data() ?? {};

          final junkshopUid =
              (data['assignedJunkshopUid'] ?? '').toString().trim();
          final junkshopName =
              (data['assignedJunkshopName'] ?? 'Junkshop').toString().trim();

          if (junkshopUid.isEmpty) {
            return Center(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: const Text(
                  "No assigned junkshop yet.\n\nOnce a junkshop accepts you, it will appear here.",
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              InkWell(
                onTap: () async {
                  final chatId = await chatService.ensureJunkshopChat(
                    junkshopUid: junkshopUid,
                    collectorUid: user.uid,
                  );

                  if (!context.mounted) return;

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        chatId: chatId,
                        title: junkshopName.isEmpty ? "Junkshop" : junkshopName,
                        otherUserId: junkshopUid, // ✅ ADD THIS (use the variable you have)
                      ),
                    ),
                  );
                },
                child: Container(
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
                          color: primaryColor.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.storefront_outlined,
                            color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              junkshopName.isEmpty ? "Junkshop" : junkshopName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Tap to open chat",
                              style: TextStyle(
                                  color: Colors.grey.shade400, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.grey.shade500),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
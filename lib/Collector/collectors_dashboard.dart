  import 'dart:ui';
  import 'package:cloud_firestore/cloud_firestore.dart';
  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:firebase_messaging/firebase_messaging.dart';
  import 'package:flutter/material.dart';
  import 'collector_messages_page.dart';
  import 'collector_notifications_page.dart';
  import 'collector_pickup_map_page.dart';
  import 'collector_transaction_page.dart';

  class CollectorsDashboardPage extends StatefulWidget {
    const CollectorsDashboardPage({super.key});

    @override
    State<CollectorsDashboardPage> createState() =>
        _CollectorsDashboardPageState();
  }

  class _CollectorsDashboardPageState extends State<CollectorsDashboardPage>
      with WidgetsBindingObserver {
    static const Color primaryColor = Color(0xFF1FA9A7);
    static const Color bgColor = Color(0xFF0F172A);
    static const int maxActivePickups = 5;

    final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

    int _tabIndex = 0;

    Future<void> _acceptPickup(String requestId) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final db = FirebaseFirestore.instance;
      final requestRef = db.collection('requests').doc(requestId);

      try {
        final activeDocs = await db
            .collection('requests')
            .where('type', isEqualTo: 'pickup')
            .where('collectorId', isEqualTo: user.uid)
            .where('active', isEqualTo: true)
            .where('status', whereIn: ['accepted', 'arrived', 'scheduled'])
            .get();

        if (activeDocs.docs.length >= maxActivePickups) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "You can only accept up to $maxActivePickups active pickups.",
              ),
            ),
          );
          return;
        }

        await db.runTransaction((tx) async {
          final requestSnap = await tx.get(requestRef);
          if (!requestSnap.exists) {
            throw Exception("Request not found.");
          }

          final data = requestSnap.data() as Map<String, dynamic>;
          final status = (data['status'] ?? '').toString().toLowerCase();
          final collectorId = (data['collectorId'] ?? '').toString();

          if (!['pending', 'scheduled'].contains(status)) {
            throw Exception("This pickup is no longer available.");
          }

          if (collectorId.isNotEmpty && collectorId != user.uid) {
            throw Exception("This pickup was already accepted by another collector.");
          }

          tx.update(requestRef, {
            'status': 'accepted',
            'active': true,
            'collectorId': user.uid,
            'acceptedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'queueNumber': activeDocs.docs.length + 1,
          });
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
          'declinedBy': FieldValue.arrayUnion([user.uid]),
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

    @override
    void initState() {
      super.initState();
      WidgetsBinding.instance.addObserver(this);
      _setOnline(true);
      _saveFcmToken();
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
   

   



    Future<void> _saveFcmToken() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      try {
        final fcm = FirebaseMessaging.instance;

        await fcm.requestPermission(alert: true, badge: true, sound: true);

        final token = await fcm.getToken();
        if (token == null || token.trim().isEmpty) {
          debugPrint("⚠️ FCM token is null/empty");
          return;
        }

        await FirebaseFirestore.instance.collection("Users").doc(user.uid).set({
          "fcmToken": token,
          "fcmUpdatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        debugPrint("✅ FCM token saved for ${user.uid}: $token");

        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
          await FirebaseFirestore.instance.collection("Users").doc(user.uid).set({
            "fcmToken": newToken,
            "fcmUpdatedAt": FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          debugPrint("✅ FCM token refreshed + saved");
        });
      } catch (e) {
        debugPrint("❌ saveFcmToken failed: $e");
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

    Widget _collectorProfileDrawer(BuildContext context) {
      final user = FirebaseAuth.instance.currentUser;

      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                const Text(
                  "Profile",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Icon(Icons.person, size: 80, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              user?.displayName ?? "Collector",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              user?.email ?? "No email",
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
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

      if (s == "pending") {
        title = "Collector request submitted";
        body = "Please wait for admin approval.";
      } else if (s == "adminapproved") {
        title = "Admin approved";
        body = "You may now access the Collector Dashboard.";
      } else if (s == "rejected") {
        title = "Request rejected";
        body = "Your collector request was rejected.\nYou may submit again.";
      }

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

    bool _isCollectorAdminApproved(Map<String, dynamic>? data) {
      final s = (data?['collectorStatus'] ?? "").toString().trim().toLowerCase();
      return s == "adminapproved";
    }

    bool _isLegacyCollectorVerified(Map<String, dynamic>? data) {
      final legacyAdminOk = data?['adminVerified'] == true;
      final legacyAdminStatus =
          (data?['adminStatus'] ?? "").toString().toLowerCase();
      final legacyJunkshopOk = data?['junkshopVerified'] == true;
      final legacyActive = data?['collectorActive'] == true;

      return legacyAdminOk &&
          legacyAdminStatus == "approved" &&
          legacyJunkshopOk &&
          legacyActive;
    }

    Widget _buildCollectorNotifBell() {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid == null) {
        return InkWell(
          onTap: () async {
            if (!context.mounted) return;
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CollectorNotificationsPage()),
            );
          },
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Icon(Icons.notifications_outlined, color: Colors.grey.shade300),
          ),
        );
      }

      final userDocStream =
          FirebaseFirestore.instance.collection('Users').doc(uid).snapshots();

      final unassignedQuery = FirebaseFirestore.instance
          .collection('requests')
          .where('type', isEqualTo: 'pickup')
          .where('status', whereIn: ['pending', 'scheduled'])
          .orderBy('updatedAt', descending: true)
          .limit(1);

      final mineQuery = FirebaseFirestore.instance
          .collection('requests')
          .where('type', isEqualTo: 'pickup')
          .where('collectorId', isEqualTo: uid)
          .where('status', whereIn: ['pending', 'scheduled'])
          .orderBy('updatedAt', descending: true)
          .limit(1);

      Widget bell({required bool hasUnread}) {
        return InkWell(
          onTap: () async {
            await FirebaseFirestore.instance.collection('Users').doc(uid).set({
              'lastNotifSeenAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

            if (!context.mounted) return;
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CollectorNotificationsPage()),
            );
          },
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedScale(
                scale: hasUnread ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Icon(
                    Icons.notifications_outlined,
                    color: hasUnread ? Colors.amberAccent : Colors.grey.shade300,
                  ),
                ),
              ),
              if (hasUnread)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      }

      Timestamp? pickTs(QuerySnapshot? qs) {
        final docs = qs?.docs ?? [];
        if (docs.isEmpty) return null;
        final data = docs.first.data() as Map<String, dynamic>;
        return data['updatedAt'] as Timestamp?;
      }

      return StreamBuilder<DocumentSnapshot>(
        stream: userDocStream,
        builder: (context, userSnap) {
          final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
          final lastSeen = userData['lastNotifSeenAt'] as Timestamp?;

          return StreamBuilder<QuerySnapshot>(
            stream: unassignedQuery.snapshots(),
            builder: (context, unassignedSnap) {
              return StreamBuilder<QuerySnapshot>(
                stream: mineQuery.snapshots(),
                builder: (context, mineSnap) {
                  final a = pickTs(unassignedSnap.data);
                  final b = pickTs(mineSnap.data);

                  Timestamp? newestTs;
                  if (a != null && b != null) {
                    newestTs = a.toDate().isAfter(b.toDate()) ? a : b;
                  } else {
                    newestTs = a ?? b;
                  }

                  bool hasUnread = false;
                  if (newestTs != null) {
                    if (lastSeen == null) {
                      hasUnread = true;
                    } else {
                      hasUnread = newestTs.toDate().isAfter(lastSeen.toDate());
                    }
                  }

                  return bell(hasUnread: hasUnread);
                },
              );
            },
          );
        },
      );
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

          final isCollectorRole = _isCollectorRole(data);
          final collectorStatus = (data?['collectorStatus'] ?? "").toString();

          final legacyAdminOk = data?['adminVerified'] == true;
          final legacyJunkshopOk = data?['junkshopVerified'] == true;
          final legacyActive = data?['collectorActive'] == true;

          final allowDashboard =
              (isCollectorRole && _isCollectorAdminApproved(data)) ||
                  _isLegacyCollectorVerified(data);

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

          final pages = <Widget>[
            _CollectorHomeTab(
              collectorId: user.uid,
              onOpenProfile: () => _scaffoldKey.currentState?.openDrawer(),
              notifBell: _buildCollectorNotifBell(),
              onOpenOrders: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _CollectorMapTab(
                      collectorId: user.uid,
                    ),
                  ),
                );
              },
            ),
            const CollectorMessagesPage(),
            const CollectorTransactionPage(embedded: true),
          ];

          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: bgColor,
            drawer: Drawer(
              backgroundColor: bgColor,
              child: SafeArea(child: _collectorProfileDrawer(context)),
            ),
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
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: "TRANSACTION"),
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

  class _CollectorHomeTab extends StatelessWidget {
    const _CollectorHomeTab({
      required this.collectorId,
      required this.onOpenProfile,
      required this.notifBell,
      required this.onOpenOrders,
    });

    final Widget notifBell;
    final String collectorId;
    final VoidCallback onOpenProfile;
    final VoidCallback onOpenOrders;

    static const Color primaryColor = Color(0xFF1FA9A7);
    static const Color surfaceColor = Color(0xFF111827);
    static const Color cardColor = Color(0xFF1A2332);
    static const Color borderColor = Color(0xFF263244);
    static const Color textMuted = Color(0xFF94A3B8);

    @override
    Widget build(BuildContext context) {
      final user = FirebaseAuth.instance.currentUser;

      final activeQuery = FirebaseFirestore.instance
          .collection('requests')
          .where('type', isEqualTo: 'pickup')
          .where('collectorId', isEqualTo: collectorId)
          .where('active', isEqualTo: true);

      final completedTodayQuery = FirebaseFirestore.instance
          .collection('requests')
          .where('type', isEqualTo: 'pickup')
          .where('collectorId', isEqualTo: collectorId)
          .where('status', isEqualTo: 'completed');

      return StreamBuilder<QuerySnapshot>(
        stream: activeQuery.snapshots(),
        builder: (context, activeSnap) {
          final activeCount = activeSnap.data?.docs.length ?? 0;

          return StreamBuilder<QuerySnapshot>(
            stream: completedTodayQuery.snapshots(),
            builder: (context, completedSnap) {
              final completedCount = completedSnap.data?.docs.length ?? 0;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // HEADER
                    Row(
                      children: [
                        GestureDetector(
                          onTap: onOpenProfile,
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: primaryColor.withOpacity(0.25),
                              ),
                            ),
                            child: const Icon(Icons.person, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Collector Dashboard",
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user?.displayName ?? "Collector",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                              ),
                            ],
                          ),
                        ),
                        notifBell,
                      ],
                    ),

                    const SizedBox(height: 18),

                    // OVERVIEW CARD
                    _glassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: primaryColor.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.route_outlined,
                                  color: primaryColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Today’s Overview",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      "Track your assigned pickups and recent activity.",
                                      style: TextStyle(
                                        color: textMuted,
                                        fontSize: 12,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.06),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    activeCount == 0
                                        ? "You have no active pickups at the moment."
                                        : "You currently have $activeCount active pickup${activeCount == 1 ? '' : 's'}.",
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // SUMMARY CARDS
                    Row(
                      children: [
                        Expanded(
                          child: _summaryCard(
                            title: "Active",
                            value: "$activeCount",
                            icon: Icons.local_shipping_outlined,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _summaryCard(
                            title: "Completed",
                            value: "$completedCount",
                            icon: Icons.check_circle_outline,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _summaryCard(
                            title: "Limit",
                            value: "20",
                            icon: Icons.layers_outlined,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // PRIMARY ACTION
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onOpenOrders,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text("Open Active Pickups"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // SECTION HEADER
                    Row(
                      children: [
                        const Text(
                          "Recent Activity",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          "Latest updates",
                          style: TextStyle(
                            color: textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    _CollectorLogsHome(collectorId: collectorId),
                  ],
                ),
              );
            },
          );
        },
      );
    }

    static Widget _glassCard({required Widget child}) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      );
    }

    static Widget _summaryCard({
      required String title,
      required String value,
      required IconData icon,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: primaryColor),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                color: textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
  }

  class _CollectorMapTab extends StatelessWidget {
    const _CollectorMapTab({
      required this.collectorId,
    });

    final String collectorId;

    static const Color primaryColor = Color(0xFF1FA9A7);
    static const Color bgColor = Color(0xFF0F172A);
    static const Color cardColor = Color(0xFF1A2332);
    static const Color borderColor = Color(0xFF263244);
    static const Color textMuted = Color(0xFF94A3B8);

    String _two(int n) => n.toString().padLeft(2, '0');

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

    @override
    Widget build(BuildContext context) {
      final activeQueueQuery = FirebaseFirestore.instance
          .collection('requests')
          .where('type', isEqualTo: 'pickup')
          .where('collectorId', isEqualTo: collectorId)
          .where('active', isEqualTo: true)
          .where('status', whereIn: ['accepted', 'arrived', 'scheduled'])
          .orderBy('acceptedAt', descending: false)
          .limit(5);

      return Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text(
            "Active Pickups",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ),
        body: Stack(
          children: [
            Positioned(
              top: -120,
              right: -120,
              child: _blurCircle(primaryColor.withOpacity(0.12), 280),
            ),
            Positioned(
              bottom: -100,
              left: -100,
              child: _blurCircle(Colors.green.withOpacity(0.08), 240),
            ),
            SafeArea(
              top: false,
              child: StreamBuilder<QuerySnapshot>(
                stream: activeQueueQuery.snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: primaryColor),
                    );
                  }

                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          "Failed to load pickups.\n${snap.error}",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    );
                  }

                  final docs = snap.data?.docs ?? [];

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _headerCard(docs.length),
                        const SizedBox(height: 16),

                        if (docs.isEmpty)
                          _emptyCard(
                            title: "No active pickups",
                            body:
                                "Accepted pickups will appear here once they are assigned to you.",
                          )
                        else ...[
                          Row(
                            children: [
                              const Text(
                                "Pickup Queue",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                "${docs.length}/5 active",
                                style: const TextStyle(
                                  color: textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          for (final doc in docs) ...[
                            _pickupQueueCard(context, doc),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final requestIds = docs.map((d) => d.id).toList();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CollectorPickupMapPage(
                                      requestIds: requestIds,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.map_outlined),
                              label: const Text("Open Route Map"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    Widget _headerCard(int count) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.route_outlined, color: primaryColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Manage Active Pickups",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Review your current pickup queue and open your route map when ready.",
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.local_shipping_outlined,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "$count active pickup${count == 1 ? '' : 's'}",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget _pickupQueueCard(BuildContext context, QueryDocumentSnapshot doc) {
      final data = doc.data() as Map<String, dynamic>;

      final status = (data['status'] ?? '').toString().toLowerCase();
      final name = (data['householdName'] ?? 'Household').toString();
      final address = (data['fullAddress'] ?? data['pickupAddress'] ?? '').toString();
      final phoneNumber = (data['phoneNumber'] ?? '').toString();
      final queueNumber = data['queueNumber'];

      final bagLabel = (data['bagLabel'] ?? '').toString();
      final bagKgNum =
          (data['bagKg'] is num) ? (data['bagKg'] as num).toDouble() : null;
      final etaMinutes =
          (data['etaMinutes'] is num) ? (data['etaMinutes'] as num).toInt() : null;
      final pickupTimeText = _formatPickupSchedule(data);

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.navigation_rounded,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        queueNumber != null ? "Stop $queueNumber" : "Pickup",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _statusChip(status),
              ],
            ),
            if (address.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.place_outlined, size: 16, color: textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textMuted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (phoneNumber.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.phone_outlined, size: 16, color: textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      phoneNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: textMuted,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metaChip(Icons.access_time_rounded, pickupTimeText),
                if (bagLabel.isNotEmpty)
                  _metaChip(
                    Icons.shopping_bag_outlined,
                    "$bagLabel${bagKgNum != null ? " • ${bagKgNum.toStringAsFixed(1)} kg" : ""}",
                  ),
                if (etaMinutes != null)
                  _metaChip(Icons.timer_outlined, "$etaMinutes min ETA"),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CollectorPickupMapPage(
                        requestIds: [doc.id],
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  "Open Pickup",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget _emptyCard({required String title, required String body}) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.route_outlined,
                size: 28,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: textMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    Widget _metaChip(IconData icon, String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 0),
            Icon(icon, size: 15, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    Widget _statusChip(String status) {
      final s = status.toLowerCase();

      String label = s.isEmpty ? "Unknown" : s[0].toUpperCase() + s.substring(1);
      IconData icon = Icons.info_outline;
      Color bg = Colors.white.withOpacity(0.08);
      Color fg = Colors.white70;

      if (s == "pending" || s == "scheduled") {
        label = "Pending";
        icon = Icons.schedule_rounded;
        bg = Colors.amber.withOpacity(0.14);
        fg = Colors.amber.shade200;
      } else if (s == "accepted") {
        label = "Accepted";
        icon = Icons.check_circle_outline;
        bg = Colors.lightBlue.withOpacity(0.14);
        fg = Colors.lightBlue.shade100;
      } else if (s == "arrived") {
        label = "Arrived";
        icon = Icons.near_me_outlined;
        bg = Colors.green.withOpacity(0.14);
        fg = Colors.green.shade200;
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    static Widget _blurCircle(Color color, double size) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
      );
    }
  }

  class _CollectorLogsHome extends StatelessWidget {
    const _CollectorLogsHome({
      required this.collectorId,
    });

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
          .orderBy('acceptedAt', descending: false)
          .limit(5);

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

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withOpacity(0.10)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Resume active pickups",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "${docs.length} active pickup(s)",
                              style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            for (final doc in docs) ...[
                              Builder(
                                builder: (_) {
                                  final data = doc.data() as Map<String, dynamic>;
                                  final status =
                                      (data['status'] ?? '').toString().toLowerCase();
                                  final name =
                                      (data['householdName'] ?? 'Household').toString();
                                  final address =
                                      (data['fullAddress'] ?? data['pickupAddress'] ?? '').toString();
                                  final phoneNumber = (data['phoneNumber'] ?? '').toString();

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.place_outlined,
                                            color: Colors.greenAccent),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "$name • $status",
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (address.isNotEmpty)
                                                Text(
                                                  address,
                                                  style: TextStyle(
                                                    color: Colors.grey.shade400,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              if (phoneNumber.isNotEmpty)
                                              Text(
                                                "Mobile: $phoneNumber",
                                                style: TextStyle(
                                                  color: Colors.grey.shade300,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),  
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  final requestIds = docs.map((d) => d.id).toList();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => CollectorPickupMapPage(
                                        requestIds: requestIds,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text("OPEN ALL ON MAP"),
                              ),
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
      final phoneNumber = (data['phoneNumber'] ?? '').toString();
      final title = _statusToTitle(status);
      final ts = _pickBestTimestamp(data, status);
      final timeText = _formatTimestamp(ts);

      return _logCard(
        title: title,
        subtitle: phoneNumber.isNotEmpty
            ? "Name: $name\nMobile: $phoneNumber"
            : "Name: $name",
        time: timeText,
        icon: _statusToIcon(status),
        iconBg: _statusToIconBg(status),
        iconColor: _statusToIconColor(status),
      );
    }

    static String _statusToTitle(String status) {
      switch (status) {
        case 'completed_pending_household':
          return "Waiting for household confirmation";
        case 'confirmed':
          return "Pickup confirmed";
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
      final yesterday =
          dt.year == now.year && dt.month == now.month && dt.day == now.day - 1;

      String two(int n) => n.toString().padLeft(2, '0');

      int hour = dt.hour % 12;
      if (hour == 0) hour = 12;
      final ampm = dt.hour >= 12 ? "PM" : "AM";
      final time = "$hour:${two(dt.minute)} $ampm";

      if (sameDay) return "Today • $time";
      if (yesterday) return "Yesterday • $time";

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
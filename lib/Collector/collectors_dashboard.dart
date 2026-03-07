<<<<<<< HEAD
import 'dart:ui';
import 'collector_notifications_page.dart';
import 'collector_messages_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'collector_transaction_page.dart';
import 'collector_pickup_map_page.dart';

import '../chat/services/chat_services.dart';
=======
  import 'dart:ui';
  import 'collector_notifications_page.dart';
  import 'collector_messages_page.dart';
  import 'package:flutter/material.dart';
  import 'package:cloud_firestore/cloud_firestore.dart';
  import 'package:firebase_auth/firebase_auth.dart';
  import 'package:firebase_messaging/firebase_messaging.dart';
  import 'collector_transaction_page.dart'; // the merged BUY/SELL page we made
  import 'collector_pickup_map_page.dart';

  // ✅ Chat (pickup list + junkshop direct chat)
  import '../chat/services/chat_services.dart';
>>>>>>> b0c204e (di pa tapos)

  class CollectorsDashboardPage extends StatefulWidget {
    const CollectorsDashboardPage({super.key});

<<<<<<< HEAD
  @override
  State<CollectorsDashboardPage> createState() =>
      _CollectorsDashboardPageState();
}

class _CollectorsDashboardPageState extends State<CollectorsDashboardPage>
    with WidgetsBindingObserver {
  static const Color primaryColor = Color(0xFF1FA9A7);
  static const Color bgColor = Color(0xFF0F172A);

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ChatService _chat = ChatService();

  int _tabIndex = 0;

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

      final existing = await db
          .collection('requests')
          .where('type', isEqualTo: 'pickup')
          .where('collectorId', isEqualTo: user.uid)
          .where('active', isEqualTo: true)
          .get();

      final hasAnotherActivePickup = existing.docs.any((d) {
        if (d.id == requestId) return false;
        final data = d.data();
        final status = (data['status'] ?? '').toString().toLowerCase();

        return status == 'pending' ||
            status == 'scheduled' ||
            status == 'accepted' ||
            status == 'arrived';
      });

      if (hasAnotherActivePickup) {
        throw "You already have an active pickup. Complete it first.";
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
=======
    @override
    State<CollectorsDashboardPage> createState() => _CollectorsDashboardPageState();
  }

  class _CollectorsDashboardPageState extends State<CollectorsDashboardPage>
      with WidgetsBindingObserver {
    // Theme
    static const Color primaryColor = Color(0xFF1FA9A7);
    static const Color bgColor = Color(0xFF0F172A);

    // ✅ RIGHT DRAWER controller
    final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

    // ✅ Chat service
    final ChatService _chat = ChatService();
    

    // ✅ Footer current tab
    int _tabIndex = 0;

    static const int maxActivePickups = 5;

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
    @override
    void initState() {
      super.initState();
      WidgetsBinding.instance.addObserver(this);
>>>>>>> b0c204e (di pa tapos)
      _setOnline(true);

      // ✅ save FCM token
      _saveFcmToken();
    }

    @override
    void dispose() {
      WidgetsBinding.instance.removeObserver(this);
      _setOnline(false);
      super.dispose();
    }

<<<<<<< HEAD
    try {
      final fcm = FirebaseMessaging.instance;

      await fcm.requestPermission(alert: true, badge: true, sound: true);

      final token = await fcm.getToken();
      if (token == null || token.trim().isEmpty) {
        debugPrint("⚠️ FCM token is null/empty");
        return;
=======
    @override
    void didChangeAppLifecycleState(AppLifecycleState state) {
      if (state == AppLifecycleState.resumed) {
        _setOnline(true);
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.detached) {
        _setOnline(false);
>>>>>>> b0c204e (di pa tapos)
      }
    }

    Future<void> _saveFcmToken() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      try {
        final fcm = FirebaseMessaging.instance;

        // ✅ Android 13+ + iOS permission
        await fcm.requestPermission(alert: true, badge: true, sound: true);

        final token = await fcm.getToken();
        if (token == null || token.trim().isEmpty) {
          debugPrint("⚠️ FCM token is null/empty");
          return;
        }

<<<<<<< HEAD
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
=======
>>>>>>> b0c204e (di pa tapos)
        await FirebaseFirestore.instance.collection("Users").doc(user.uid).set({
          "fcmToken": token,
          "fcmUpdatedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        debugPrint("✅ FCM token saved for ${user.uid}: $token");

<<<<<<< HEAD
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
      final pickupAddress = (data['pickupAddress'] ?? '').toString();

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
    String body =
        "Your account is not verified yet.\nPlease wait for approval.";

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
              const Icon(Icons.hourglass_top,
                  color: Colors.white70, size: 70),
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
          MaterialPageRoute(
            builder: (_) => const CollectorNotificationsPage(),
          ),
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
        child: Icon(
          Icons.notifications_none_rounded,
          color: Colors.grey.shade300,
        ),
      ),
    );
  }

  final unreadNotifStream = FirebaseFirestore.instance
      .collection('userNotifications')
      .doc(uid)
      .collection('items')
      .where('status', isEqualTo: 'unread')
      .snapshots();

  final unassignedStream = FirebaseFirestore.instance
      .collection('requests')
      .where('type', isEqualTo: 'pickup')
      .where('active', isEqualTo: true)
      .where('collectorId', isEqualTo: "")
      .where('status', whereIn: ['pending', 'scheduled'])
      .snapshots();

  final mineStream = FirebaseFirestore.instance
      .collection('requests')
      .where('type', isEqualTo: 'pickup')
      .where('collectorId', isEqualTo: uid)
      .where('status', whereIn: ['pending', 'scheduled', 'accepted'])
      .snapshots();

  return StreamBuilder<QuerySnapshot>(
    stream: unreadNotifStream,
    builder: (context, notifSnap) {
      return StreamBuilder<QuerySnapshot>(
        stream: unassignedStream,
        builder: (context, aSnap) {
          return StreamBuilder<QuerySnapshot>(
            stream: mineStream,
            builder: (context, bSnap) {
              if (notifSnap.hasError) {
                debugPrint('BELL notifSnap error: ${notifSnap.error}');
              }
              if (aSnap.hasError) {
                debugPrint('BELL unassignedStream error: ${aSnap.error}');
              }
              if (bSnap.hasError) {
                debugPrint('BELL mineStream error: ${bSnap.error}');
              }

              final hasUnread = (notifSnap.data?.docs.isNotEmpty ?? false);

              final Map<String, QueryDocumentSnapshot> byId = {};

              for (final d in (aSnap.data?.docs ?? [])) {
                byId[d.id] = d;
              }

              for (final d in (bSnap.data?.docs ?? [])) {
                byId[d.id] = d;
              }

              final visiblePickupDocs = byId.values.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final declinedRaw = data['declinedBy'];
                final declinedBy = declinedRaw is List
                    ? declinedRaw.map((e) => e.toString()).toList()
                    : <String>[];

                final active = data['active'] == true;
                final status = (data['status'] ?? '').toString().toLowerCase();

                final visible = !declinedBy.contains(uid);
                final alertable = active &&
                    (status == 'pending' || status == 'scheduled');

                debugPrint(
                  'BELL DOC ${d.id} => active=$active status=$status declinedBy=$declinedBy visible=$visible alertable=$alertable',
                );

                return visible && alertable;
              }).toList();

              final hasAvailablePickup = visiblePickupDocs.isNotEmpty;
              final hasAlert = hasUnread || hasAvailablePickup;

              debugPrint(
                'BELL => unread=$hasUnread, aDocs=${aSnap.data?.docs.length ?? 0}, bDocs=${bSnap.data?.docs.length ?? 0}, visiblePickupDocs=${visiblePickupDocs.length}, hasAlert=$hasAlert',
              );

              return InkWell(
                onTap: () async {
                  if (!context.mounted) return;
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CollectorNotificationsPage(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withOpacity(0.10)),
                        color: Colors.white.withOpacity(0.04),
                      ),
                      child: Icon(
                        Icons.notifications_none_rounded,
                        color: hasAlert ? Colors.amber : Colors.white70,
                        size: 28,
                      ),
                    ),
                    if (hasAlert)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: bgColor,
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
=======
        // ✅ keep updated on refresh
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

            // ✅ Logout
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

    // ✅ UPDATED: Admin-approved collectors can enter dashboard immediately
    // New separated logic:
    // - allow if Roles == collector AND collectorStatus == "adminApproved"
    // - legacy fallback remains
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
        // should not normally show if allowDashboard is correct
        title = "Admin approved";
        body = "You may now access the Collector Dashboard.";
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
>>>>>>> b0c204e (di pa tapos)
        ),
      );
    }

<<<<<<< HEAD
    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance.collection('Users').doc(user.uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: bgColor,
            body: Center(child: CircularProgressIndicator()),
          );
        }
=======
    bool _isCollectorRole(Map<String, dynamic>? data) {
      final rolesRaw =
          (data?['Roles'] ?? data?['role'] ?? "").toString().trim().toLowerCase();
      return rolesRaw == "collector" || rolesRaw == "collectors";
    }
>>>>>>> b0c204e (di pa tapos)

    // ✅ NEW FLOW: allow entry once admin approved (no junkshop needed)
    bool _isCollectorAdminApproved(Map<String, dynamic>? data) {
      final s = (data?['collectorStatus'] ?? "").toString().trim().toLowerCase();
      return s == "adminapproved";
    }

    // ✅ legacy fallback (keep)
    bool _isLegacyCollectorVerified(Map<String, dynamic>? data) {
      final legacyAdminOk = data?['adminVerified'] == true;
      final legacyAdminStatus = (data?['adminStatus'] ?? "").toString().toLowerCase();
      final legacyJunkshopOk = data?['junkshopVerified'] == true;
      final legacyActive = data?['collectorActive'] == true;
      return legacyAdminOk && legacyAdminStatus == "approved" && legacyJunkshopOk && legacyActive;
    } 

    Widget _buildCollectorNotifBell() {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      // fallback bell (shouldn't happen if dashboard requires login)
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
<<<<<<< HEAD
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
            onAcceptPickup: _acceptPickup,
            onOpenOrders: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _CollectorMapTab(
                    collectorId: user.uid,
                    onAcceptPickup: _acceptPickup,
                    onDeclinePickup: _declinePickup,
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
=======
            child: Icon(Icons.notifications_outlined, color: Colors.grey.shade300),
>>>>>>> b0c204e (di pa tapos)
          ),
        );
      }

<<<<<<< HEAD
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
          BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded), label: "HOME"),
          BottomNavigationBarItem(
              icon: Icon(Icons.forum_outlined), label: "CHATS"),
          BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long), label: "TRANSACTION"),
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
    required this.onAcceptPickup,
    required this.onOpenOrders,
  });

  final Widget notifBell;
  final String collectorId;
  final VoidCallback onOpenProfile;
  final Future<void> Function(String requestId) onAcceptPickup;
  final VoidCallback onOpenOrders;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
=======
      final userDocStream =
          FirebaseFirestore.instance.collection('Users').doc(uid).snapshots();

      // ✅ Orders that are NOT yet assigned to any collector
      final unassignedQuery = FirebaseFirestore.instance
          .collection('requests')
          .where('type', isEqualTo: 'pickup')
          .where('status', whereIn: ['pending', 'scheduled'])
          .orderBy('updatedAt', descending: true)
          .limit(1);

      // ✅ Orders already assigned to me (optional, but useful)
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
            // mark as seen BEFORE opening notifications
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
>>>>>>> b0c204e (di pa tapos)
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
<<<<<<< HEAD
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
                      style:
                          TextStyle(color: Colors.grey.shade400, fontSize: 12),
=======
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
>>>>>>> b0c204e (di pa tapos)
                    ),
                  ),
                ),
<<<<<<< HEAD
              ),
              notifBell,
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
=======
            ],
          ),
        );
      }

      Timestamp? _pickTs(QuerySnapshot? qs) {
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
                  final a = _pickTs(unassignedSnap.data);
                  final b = _pickTs(mineSnap.data);

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
                      hasUnread = newestTs!.toDate().isAfter(lastSeen.toDate());
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

          // NEW FLOW checks
          final isCollectorRole = _isCollectorRole(data);
          final collectorStatus = (data?['collectorStatus'] ?? "").toString();

          // LEGACY checks
          final legacyAdminOk = data?['adminVerified'] == true;
          final legacyJunkshopOk = data?['junkshopVerified'] == true;
          final legacyActive = data?['collectorActive'] == true;

          // ✅ IMPORTANT: allow dashboard when adminApproved (no junkshop needed)
          final allowDashboard =
              (isCollectorRole && _isCollectorAdminApproved(data)) || _isLegacyCollectorVerified(data);

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

          // ✅ 3 bottom tabs (NOTIFS is now a RIGHT drawer)
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

            // ✅ Transactions TAB (your merged buy/sell page)
            const CollectorTransactionPage(embedded: true),
  ];

          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: bgColor,

            // ✅ LEFT DRAWER = PROFILE
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

                // ✅ MUST be inside children list
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
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: "TRANSACTION"),
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
  }

  // ===================== HOME TAB =====================
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

    @override
    Widget build(BuildContext context) {
      final user = FirebaseAuth.instance.currentUser;

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 90), // leave space for footer
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Header: profile left, bell right (like household/admin)
            Row(
              children: [
                GestureDetector(
                  onTap: onOpenProfile,
                  child: Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1FA9A7), Colors.green],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person, color: Colors.white),
>>>>>>> b0c204e (di pa tapos)
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
<<<<<<< HEAD
                        "Community + Environment",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
=======
                        "Collector Dashboard",
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
>>>>>>> b0c204e (di pa tapos)
                      ),
                      Text(
<<<<<<< HEAD
                        "Every pickup helps the community, supports junkshops, and reduces pollution.",
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.35),
=======
                        user?.displayName ?? "Collector",
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
>>>>>>> b0c204e (di pa tapos)
                      ),
                    ],
                  ),
                ),

                // ✅ uniform bell widget from parent
                notifBell,
              ],
            ),
<<<<<<< HEAD
          ),
          const SizedBox(height: 14),
          const Text(
            "Logs",
            style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          _CollectorLogsHome(
            collectorId: collectorId,
            onAcceptPickup: onAcceptPickup,
          ),
        ],
      ),
    );
  }
=======

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
                          style:
                              TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "Every pickup helps the community, supports junkshops, and reduces pollution.",
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onOpenOrders,
                icon: const Icon(Icons.route_outlined),
                label: const Text("VIEW ACTIVE PICKUPS"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1FA9A7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
>>>>>>> b0c204e (di pa tapos)

            const Text(
              "Logs",
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

<<<<<<< HEAD
class _CollectorMapTab extends StatelessWidget {
  const _CollectorMapTab({
    required this.collectorId,
    required this.onAcceptPickup,
    required this.onDeclinePickup,
  });

  final String collectorId;
  final Future<void> Function(String requestId) onAcceptPickup;
  final Future<void> Function(String requestId, {required String reason}) onDeclinePickup;

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
=======
            _CollectorLogsHome(
              collectorId: collectorId,
            ),
          ],
        ),
      );
>>>>>>> b0c204e (di pa tapos)
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

<<<<<<< HEAD
  @override
  Widget build(BuildContext context) {
    final resumeQuery = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('collectorId', isEqualTo: collectorId)
        .where('status', whereIn: ['pending', 'scheduled'])
        .orderBy('updatedAt', descending: true)
        .limit(1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Orders",
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
            stream: resumeQuery.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
=======
  // ===================== MAP TAB =====================
  class _CollectorMapTab extends StatelessWidget {
    const _CollectorMapTab({
      required this.collectorId,
    });

    final String collectorId;

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

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Orders",
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: activeQueueQuery.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
>>>>>>> b0c204e (di pa tapos)

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _emptyCard(
                    title: "No active pickups",
                    body: "Accepted pickups will appear here.",
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Active pickups (${docs.length}/5)",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    for (final doc in docs) ...[
                      _pickupQueueCard(context, doc),
                      const SizedBox(height: 10),
                    ],

                    const SizedBox(height: 12),

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
                        label: const Text("OPEN ROUTE MAP"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1FA9A7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      );
    }

    Widget _pickupQueueCard(BuildContext context, QueryDocumentSnapshot doc) {
      final data = doc.data() as Map<String, dynamic>;

      final status = (data['status'] ?? '').toString().toLowerCase();
      final name = (data['householdName'] ?? 'Household').toString();
      final address = (data['pickupAddress'] ?? '').toString();
      final queueNumber = data['queueNumber'];

      final bagLabel = (data['bagLabel'] ?? '').toString();
      final bagKgNum = (data['bagKg'] is num) ? (data['bagKg'] as num).toDouble() : null;
      final etaMinutes = (data['etaMinutes'] is num) ? (data['etaMinutes'] as num).toInt() : null;
      final pickupTimeText = _formatPickupSchedule(data);

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                    color: Colors.green.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.navigation_rounded, color: Colors.green),
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
                        style: TextStyle(
                          color: Colors.grey.shade300,
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
            const SizedBox(height: 10),
            if (address.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.place_outlined, size: 16, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metaChip(Icons.access_time_rounded, "Pickup: $pickupTimeText"),
                if (bagLabel.isNotEmpty)
                  _metaChip(
                    Icons.shopping_bag_outlined,
                    "Bag: $bagLabel${bagKgNum != null ? " • ${bagKgNum.toStringAsFixed(1)} kg" : ""}",
                  ),
                if (etaMinutes != null)
                  _metaChip(Icons.timer_outlined, "ETA: $etaMinutes min"),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: _pillButton(
                label: "OPEN",
                isPrimary: true,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CollectorPickupMapPage(
                        requestIds: [doc.id],
                      ),
                    ),
                  );
                },
              ),
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
    Widget _metaChip(IconData icon, String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.20),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    Widget _statusChip(String status) {
      final s = status.toLowerCase();

      String label = s.isEmpty ? "UNKNOWN" : s.toUpperCase();
      IconData icon = Icons.info_outline;
      Color bg = Colors.white.withOpacity(0.10);
      Color fg = Colors.white70;

      if (s == "pending" || s == "scheduled") {
        label = "PENDING";
        icon = Icons.schedule_rounded;
        bg = Colors.amber.withOpacity(0.15);
        fg = Colors.amberAccent;
      } else if (s == "accepted") {
        label = "ACCEPTED";
        icon = Icons.check_circle_outline;
        bg = Colors.lightBlue.withOpacity(0.16);
        fg = Colors.lightBlueAccent;
      } else if (s == "arrived") {
        label = "ARRIVED";
        icon = Icons.near_me_outlined;
        bg = Colors.green.withOpacity(0.15);
        fg = Colors.greenAccent;
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      );
    }

    Widget _pillButton({
      required String label,
      required bool isPrimary,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        height: 44,
        child: isPrimary
            ? ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1FA9A7),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              )
            : OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withOpacity(0.18)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
      );
    }
  }

  // ================= LOGS HOME (unchanged) =================
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

<<<<<<< HEAD
              final bagLabel = (data['bagLabel'] ?? '').toString();
              final bagKgNum =
                  (data['bagKg'] is num) ? (data['bagKg'] as num).toDouble() : null;

              final etaMinutes = (data['etaMinutes'] is num)
                  ? (data['etaMinutes'] as num).toInt()
                  : null;

              final pickupTimeText = _formatPickupSchedule(data);
              final isAcceptable = status == 'pending' || status == 'scheduled';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
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
                            color: Colors.green.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.navigation_rounded,
                              color: Colors.green),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Current pickup",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
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
                                style: TextStyle(
                                  color: Colors.grey.shade300,
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
                    const SizedBox(height: 10),
                    if (address.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.place_outlined,
                              size: 16, color: Colors.grey.shade400),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _metaChip(
                            Icons.access_time_rounded, "Pickup: $pickupTimeText"),
                        if (bagLabel.isNotEmpty)
                          _metaChip(
                            Icons.shopping_bag_outlined,
                            "Bag: $bagLabel${bagKgNum != null ? " • ${bagKgNum.toStringAsFixed(1)} kg" : ""}",
                          ),
                        if (etaMinutes != null)
                          _metaChip(Icons.timer_outlined, "ETA: $etaMinutes min"),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (isAcceptable) ...[
                          Expanded(
                            child: _pillButton(
                              label: "DECLINE",
                              isPrimary: false,
                              onTap: () async => await onDeclinePickup(
                                doc.id,
                                reason: "Collector declined the pickup",
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _pillButton(
                              label: "ACCEPT",
                              isPrimary: true,
                              onTap: () async => await onAcceptPickup(doc.id),
                            ),
                          ),
                        ] else ...[
                          Expanded(
                            child: _pillButton(
                              label: "OPEN",
                              isPrimary: true,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CollectorPickupMapPage(requestId: doc.id),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
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
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, height: 1.35)),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final s = status.toLowerCase();

    String label = s.isEmpty ? "UNKNOWN" : s.toUpperCase();
    IconData icon = Icons.info_outline;
    Color bg = Colors.white.withOpacity(0.10);
    Color fg = Colors.white70;

    if (s == "pending" || s == "scheduled") {
      label = "PENDING";
      icon = Icons.schedule_rounded;
      bg = Colors.amber.withOpacity(0.15);
      fg = Colors.amberAccent;
    } else if (s == "accepted") {
      label = "ACCEPTED";
      icon = Icons.check_circle_outline;
      bg = Colors.lightBlue.withOpacity(0.16);
      fg = Colors.lightBlueAccent;
    } else if (s == "arrived") {
      label = "ARRIVED";
      icon = Icons.near_me_outlined;
      bg = Colors.green.withOpacity(0.15);
      fg = Colors.greenAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pillButton({
    required String label,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 44,
      child: isPrimary
          ? ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1FA9A7),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.18)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
    );
  }
}

class _CollectorLogsHome extends StatelessWidget {
  const _CollectorLogsHome({
    required this.collectorId,
    required this.onAcceptPickup,
  });

  final String collectorId;
  final Future<void> Function(String requestId) onAcceptPickup;

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
        .where('status', whereIn: ['pending', 'accepted', 'arrived', 'scheduled'])
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
                child: Text("No logs yet.",
                    style: TextStyle(color: Colors.white70)),
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
                          const Icon(Icons.play_arrow_rounded,
                              color: Colors.green),
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
                                  style: TextStyle(
                                      color: Colors.grey.shade300, fontSize: 12),
                                ),
                                if (address.isNotEmpty)
                                  Text(
                                    address,
                                    style: TextStyle(
                                        color: Colors.grey.shade400, fontSize: 11),
                                  ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      CollectorPickupMapPage(requestId: doc.id),
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
                    child: Text("No active pickups.",
                        style: TextStyle(color: Colors.white54)),
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
                  const Text("No history yet.",
                      style: TextStyle(color: Colors.white54))
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

  static Timestamp? _pickBestTimestamp(
      Map<String, dynamic> data, String status) {
    Timestamp? t(dynamic v) => v is Timestamp ? v : null;

    if (status == 'accepted') {
      return t(data['acceptedAt']) ?? t(data['updatedAt']) ?? t(data['createdAt']);
    }
    if (status == 'completed') {
      return t(data['completedAt']) ?? t(data['updatedAt']) ?? t(data['createdAt']);
    }
    if (status == 'transferred') {
      return t(data['transferredAt']) ??
          t(data['updatedAt']) ??
          t(data['createdAt']);
    }
    return t(data['updatedAt']) ?? t(data['createdAt']);
  }

  static String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return "—";
    final dt = ts.toDate();
    final now = DateTime.now();

    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
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
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
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
=======
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
                                  final status = (data['status'] ?? '').toString().toLowerCase();
                                  final name = (data['householdName'] ?? 'Household').toString();
                                  final address = (data['pickupAddress'] ?? '').toString();

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
                                        const Icon(Icons.place_outlined, color: Colors.greenAccent),
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

>>>>>>> b0c204e (di pa tapos)

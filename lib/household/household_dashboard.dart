import 'dart:async';
import 'dart:ui';

import '../waiting_collector_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../geomapping.dart';
import '../image_detection.dart';
import 'household_order_page.dart';
import '../auth/CollectorAccountCreation.dart';
import '../services/notification_service.dart';
import 'package:ecoscrap_app/chat/screens/chat_list_page.dart';

class DashboardPage extends StatefulWidget {
  final int initialTabIndex;

  const DashboardPage({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _activeTabIndex;

  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  // ===== TOP SLIDER STATE =====
  final PageController _promoController = PageController();
  int _promoIndex = 0;
  Timer? _promoTimer;

  // ===== FIXED MISSING FIELDS =====
  StreamSubscription<QuerySnapshot>? _acceptedRequestSub;
  bool _autoOpenedOrderForActiveRequest = false;

  // (kept)
  bool _cameraBarOpen = false;

  // ================= TAB SCREENS =================
  List<Widget> get _tabScreens => [
        _householdHome(),
        _historyScreen(),
        const HouseholdOrderPage(),
        const ChatListPage(type: "pickup", title: "Chats"),
      ];

  @override
  void initState() {
    super.initState();

    _activeTabIndex = widget.initialTabIndex;

    NotificationService.init();
    _listenForAcceptedPickup();
    _ensureNotificationBaseline();

    _promoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_promoController.hasClients) return;
      final next = (_promoIndex + 1) % 3;
      _promoController.animateToPage(
        next,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  Stream<QuerySnapshot> _activePendingRequestStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Stream<QuerySnapshot>.empty();
    }

    return FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('householdId', isEqualTo: user.uid)
        .where('active', isEqualTo: true)
        .where('status', whereIn: ['pending', 'scheduled'])
        .limit(1)
        .snapshots();
  }

  Widget _waitingCollectorBanner() {
    return StreamBuilder<QuerySnapshot>(
      stream: _activePendingRequestStream(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final doc = snap.data!.docs.first;
        final data = doc.data() as Map<String, dynamic>;

        final pickupGeo = data['pickupLocation'] as GeoPoint?;
        final destGeo = data['destinationLocation'] as GeoPoint?;

        if (pickupGeo == null || destGeo == null) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WaitingCollectorPage(
                      requestId: doc.id,
                      pickupLatLng: LatLng(
                        pickupGeo.latitude,
                        pickupGeo.longitude,
                      ),
                      destinationLatLng: LatLng(
                        destGeo.latitude,
                        destGeo.longitude,
                      ),
                    ),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: primaryColor.withOpacity(0.28),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        "Waiting for collector",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _swipeHint({
    String? label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chevron_left,
              size: 18, color: Colors.white.withOpacity(0.65)),
          const SizedBox(width: 2),
          Icon(Icons.swipe, size: 18, color: Colors.white.withOpacity(0.85)),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right,
              size: 18, color: Colors.white.withOpacity(0.65)),
          if (label != null) ...[
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _promoTimer?.cancel();
    _promoController.dispose();
    _acceptedRequestSub?.cancel();
    super.dispose();
  }

  void _listenForAcceptedPickup() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _acceptedRequestSub = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('householdId', isEqualTo: user.uid)
        .where('active', isEqualTo: true)
        .limit(1)
        .snapshots()
        .listen((snap) {
      if (!mounted || snap.docs.isEmpty) return;

      final data = snap.docs.first.data() as Map<String, dynamic>;
      final status = (data['status'] ?? '').toString().trim().toLowerCase();

      final shouldOpenOrder = status == 'accepted' ||
          status == 'confirmed' ||
          status == 'ongoing' ||
          status == 'arrived';

      if (shouldOpenOrder) {
        if (_activeTabIndex != 2 || !_autoOpenedOrderForActiveRequest) {
          setState(() {
            _activeTabIndex = 2;
            _autoOpenedOrderForActiveRequest = true;
          });
        }
      } else if (status == 'pending' || status == 'scheduled') {
        _autoOpenedOrderForActiveRequest = false;
      }
    });
  }


  void _closeCameraBar() {
    if (_cameraBarOpen) setState(() => _cameraBarOpen = false);
  }

Future<void> _markNotificationsSeen() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
    'lastNotifSeenAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

  Future<void> _openPickupFlow() async {
    _closeCameraBar();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final query = await FirebaseFirestore.instance
          .collection('requests')
          .where('type', isEqualTo: 'pickup')
          .where('householdId', isEqualTo: user.uid)
          .where('active', isEqualTo: true)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final data = doc.data();

        final status = (data['status'] ?? '').toString().trim().toLowerCase();

        final isStillWaiting = status == 'pending' || status == 'scheduled';

        if (isStillWaiting) {
          final pickupGeo = data['pickupLocation'] as GeoPoint?;
          final destGeo = data['destinationLocation'] as GeoPoint?;

          if (pickupGeo != null && destGeo != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WaitingCollectorPage(
                  requestId: doc.id,
                  pickupLatLng: LatLng(
                    pickupGeo.latitude,
                    pickupGeo.longitude,
                  ),
                  destinationLatLng: LatLng(
                    destGeo.latitude,
                    destGeo.longitude,
                  ),
                ),
              ),
            );
            return;
          }
        }

        final hasActiveRequest = [
          'pending',
          'scheduled',
          'accepted',
          'confirmed',
          'ongoing',
          'arrived',
        ].contains(status);

        if (hasActiveRequest) {
          setState(() {
            _activeTabIndex = 2;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You already have an active pickup request.'),
            ),
          );
          return;
        }
      }

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GeoMappingPage()),
      );
    } catch (e) {
      debugPrint('Error opening pickup flow: $e');

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GeoMappingPage()),
      );
    }
  }

  Future<void> _ensureNotificationBaseline() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef = FirebaseFirestore.instance.collection('Users').doc(user.uid);
    final userDoc = await userRef.get();

    final data = userDoc.data();
    final hasLastSeen = data != null && data['lastNotifSeenAt'] != null;

    if (!hasLastSeen) {
      await userRef.set({
        'lastNotifSeenAt': Timestamp.now(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> _clearNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = Timestamp.now();

    await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
      'lastNotifSeenAt': now,
      'lastNotifClearedAt': now,
    }, SetOptions(merge: true));
  }

  Future<void> _markHouseholdNotificationRead(String notificationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || notificationId.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('userNotifications')
        .doc(user.uid)
        .collection('items')
        .doc(notificationId)
        .set({
      'status': 'read',
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  bool _isUserNotificationUnread(
    Map<String, dynamic> data,
    Timestamp? lastSeen,
  ) {
    final status = (data['status'] ?? 'unread').toString().toLowerCase();
    if (status == 'unread') return true;

    final createdAt = data['createdAt'] as Timestamp?;
    if (createdAt == null) return false;
    if (lastSeen == null) return true;
    return createdAt.toDate().isAfter(lastSeen.toDate());
  }

  Future<void> _openHouseholdNotification(
  BuildContext context, {
  required String notificationId,
  required Map<String, dynamic> data,
}) async {
  final title = (data['title'] ?? 'Notification').toString();
  final message = (data['message'] ?? '').toString();
  final reason = (data['reason'] ??
          data['collectorDeclineReason'] ??
          data['declineReason'] ??
          data['declinedReason'] ??
          '')
      .toString();
  final pickupAddress = (data['pickupAddress'] ?? '').toString();
  final type = (data['type'] ?? '').toString();

  await _markHouseholdNotificationRead(notificationId);

  if (!mounted) return;

  final normalizedTitle = title.trim().toLowerCase();
  final normalizedMessage = message.trim().toLowerCase();
  final isDeclineNotif = type == 'collector_declined_pickup' ||
      normalizedTitle == 'pickup declined' ||
      normalizedTitle == 'pickup request declined' ||
      normalizedMessage.contains('declined the pickup request') ||
      normalizedMessage.contains('declined your pickup request');

  if (isDeclineNotif) {
    await showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              if (reason.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Reason',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reason,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ],
              if (pickupAddress.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Pickup address',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  pickupAddress,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

  // ================= CAMERA =================
  Future<void> _openLens(BuildContext context) async {
    final proceed = await _showScanHowToSheet(context);
    if (!proceed) return;

    var status = await Permission.camera.status;
    if (status.isDenied) {
      status = await Permission.camera.request();
    }

    if (status.isGranted) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ImageDetectionPage()),
      );
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  Stream<int> _householdNotifCountStream(String householdUid) {
    return FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('householdId', isEqualTo: householdUid)
        .where('active', isEqualTo: true)
        .where('status',
            whereIn: ['accepted', 'arrived', 'completed', 'cancelled', 'canceled'])
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Widget _pickupNotificationTile(QueryDocumentSnapshot d) {
    final data = d.data() as Map<String, dynamic>;

    final status = (data['status'] ?? '').toString().toLowerCase();
    final driver = (data['collectorName'] ?? 'Driver').toString();

    String title;
    IconData icon;

    switch (status) {
      case 'accepted':
        title = "Pickup accepted • Driver: $driver";
        icon = Icons.thumb_up_alt_outlined;
        break;
      case 'arrived':
        title = "Driver arrived at pickup location";
        icon = Icons.location_on_outlined;
        break;
      case 'completed':
        title = "Pickup completed";
        icon = Icons.check_circle_outline;
        break;
      case 'cancelled':
      case 'canceled':
        title = "Pickup cancelled";
        icon = Icons.cancel_outlined;
        break;
      case 'scheduled':
        title = "Pickup scheduled";
        icon = Icons.event_available_outlined;
        break;
      default:
        title = "Pickup update";
        icon = Icons.receipt_long;
    }

    return _notificationTile(
      icon: icon,
      title: title,
      subtitle: "Tap Order tab to view details.",
    );
  }

  Future<bool> _showScanHowToSheet(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScanHowToSheet(
        primaryColor: primaryColor,
        bgColor: bgColor,
      ),
    );
    return result == true;
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        _closeCameraBar();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: bgColor,
        extendBody: true,
        drawer: Drawer(
          backgroundColor: bgColor,
          child: SafeArea(child: _profileDrawer()),
        ),
        endDrawer: Drawer(
          backgroundColor: bgColor,
          child: SafeArea(child: _notificationsDrawer()),
        ),
        body: Stack(
          children: [
            _blurCircle(
              primaryColor.withOpacity(0.14),
              320,
              top: -120,
              right: -120,
            ),
            _blurCircle(
              Colors.green.withOpacity(0.10),
              380,
              bottom: 110,
              left: -130,
            ),
            SafeArea(
              child: Column(
                children: [
                  _header(user),
                  _waitingCollectorBanner(),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: KeyedSubtree(
                        key: ValueKey(_activeTabIndex),
                        child: _tabScreens[_activeTabIndex],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SizedBox(
          height: 90,
          child: Container(
            height: 90,
            decoration: BoxDecoration(
              color: bgColor.withOpacity(0.86),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.08)),
              ),
            ),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _navItem(0, Icons.home_outlined, "Home"),
                      _navItem(1, Icons.history, "History"),
                      _navItem(2, Icons.receipt_long, "Order"),
                      _navItem(3, Icons.message_outlined, "Chat"),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotifBell() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return _iconButton(
        Icons.notifications_none_rounded,
        badge: false,
        onTap: () {
          _closeCameraBar();
          _scaffoldKey.currentState?.openEndDrawer();
        },
      );
    }

    final userDocStream =
        FirebaseFirestore.instance.collection('Users').doc(uid).snapshots();

    final requestQuery = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('householdId', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .limit(20);

    final notifQuery = FirebaseFirestore.instance
        .collection('userNotifications')
        .doc(uid)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .limit(20);

    return StreamBuilder<DocumentSnapshot>(
      stream: userDocStream,
      builder: (context, userSnap) {
        final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final lastSeen = userData['lastNotifSeenAt'] as Timestamp?;

        return StreamBuilder<QuerySnapshot>(
          stream: requestQuery.snapshots(),
          builder: (context, requestSnap) {
            final requestDocs = requestSnap.data?.docs ?? [];

            return StreamBuilder<QuerySnapshot>(
              stream: notifQuery.snapshots(),
              builder: (context, notifSnap) {
                final notifDocs = notifSnap.data?.docs ?? [];

                final hasRequestUnread = requestDocs.any((d) {
                  final data = d.data() as Map<String, dynamic>;
                  final updatedAt = data['updatedAt'] as Timestamp?;
                  if (updatedAt == null) return false;
                  if (lastSeen == null) return true;
                  return updatedAt.toDate().isAfter(lastSeen.toDate());
                });

                final hasUserNotifUnread = notifDocs.any((d) {
  final data = d.data() as Map<String, dynamic>;
  return _isUserNotificationUnread(data, lastSeen);
});

return _iconButton(
  Icons.notifications_none_rounded,
  badge: hasRequestUnread || hasUserNotifUnread,
  onTap: () {
    _closeCameraBar();
    _scaffoldKey.currentState?.openEndDrawer();
    Future.delayed(const Duration(milliseconds: 320), () async {
      if (!mounted) return;
      await _markNotificationsSeen();
    });
  },
);

                return _iconButton(
                  Icons.notifications_none_rounded,
                  badge: hasRequestUnread || hasUserNotifUnread,
                  onTap: () {
                    _closeCameraBar();
                    _scaffoldKey.currentState?.openEndDrawer();
                    Future.delayed(const Duration(milliseconds: 320), () async {
                      if (!mounted) return;
                      await _markNotificationsSeen();
                    });
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _iconButton(IconData icon,
      {bool badge = false, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
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
              icon,
              color: badge ? Colors.amber : Colors.white70,
              size: 28,
            ),
          ),
          if (badge)
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
  }

  Widget _blurCircle(
    Color color,
    double size, {
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  Widget _header(User? user) {
    final email = user?.email ?? 'Household';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () {
              _closeCameraBar();
              _scaffoldKey.currentState?.openDrawer();
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: const Icon(Icons.person_outline, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _buildNotifBell(),
        ],
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _activeTabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          _closeCameraBar();
          setState(() => _activeTabIndex = index);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? primaryColor : Colors.white70,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _householdHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _promoSection(),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _actionCard(
                  icon: Icons.local_shipping_outlined,
                  title: 'Request Pickup',
                  subtitle: 'Schedule or send a pickup request.',
                  gradientColors: const [Color(0xFF1FA9A7), Color(0xFF157C7B)],
                  onTap: _openPickupFlow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _actionCard(
                  icon: Icons.qr_code_scanner_outlined,
                  title: 'Scan Item',
                  subtitle: 'Validate plastics when you are unsure.',
                  gradientColors: const [Color(0xFF334155), Color(0xFF1E293B)],
                  onTap: () => _openLens(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _acceptedPlasticsSection(),
        ],
      ),
    );
  }

  Widget _promoSection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.recycling_outlined, color: primaryColor),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'EcoScrap Household',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Request a collector, track pickup updates, and validate plastic items before disposal.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _acceptedPlasticsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Accepted Plastics',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        _infoCard(
          icon: Icons.category_outlined,
          title: 'Colored Plastics',
          body: 'Hard plastic items with strong colors such as blue, green, or red.',
        ),
        const SizedBox(height: 10),
        _infoCard(
          icon: Icons.opacity_outlined,
          title: 'Transparent Plastics',
          body: 'Clear PET plastics like bottles and food containers.',
        ),
        const SizedBox(height: 10),
        _infoCard(
          icon: Icons.inventory_2_outlined,
          title: 'Thick Bottles & Containers',
          body: 'HDPE household bottles and containers with rigid walls.',
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> gradientColors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _historyScreen() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(
        child: Text('Not logged in.', style: TextStyle(color: Colors.white)),
      );
    }

    final query = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('householdId', isEqualTo: user.uid)
        .where('active', isEqualTo: false)
        .orderBy('updatedAt', descending: true)
        .limit(30);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text(
              'Error loading history: ${snap.error}',
              style: const TextStyle(color: Colors.white70),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text('No history yet.', style: TextStyle(color: Colors.white70)),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            final status = (data['status'] ?? '').toString().toLowerCase();
            final collectorName = (data['collectorName'] ?? '—').toString();
            final updatedAt = data['updatedAt'] as Timestamp?;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _historyCard(
                title: _pickupStatusToTitle(status),
                subtitle: 'Collector: $collectorName',
                rightText: _formatTimestamp(updatedAt),
                icon: _statusToIcon(status),
                iconBg: _statusToIconBg(status),
                iconColor: _statusToIconColor(status),
              ),
            );
          },
        );
      },
    );
  }

  Widget _historyCard({
    required String title,
    required String subtitle,
    required String rightText,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
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
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            rightText,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          ),
        ],
      ),
    );
  }

  IconData _statusToIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'accepted':
        return Icons.thumb_up_alt_outlined;
      case 'arrived':
        return Icons.location_on_outlined;
      case 'cancelled':
      case 'canceled':
      case 'declined':
        return Icons.cancel_outlined;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  Color _statusToIconBg(String status) {
    switch (status) {
      case 'completed':
        return Colors.green.withOpacity(0.16);
      case 'accepted':
      case 'arrived':
        return Colors.blue.withOpacity(0.16);
      case 'cancelled':
      case 'canceled':
      case 'declined':
        return Colors.red.withOpacity(0.16);
      default:
        return Colors.white.withOpacity(0.10);
    }
  }

  Color _statusToIconColor(String status) {
    switch (status) {
      case 'completed':
        return Colors.greenAccent;
      case 'accepted':
      case 'arrived':
        return Colors.lightBlueAccent;
      case 'cancelled':
      case 'canceled':
      case 'declined':
        return Colors.redAccent;
      default:
        return Colors.white70;
    }
  }

  Widget _notificationsDrawer() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    return const Center(
      child: Text('Not logged in', style: TextStyle(color: Colors.white)),
    );
  }

  final userDocStream =
      FirebaseFirestore.instance.collection('Users').doc(uid).snapshots();

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Notifications',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await _clearNotifications();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Notifications cleared")),
                );
              },
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text("Clear"),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<DocumentSnapshot>(
            stream: userDocStream,
            builder: (context, userSnap) {
              final userData =
                  userSnap.data?.data() as Map<String, dynamic>? ?? {};
              final lastCleared =
                  userData['lastNotifClearedAt'] as Timestamp?;

              final requestQuery = FirebaseFirestore.instance
                  .collection('requests')
                  .where('type', isEqualTo: 'pickup')
                  .where('householdId', isEqualTo: uid)
                  .orderBy('updatedAt', descending: true)
                  .limit(20);

              final notifQuery = FirebaseFirestore.instance
                  .collection('userNotifications')
                  .doc(uid)
                  .collection('items')
                  .orderBy('createdAt', descending: true)
                  .limit(20);

              return StreamBuilder<QuerySnapshot>(
                stream: requestQuery.snapshots(),
                builder: (context, requestSnap) {
                  if (requestSnap.hasError) {
                    return Center(
                      child: Text(
                        'Failed to load notifications: ${requestSnap.error}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    );
                  }

                  return StreamBuilder<QuerySnapshot>(
                    stream: notifQuery.snapshots(),
                    builder: (context, notifSnap) {
                      if (requestSnap.connectionState ==
                              ConnectionState.waiting ||
                          notifSnap.connectionState ==
                              ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (notifSnap.hasError) {
                        return Center(
                          child: Text(
                            'Failed to load notifications: ${notifSnap.error}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        );
                      }

                      final requestDocs = requestSnap.data?.docs ?? [];
                      final notifDocs = notifSnap.data?.docs ?? [];
                      final entries = <Map<String, dynamic>>[];

                      for (final d in requestDocs) {
                        final data = d.data() as Map<String, dynamic>;
                        final status =
                            (data['status'] ?? '').toString().toLowerCase();

                        // keep decline only from userNotifications
                        if (status == 'declined') {
                          continue;
                        }

                        final driver =
                            (data['collectorName'] ?? '—').toString();
                        final updatedAt = data['updatedAt'] as Timestamp?;
                        final unread = updatedAt != null &&
                            (lastSeen == null ||
                                updatedAt.toDate().isAfter(lastSeen.toDate()));

                        entries.add({
                          'title': _pickupStatusToTitle(status),
                          'subtitle': 'Driver: $driver',
                          'time': _formatTimestamp(updatedAt),
                          'unread': unread,
                          'sortAt': updatedAt,
                          'onTap': null,
                        });
                      }

                      final seenDeclineRequestIds = <String>{};

                      for (final d in notifDocs) {
                        final data = d.data() as Map<String, dynamic>;
                        final createdAt = data['createdAt'] as Timestamp?;
                        final type = (data['type'] ?? '').toString();
                        final title =
                            (data['title'] ?? '').toString().trim().toLowerCase();
                        final message =
                            (data['message'] ?? '').toString().trim().toLowerCase();
                        final requestId =
                            (data['requestId'] ?? '').toString().trim();

                        final reason = (data['reason'] ??
                                data['collectorDeclineReason'] ??
                                data['declineReason'] ??
                                data['declinedReason'] ??
                                '')
                            .toString()
                            .trim();

                        final isDeclineNotif =
                            type == 'collector_declined_pickup' ||
                                title == 'pickup declined' ||
                                title == 'pickup request declined' ||
                                message.contains('declined the pickup request') ||
                                message.contains('declined your pickup request');

                        // hide old empty decline notification
                        if (isDeclineNotif && reason.isEmpty) {
                          continue;
                        }

                        // keep only one decline notification per request
                        if (isDeclineNotif &&
                            requestId.isNotEmpty &&
                            seenDeclineRequestIds.contains(requestId)) {
                          continue;
                        }

                        if (isDeclineNotif && requestId.isNotEmpty) {
                          seenDeclineRequestIds.add(requestId);
                        }

                        entries.add({
                          'title': (data['title'] ?? 'Notification').toString(),
                          'subtitle': (data['message'] ?? '').toString(),
                          'time': _formatTimestamp(createdAt),
                          'unread': _isUserNotificationUnread(data, lastSeen),
                          'sortAt': createdAt,
                          'onTap': () => _openHouseholdNotification(
                                context,
                                notificationId: d.id,
                                data: data,
                              ),
                        });
                      }

                      entries.sort((a, b) {
                        final aTs = a['sortAt'] as Timestamp?;
                        final bTs = b['sortAt'] as Timestamp?;
                        if (aTs == null && bTs == null) return 0;
                        if (aTs == null) return 1;
                        if (bTs == null) return -1;
                        return bTs.compareTo(aTs);
                      });

                      if (entries.isEmpty) {
                        return const Center(
                          child: Text(
                            'No notifications yet.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final entry = entries[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _notificationLogTile(
                              title: entry['title'] as String,
                              subtitle: entry['subtitle'] as String,
                              time: entry['time'] as String,
                              unread: entry['unread'] as bool,
                              onTap: entry['onTap'] as VoidCallback?,
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
        ),
      ],
    ),
  );
}

  String _pickupStatusToTitle(String status) {
    switch (status) {
      case 'completed':
        return 'Pickup completed';
      case 'arrived':
        return 'Collector arrived';
      case 'accepted':
        return 'Pickup accepted';
      case 'scheduled':
        return 'Pickup scheduled';
      case 'pending':
        return 'Pickup request sent';
      case 'cancelled':
      case 'canceled':
        return 'Pickup cancelled';
      case 'declined':
        return 'Pickup declined';
      default:
        return status.isEmpty ? 'Pickup update' : 'Pickup $status';
    }
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate();
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = dt.year == yesterday.year &&
        dt.month == yesterday.month &&
        dt.day == yesterday.day;

    String two(int n) => n.toString().padLeft(2, '0');
    int hour = dt.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour:${two(dt.minute)} $ampm';

    if (sameDay) return 'Today • $time';
    if (isYesterday) return 'Yesterday • $time';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day} • $time';
  }

  Widget _notificationLogTile({
    required String title,
    required String subtitle,
    required String time,
    required bool unread,
    VoidCallback? onTap,
  }) {
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: unread ? primaryColor.withOpacity(0.06) : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unread ? primaryColor.withOpacity(0.18) : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSlide(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            offset: unread ? Offset.zero : const Offset(-0.25, 0),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: unread ? 1 : 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: unread ? 8 : 0,
                height: 8,
                margin: EdgeInsets.only(right: unread ? 10 : 0, top: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF1FA9A7),
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
                          color: Colors.white.withOpacity(unread ? 1 : 0.92),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      time,
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
                    color: Colors.white.withOpacity(unread ? 0.72 : 0.62),
                    fontSize: 13,
                  ),
                ),
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

  Widget _notificationTile({
    required IconData icon,
    required String title,
    required String subtitle,
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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileDrawer() {
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
                'Profile',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Icon(Icons.person, size: 80, color: Colors.white54),
          const SizedBox(height: 16),
          Text(
            user?.email ?? 'Household User',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 24),
          _howToUseCard(),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              children: [
                Icon(Icons.local_shipping_outlined, color: primaryColor, size: 32),
                const SizedBox(height: 12),
                const Text(
                  'Apply as Collector',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Create a collector account and submit requirements to start collecting.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CollectorAccountCreation(),
                        ),
                      );
                    },
                    child: const Text('Apply Now', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (!mounted) return;
                Navigator.pushReplacementNamed(context, '/login');
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _howToUseCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to use',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 12),
          _HowToRow(icon: Icons.notifications_outlined, text: 'Check updates and tips in Notifications.'),
          SizedBox(height: 10),
          _HowToRow(icon: Icons.local_shipping_outlined, text: 'Create a pickup request and wait for a collector.'),
          SizedBox(height: 10),
          _HowToRow(icon: Icons.qr_code_scanner_outlined, text: 'Use scan only when you need help validating an item.'),
        ],
      ),
    );
  }
}

class _HowToRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HowToRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF1FA9A7), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _ScanHowToSheet extends StatelessWidget {
  final Color primaryColor;
  final Color bgColor;

  const _ScanHowToSheet({
    required this.primaryColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: bgColor.withOpacity(0.95),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.info_outline, color: primaryColor),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "Use Scan for Validation",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close, color: Colors.white),
                )
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "Scan is only for validation when you're unsure about a plastic item. For best results:",
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
            const SizedBox(height: 14),
            _step(
              icon: Icons.wb_sunny_outlined,
              title: "Use good lighting",
              body:
                  "Clear lighting helps the scan validate the item more accurately.",
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 10),
            _step(
              icon: Icons.crop_free,
              title: "Focus on one item",
              body:
                  "Show one plastic item clearly inside the frame for validation.",
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 10),
            _step(
              icon: Icons.front_hand_outlined,
              title: "Hold steady",
              body:
                  "Keep your phone steady for 1–2 seconds before capturing the item.",
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 10),
            _step(
              icon: Icons.warning_amber_outlined,
              title: "Use only when unsure",
              body:
                  "If the item already matches the accepted examples, you do not need to scan it.",
              primaryColor: primaryColor,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.white.withOpacity(0.18)),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      "Validate Item",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _step({
    required IconData icon,
    required String title,
    required String body,
    required Color primaryColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
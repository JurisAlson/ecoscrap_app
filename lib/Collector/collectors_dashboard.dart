import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

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
  static const double maxCapacityKg = 20.0;

  static const List<String> declineReasons = [
    "Too far from my location",
    "Already handling another pickup",
    "Cannot complete right now",
    "Other",
  ];

  static const List<String> activePickupStatuses = [
    'accepted',
    'arrived',
    'scheduled',
    'ongoing'
  ];

  static const List<String> openPickupStatuses = [
    'pending',
    'scheduled',
  ];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _tabIndex = 0;

  StreamSubscription<Position>? _liveLocationSub;
  bool _isSendingLiveLocation = false;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _requestsRef =>
      _db.collection('requests');

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('Users').doc(uid);

  CollectionReference<Map<String, dynamic>> _userNotificationsRef(String uid) =>
      _db.collection('userNotifications').doc(uid).collection('items');

  Query<Map<String, dynamic>> _activeCollectorRequestsQuery(String collectorId) {
    return _requestsRef
        .where('type', isEqualTo: 'pickup')
        .where('collectorId', isEqualTo: collectorId)
        .where('active', isEqualTo: true)
        .where('status', whereIn: activePickupStatuses);
  }

  Query<Map<String, dynamic>> _openUnassignedRequestsQuery() {
    return _requestsRef
        .where('type', isEqualTo: 'pickup')
        .where('active', isEqualTo: true)
        .where('collectorId', isEqualTo: "")
        .where('status', whereIn: openPickupStatuses)
        .orderBy('updatedAt', descending: true);
  }


  Stream<QuerySnapshot<Map<String, dynamic>>> _ongoingCollectorPickupStream() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return const Stream.empty();
  }

  return _requestsRef
      .where('type', isEqualTo: 'pickup')
      .where('collectorId', isEqualTo: user.uid)
      .where('active', isEqualTo: true)
      .where('status', whereIn: activePickupStatuses)
      .limit(1)
      .snapshots();
}

  Query<Map<String, dynamic>> _openMineRequestsQuery(String collectorId) {
    return _requestsRef
        .where('type', isEqualTo: 'pickup')
        .where('collectorId', isEqualTo: collectorId)
        .where('active', isEqualTo: true)
        .where('status', whereIn: openPickupStatuses)
        .orderBy('updatedAt', descending: true);
  }

  String _pickupAddress(Map<String, dynamic> data, {String fallback = ''}) {
    return (data['fullAddress'] ?? data['pickupAddress'] ?? fallback)
        .toString();
  }

  String _phoneNumber(Map<String, dynamic> data) {
    return (data['phoneNumber'] ?? '').toString();
  }

  String _householdName(
    Map<String, dynamic> data, {
    String fallback = 'Household',
  }) {
    return (data['householdName'] ?? fallback).toString();
  }

  Timestamp? _asTimestamp(dynamic value) => value is Timestamp ? value : null;

  bool _isCancelledPickupNotification(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().toLowerCase();
    final title = (data['title'] ?? '').toString().toLowerCase();
    final message = (data['message'] ?? '').toString().toLowerCase();

    return type.contains('cancel') ||
        title.contains('cancel') ||
        message.contains('cancel');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnline(true);
    _saveFcmToken();
    _startDashboardLiveTracking();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setOnline(false);
    _stopDashboardLiveTracking(clearFirestore: true);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnline(true);
      _startDashboardLiveTracking();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _setOnline(false);
      _stopDashboardLiveTracking(clearFirestore: false);
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    var perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  Future<void> _startDashboardLiveTracking() async {
    debugPrint('DASHBOARD: _startDashboardLiveTracking called');

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_isSendingLiveLocation) return;

    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return;

    _isSendingLiveLocation = true;

    final firstPos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    // ALWAYS update collector location in Users
    await _updateCollectorUserLiveLocation(firstPos);

    // ONLY mirror into request docs if there are active assigned pickups
    final activeDocs = await _activeCollectorRequestsQuery(user.uid).get();
    if (activeDocs.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in activeDocs.docs) {
        batch.set(
          doc.reference,
          {
            'collectorLiveLocation': GeoPoint(
              firstPos.latitude,
              firstPos.longitude,
            ),
            'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
            'sharingLiveLocation': true,
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }

    await _liveLocationSub?.cancel();

    _liveLocationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((position) async {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // ALWAYS keep Users/{uid} updated
      await _updateCollectorUserLiveLocation(position);

      // ONLY update assigned active requests if any exist
      final activeNow = await _activeCollectorRequestsQuery(currentUser.uid).get();

      if (activeNow.docs.isNotEmpty) {
        final batch = _db.batch();
        for (final doc in activeNow.docs) {
          batch.set(
            doc.reference,
            {
              'collectorLiveLocation': GeoPoint(
                position.latitude,
                position.longitude,
              ),
              'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
              'sharingLiveLocation': true,
            },
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      }
    });
  }

  Future<void> _stopDashboardLiveTracking({bool clearFirestore = false}) async {
    final user = FirebaseAuth.instance.currentUser;

    await _liveLocationSub?.cancel();
    _liveLocationSub = null;
    _isSendingLiveLocation = false;

    if (user != null) {
      await _userRef(user.uid).set({
        'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (!clearFirestore || user == null) return;

    final activeDocs = await _activeCollectorRequestsQuery(user.uid).get();
    if (activeDocs.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in activeDocs.docs) {
      batch.set(
        doc.reference,
        {
          'sharingLiveLocation': false,
          'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> _updateCollectorUserLiveLocation(Position position) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('Users')
        .doc(user.uid)
        .set({
      'collectorLiveLocation': GeoPoint(
        position.latitude,
        position.longitude,
      ),
      'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
      'isOnline': true,
      'isAvailableForHousehold': true,
    }, SetOptions(merge: true));
  }

  double _getRequestKg(Map<String, dynamic> data) {
    final value = data['bagKg'];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  String _two(int n) => n.toString().padLeft(2, '0');

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
    if (type == 'now') return "Now";

    final startTs =
        _asTimestamp(data['windowStart']) ?? _asTimestamp(data['scheduledAt']);
    final endTs = _asTimestamp(data['windowEnd']);

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
Future<void> _handleLogoutPressed(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final activeDocs = await _activeCollectorRequestsQuery(user.uid).get();

  if (activeDocs.docs.isNotEmpty) {
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: bgColor,
        title: const Text(
          "Logout unavailable",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "You cannot log out while a pickup is ongoing. Please finish the current pickup first.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
    return;
  }

  Navigator.pop(context);
  await _logout(context);
}
  Future<void> _logout(BuildContext context) async {
    await _setOnline(false);
    await _stopDashboardLiveTracking(clearFirestore: true);
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _acceptPickup(String requestId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final requestRef = _requestsRef.doc(requestId);

    try {
      final activeDocs = await _activeCollectorRequestsQuery(user.uid).get();

      double currentActiveKg = 0.0;
      for (final doc in activeDocs.docs) {
        currentActiveKg += _getRequestKg(doc.data());
      }

      await _db.runTransaction((tx) async {
        final requestSnap = await tx.get(requestRef);
        if (!requestSnap.exists) {
          throw Exception("Request not found.");
        }

        final data = requestSnap.data() as Map<String, dynamic>;
        final status = (data['status'] ?? '').toString().toLowerCase();
        final collectorId = (data['collectorId'] ?? '').toString();
        final requestKg = _getRequestKg(data);

        if (!openPickupStatuses.contains(status)) {
          throw Exception("This pickup is no longer available.");
        }

        if (collectorId.isNotEmpty && collectorId != user.uid) {
          throw Exception(
            "This pickup was already accepted by another collector.",
          );
        }

        if ((currentActiveKg + requestKg) > maxCapacityKg) {
          throw Exception(
            "Capacity exceeded. "
            "Current load: ${currentActiveKg.toStringAsFixed(1)} kg, "
            "request: ${requestKg.toStringAsFixed(1)} kg, "
            "max: ${maxCapacityKg.toStringAsFixed(1)} kg.",
          );
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

      await _startDashboardLiveTracking();
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

    final ref = _requestsRef.doc(requestId);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw "Request not found";

        final data = snap.data() as Map<String, dynamic>;
        final householdId = (data['householdId'] ?? '').toString().trim();
        final collectorDoc =
    await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();

final collectorData = collectorDoc.data() ?? {};
final collectorName =
    (collectorData['Name'] ??
            collectorData['displayName'] ??
            user.displayName ??
            'Collector')
        .toString();
        
        final pickupAddress = _pickupAddress(data);

        tx.update(ref, {
          'status': 'declined',
          'active': false,
          'declinedBy': FieldValue.arrayUnion([user.uid]),
          'collectorDeclineReason': reason.trim(),
          'collectorDeclinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (householdId.isNotEmpty) {
          final notifRef = _userNotificationsRef(householdId).doc();

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

  Future<void> _clearAllCancelledPickupNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snap = await _userNotificationsRef(user.uid).get();
      final batch = _db.batch();

      for (final doc in snap.docs) {
        final data = doc.data();
        if (_isCancelledPickupNotification(data)) {
          batch.delete(doc.reference);
        }
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Cancelled pickup notifications cleared."),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to clear notifications: $e")),
      );
    }
  }

  Widget _ongoingPickupBanner() {
  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _ongoingCollectorPickupStream(),
    builder: (context, snap) {
      if (!snap.hasData || snap.data!.docs.isEmpty) {
        return const SizedBox.shrink();
      }

      final doc = snap.data!.docs.first;
      final data = doc.data();

      final household = _householdName(data);
      final address = _pickupAddress(data, fallback: 'Pickup location');
      final status = (data['status'] ?? '').toString().trim().toLowerCase();
      final scheduleText = _formatPickupSchedule(data);

      String title;
      if (status == 'ongoing') {
        title = "You have an ongoing pickup";
      } else if (status == 'arrived') {
        title = "You're at a pickup location";
      } else if (status == 'scheduled') {
        title = "Upcoming scheduled pickup";
      } else {
        title = "Active pickup in progress";
      }

      String subtitle;
      if (status == 'scheduled') {
        subtitle = "$household • $scheduleText";
      } else {
        subtitle = "$household • $address";
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              // ✅ Resume pickup → go to map
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CollectorPickupMapPage(
                    requestIds: [doc.id],
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: primaryColor.withOpacity(0.35),
                ),
              ),
              child: Row(
                children: [
                  // subtle status indicator
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // subtle arrow (optional but good UX hint)
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey.shade500,
                    size: 18,
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

  Future<void> markArrivedOnce(BuildContext context, String requestId) async {
    final requestRef =
        FirebaseFirestore.instance.collection('requests').doc(requestId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(requestRef);

        if (!snap.exists) {
          throw Exception("Request not found.");
        }

        final data = snap.data() as Map<String, dynamic>;
        final currentStatus = (data['status'] ?? '').toString().toLowerCase();

        if (currentStatus == 'arrived') {
          throw Exception("You have already arrived.");
        }

        if (currentStatus != 'accepted' && currentStatus != 'scheduled') {
          throw Exception("This pickup cannot be marked as arrived.");
        }

        tx.update(requestRef, {
          'status': 'arrived',
          'arrivedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You have arrived.")),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e")),
      );
    }
  }

  Future<void> _promptPickupAction({
    required BuildContext context,
    required String requestId,
    required Map<String, dynamic> data,
  }) async {
    final address = _pickupAddress(data, fallback: 'Unknown address');
    final household = _householdName(data);
    final bagLabel = (data['bagLabel'] ?? '').toString();
    final bagKgNum = _getRequestKg(data);
    final showBagKg = bagKgNum > 0;

    final distanceKm = (data['distanceKm'] is num)
        ? (data['distanceKm'] as num).toDouble()
        : null;
    final etaMinutes =
        (data['etaMinutes'] is num) ? (data['etaMinutes'] as num).toInt() : null;

    final scheduleText = _formatPickupSchedule(data);
    final source = (data['pickupSource'] ?? '').toString();
    final phoneNumber = _phoneNumber(data);

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Pickup Request"),
        content: SingleChildScrollView(
          child: Text(
            "Household: $household\n"
            "${phoneNumber.isNotEmpty ? "Mobile: $phoneNumber\n" : ""}"
            "Address: $address\n"
            "${bagLabel.isNotEmpty ? "Bag: $bagLabel${showBagKg ? " (${bagKgNum.toStringAsFixed(1)} kg)" : ""}\n" : ""}"
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
  

  Widget _notificationsDrawer() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Center(
        child: Text(
          "Not logged in",
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    final notifStream = _userNotificationsRef(user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();

    final unassignedQuery = _openUnassignedRequestsQuery();
    final mineQuery = _openMineRequestsQuery(user.uid);

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
                  "Notifications",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
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

                        pickupDocs.sort((x, y) {
                          final dx = x.data() as Map<String, dynamic>;
                          final dy = y.data() as Map<String, dynamic>;
                          final tx = _asTimestamp(dx['updatedAt']) ??
                              _asTimestamp(dx['createdAt']);
                          final ty = _asTimestamp(dy['updatedAt']) ??
                              _asTimestamp(dy['createdAt']);
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
                                final data = doc.data() as Map<String, dynamic>;

                                final household = _householdName(data);
                                final address = _pickupAddress(data);
                                final phoneNumber = _phoneNumber(data);

                                final bagLabel =
                                    (data['bagLabel'] ?? '').toString();
                                final bagKgValue = _getRequestKg(data);
                                final bagKg =
                                    bagKgValue > 0 ? bagKgValue.toInt() : null;

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
                                                    BorderRadius.circular(14),
                                              ),
                                              child: const Icon(
                                                Icons.local_shipping_outlined,
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
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    address.isEmpty
                                                        ? "No address"
                                                        : address,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade400,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  if (phoneNumber.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      "Mobile: $phoneNumber",
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color:
                                                            Colors.grey.shade300,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
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
                                                doc.id,
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: BorderSide(
                                                  color: Colors.white
                                                      .withOpacity(0.18),
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                              ),
                                              child: const Text(
                                                "DECLINE",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () =>
                                                  _acceptPickup(doc.id),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: primaryColor,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                              ),
                                              child: const Text(
                                                "ACCEPT",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900,
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
                                        color: Colors.white.withOpacity(0.10),
                                        thickness: 1,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Text(
                                        "NOTIFICATIONS",
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.55),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.1,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(
                                        color: Colors.white.withOpacity(0.10),
                                        thickness: 1,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        await _clearAllCancelledPickupNotifications();
                                      },
                                      child: const Text(
                                        "Clear",
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ...notifDocs.map((doc) {
                                final n = doc.data() as Map<String, dynamic>;

                                final title =
                                    (n['title'] ?? 'Notification').toString();
                                final message = (n['message'] ?? '').toString();
                                final reason = (n['reason'] ??
                                        n['collectorDeclineReason'] ??
                                        'No reason provided.')
                                    .toString();
                                final status =
                                    (n['status'] ?? 'unread').toString();
                                final createdAt = n['createdAt'] as Timestamp?;
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
                                    onTap: () async {
                                      await showDialog(
                                        context: context,
                                        builder: (dialogContext) => Dialog(
                                          backgroundColor: Colors.transparent,
                                          child: Container(
                                            padding: const EdgeInsets.all(20),
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
                                                mainAxisSize: MainAxisSize.min,
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
                                                  const SizedBox(height: 18),
                                                  Text(
                                                    message,
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 15,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 18),
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      const Text(
                                                        "Reason: ",
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Text(
                                                          reason,
                                                          style:
                                                              const TextStyle(
                                                            color: Colors.white70,
                                                            fontSize: 14,
                                                            height: 1.4,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 20),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              dialogContext),
                                                      child:
                                                          const Text("Close"),
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
        ],
      ),
    );
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

      await _userRef(user.uid).set({
        "fcmToken": token,
        "fcmUpdatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint("✅ FCM token saved for ${user.uid}: $token");

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        await _userRef(user.uid).set({
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
      await _userRef(user.uid).set({
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
  await _handleLogoutPressed(context);
},
              icon: const Icon(Icons.logout),
              label: const Text("Logout"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
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
  await _handleLogoutPressed(context);
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
        onTap: () {
          _scaffoldKey.currentState?.openEndDrawer();
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
            Icons.notifications_outlined,
            color: Colors.grey.shade300,
          ),
        ),
      );
    }

    final userDocStream = _userRef(uid).snapshots();

final unassignedQuery = _requestsRef
    .where('type', isEqualTo: 'pickup')
    .where('active', isEqualTo: true)
    .where('status', whereIn: openPickupStatuses)
    .orderBy('updatedAt', descending: true)
    .limit(1);

final mineQuery = _requestsRef
    .where('type', isEqualTo: 'pickup')
    .where('collectorId', isEqualTo: uid)
    .where('active', isEqualTo: true)
    .where('status', whereIn: openPickupStatuses)
    .orderBy('updatedAt', descending: true)
    .limit(1);

    Widget bell({required bool hasUnread}) {
      return InkWell(
        onTap: () async {
          await _userRef(uid).set({
            'lastNotifSeenAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          _scaffoldKey.currentState?.openEndDrawer();
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
                  color:
                      hasUnread ? Colors.amberAccent : Colors.grey.shade300,
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
          child: Text(
            "Not logged in.",
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: _userRef(user.uid).snapshots(),
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
  onOpenNotifications: () => _scaffoldKey.currentState?.openEndDrawer(),
  notifBell: _buildCollectorNotifBell(),
  onAcceptPickup: _acceptPickup,
  onDeclinePickup: _confirmAndDeclinePickup,
  formatPickupSchedule: _formatPickupSchedule,
  getRequestKg: _getRequestKg,
  pickupAddress: (data) => _pickupAddress(data),
  phoneNumber: _phoneNumber,
  householdName: (data) => _householdName(data),
  pillBuilder: _pill,
),
          const CollectorTransactionPage(embedded: true),
        ];

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: bgColor,
          drawer: Drawer(
            backgroundColor: bgColor,
            child: SafeArea(child: _collectorProfileDrawer(context)),
          ),
          endDrawer: Drawer(
            backgroundColor: bgColor,
            child: SafeArea(child: _notificationsDrawer()),
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
              SafeArea(
  child: Column(
    children: [
      if (_tabIndex == 0) _ongoingPickupBanner(),
      Expanded(
        child: pages[_tabIndex],
      ),
    ],
  ),
),
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
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
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
            icon: Icon(Icons.home_rounded),
            label: "HOME",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: "TRANSACTION",
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

class _CollectorHomeTab extends StatelessWidget {
  const _CollectorHomeTab({
    required this.collectorId,
    required this.onOpenProfile,
    required this.onOpenNotifications,
    required this.notifBell,
    required this.onAcceptPickup,
    required this.onDeclinePickup,
    required this.formatPickupSchedule,
    required this.getRequestKg,
    required this.pickupAddress,
    required this.phoneNumber,
    required this.householdName,
    required this.pillBuilder,
  });

  final Widget notifBell;
  final String collectorId;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenNotifications;

  final Future<void> Function(String requestId) onAcceptPickup;
  final Future<void> Function(String requestId) onDeclinePickup;

  final String Function(Map<String, dynamic>) formatPickupSchedule;
  final double Function(Map<String, dynamic>) getRequestKg;
  final String Function(Map<String, dynamic>) pickupAddress;
  final String Function(Map<String, dynamic>) phoneNumber;
  final String Function(Map<String, dynamic>) householdName;
  final Widget Function(String text) pillBuilder;

  static const Color primaryColor = Color(0xFF1FA9A7);
  static const Color cardColor = Color(0xFF1A2332);
  static const Color borderColor = Color(0xFF263244);
  static const Color textMuted = Color(0xFF94A3B8);

static const List<String> activePickupStatuses = [
  'accepted',
  'arrived',
  'scheduled',
  'ongoing',
];

  static const List<String> openPickupStatuses = [
    'pending',
    'scheduled',
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final activeQuery = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('collectorId', isEqualTo: collectorId)
        .where('active', isEqualTo: true)
        .where('status', whereIn: activePickupStatuses);

    final completedTodayQuery = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('collectorId', isEqualTo: collectorId)
        .where('status', isEqualTo: 'completed');

    final availableQuery = FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'pickup')
        .where('active', isEqualTo: true)
        .where('collectorId', isEqualTo: "")
        .where('status', whereIn: openPickupStatuses)
        .orderBy('updatedAt', descending: true)
        .limit(1);

    return StreamBuilder<QuerySnapshot>(
      stream: activeQuery.snapshots(),
      builder: (context, activeSnap) {
        final activeDocs = activeSnap.data?.docs ?? [];
        final activeCount = activeDocs.length;

        double activeKg = 0.0;
        for (final doc in activeDocs) {
          final data = doc.data() as Map<String, dynamic>;
          activeKg += getRequestKg(data);
        }

        final remainingKg = (20.0 - activeKg).clamp(0.0, 20.0);
        final activeRequestIds = activeDocs.map((d) => d.id).toList();

        void openActiveMap() {
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => CollectorPickupMapPage(
      requestIds: activeRequestIds,
    ),
  ),
);
        }

        return StreamBuilder<QuerySnapshot>(
          stream: completedTodayQuery.snapshots(),
          builder: (context, completedSnap) {
            final completedCount = completedSnap.data?.docs.length ?? 0;

            return StreamBuilder<QuerySnapshot>(
              stream: availableQuery.snapshots(),
              builder: (context, availableSnap) {
                final availableDocs = availableSnap.data?.docs ?? [];
                final availableDoc =
                    availableDocs.isNotEmpty ? availableDocs.first : null;
                final availableData =
                    availableDoc?.data() as Map<String, dynamic>?;

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 90),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                              child:
                                  const Icon(Icons.person, color: Colors.white),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        "Track your assigned pickups.",
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

                            if (activeCount > 0)
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
                                        "You currently have $activeCount active pickup${activeCount == 1 ? '' : 's'} with a total load of ${activeKg.toStringAsFixed(1)} kg.",
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.map_outlined,
                                      color: Colors.white54,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              )
                            else if (availableData != null)
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 42,
                                          height: 42,
                                          decoration: BoxDecoration(
                                            color:
                                                primaryColor.withOpacity(0.18),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          child: const Icon(
                                            Icons.local_shipping_outlined,
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
                                                householdName(availableData),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                pickupAddress(availableData)
                                                        .isEmpty
                                                    ? "No address"
                                                    : pickupAddress(
                                                        availableData),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.grey.shade400,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              if (phoneNumber(availableData)
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  "Mobile: ${phoneNumber(availableData)}",
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                        InkWell(
                                          onTap: onOpenNotifications,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.notifications_outlined,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        pillBuilder(
                                          "Schedule: ${formatPickupSchedule(availableData)}",
                                        ),
                                        if ((availableData['bagLabel'] ?? '')
                                            .toString()
                                            .isNotEmpty)
                                          pillBuilder(
                                            "Bag: ${(availableData['bagLabel'] ?? '').toString()}${getRequestKg(availableData) > 0 ? " • ${getRequestKg(availableData).toStringAsFixed(0)}kg" : ""}",
                                          ),
                                        if (availableData['distanceKm'] is num)
                                          pillBuilder(
                                            "Distance: ${((availableData['distanceKm'] as num).toDouble()).toStringAsFixed(2)} km",
                                          ),
                                        if (availableData['etaMinutes'] is num)
                                          pillBuilder(
                                            "ETA: ${(availableData['etaMinutes'] as num).toInt()} min",
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () => onDeclinePickup(
                                              availableDoc!.id,
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              side: BorderSide(
                                                color: Colors.white
                                                    .withOpacity(0.18),
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                            ),
                                            child: const Text(
                                              "DECLINE",
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: () => onAcceptPickup(
                                              availableDoc!.id,
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: primaryColor,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                            ),
                                            child: const Text(
                                              "ACCEPT",
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )
                            else
                              InkWell(
                                onTap: onOpenNotifications,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
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
                                      const Expanded(
                                        child: Text(
                                          "You have no accepted active pickups at the moment. Tap here to view available requests.",
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.notifications_outlined,
                                        color: Colors.white54,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      Row(
                        children: [
                          Expanded(
                            child: _summaryCard(
                              title: "Active",
                              value: "$activeCount",
                              icon: Icons.local_shipping_outlined,
                              onTap: openActiveMap,
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
                              title: "Remaining",
                              value: "${remainingKg.toStringAsFixed(1)} kg",
                              icon: Icons.layers_outlined,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: openActiveMap,
                          icon: const Icon(Icons.map_outlined),
                          label: Text(
                            activeRequestIds.isEmpty
                                ? "Open Pickup Map"
                                : "Open Active Pickups",
                          ),
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
                  ),
                );
              },
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
    VoidCallback? onTap,
  }) {
    final child = Container(
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

    if (onTap == null) return child;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: child,
    );
  }
}
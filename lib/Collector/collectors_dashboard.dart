import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'collector_pickup_map_page.dart';

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
    'Too far from my location',
    'Already handling another pickup',
    'Cannot complete right now',
    'Other',
  ];

  static const List<String> activePickupStatuses = [
    'accepted',
    'arrived',
    'ongoing',
  ];

  static const List<String> openPickupStatuses = [
    'pending',
    'scheduled',
  ];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  StreamSubscription<Position>? _liveLocationSub;
  bool _isSendingLiveLocation = false;

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  User? get _currentUser => FirebaseAuth.instance.currentUser;

  CollectionReference<Map<String, dynamic>> get _requestsRef =>
      _db.collection('requests');

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('Users').doc(uid);

  CollectionReference<Map<String, dynamic>> _userNotificationsRef(String uid) =>
      _db.collection('userNotifications').doc(uid).collection('items');

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

  Query<Map<String, dynamic>> _pickupRequestsQuery({
    String? collectorId,
    required bool active,
    List<String>? statuses,
    bool orderByUpdatedAt = false,
    bool? acceptedForLater,
    String? pickupType,
  }) {
    Query<Map<String, dynamic>> query = _requestsRef
        .where('type', isEqualTo: 'pickup')
        .where('active', isEqualTo: active);

    if (collectorId != null) {
      query = query.where('collectorId', isEqualTo: collectorId);
    }

    if (statuses != null && statuses.isNotEmpty) {
      if (statuses.length == 1) {
        query = query.where('status', isEqualTo: statuses.first);
      } else {
        query = query.where('status', whereIn: statuses);
      }
    }

    if (acceptedForLater != null) {
      query = query.where('acceptedForLater', isEqualTo: acceptedForLater);
    }

    if (pickupType != null) {
      query = query.where('pickupType', isEqualTo: pickupType);
    }

    if (orderByUpdatedAt) {
      query = query.orderBy('updatedAt', descending: true);
    }

    return query;
  }

  Query<Map<String, dynamic>> _activeCollectorRequestsQuery(String collectorId) {
    return _pickupRequestsQuery(
      collectorId: collectorId,
      active: true,
      statuses: activePickupStatuses,
    );
  }

  Query<Map<String, dynamic>> _openUnassignedRequestsQuery() {
    return _pickupRequestsQuery(
      collectorId: '',
      active: true,
      statuses: openPickupStatuses,
      orderByUpdatedAt: true,
    );
  }

  Query<Map<String, dynamic>> _openMineRequestsQuery(String collectorId) {
    return _pickupRequestsQuery(
      collectorId: collectorId,
      active: true,
      statuses: openPickupStatuses,
      orderByUpdatedAt: true,
    );
  }

  Query<Map<String, dynamic>> _scheduledAcceptedMineQuery(String collectorId) {
    return _pickupRequestsQuery(
      collectorId: collectorId,
      active: false,
      statuses: ['scheduled'],
      acceptedForLater: true,
      orderByUpdatedAt: true,
    );
  }

  Query<Map<String, dynamic>> _scheduledInboxQuery(String collectorId) {
    return _pickupRequestsQuery(
      collectorId: collectorId,
      active: false,
      statuses: ['scheduled'],
      acceptedForLater: false,
      pickupType: 'window',
      orderByUpdatedAt: true,
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _ongoingCollectorPickupStream() {
    final user = _currentUser;
    if (user == null) return const Stream.empty();

    return _activeCollectorRequestsQuery(user.uid).limit(1).snapshots();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _setOnline(true);
    await _saveFcmToken();
    await _activateReadyScheduledPickups();
    await _startDashboardLiveTracking();
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
    switch (state) {
      case AppLifecycleState.resumed:
        _setOnline(true);
        _activateReadyScheduledPickups();
        _startDashboardLiveTracking();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _setOnline(false);
        _stopDashboardLiveTracking(clearFirestore: false);
        break;
    }
  }

  String _pickupAddress(Map<String, dynamic> data, {String fallback = ''}) {
    return (data['fullAddress'] ?? data['pickupAddress'] ?? fallback).toString();
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

  double _getRequestKg(Map<String, dynamic> data) {
    final value = data['bagKg'];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  bool _isCancelledPickupNotification(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().toLowerCase();
    final title = (data['title'] ?? '').toString().toLowerCase();
    final message = (data['message'] ?? '').toString().toLowerCase();

    return type.contains('cancel') ||
        title.contains('cancel') ||
        message.contains('cancel');
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  String _formatNotifTime(Timestamp ts) {
    final dt = ts.toDate();
    final diff = DateTime.now().difference(dt);

    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';

    return '${dt.month}/${dt.day}';
  }

  String _formatPickupSchedule(Map<String, dynamic> data) {
    final pickupType = (data['pickupType'] ?? '').toString();
    if (pickupType == 'now') return 'Now';

    final startTs =
        _asTimestamp(data['windowStart']) ?? _asTimestamp(data['scheduledAt']);
    final endTs = _asTimestamp(data['windowEnd']);

    if (startTs == null) return 'Scheduled';

    String hm(DateTime d) {
      int hour = d.hour % 12;
      if (hour == 0) hour = 12;
      final amPm = d.hour >= 12 ? 'PM' : 'AM';
      return '$hour:${_two(d.minute)} $amPm';
    }

    final start = startTs.toDate();
    final date = '${start.year}-${_two(start.month)}-${_two(start.day)}';

    if (endTs == null) return '$date • ${hm(start)}';

    final end = endTs.toDate();
    return '$date • ${hm(start)}–${hm(end)}';
  }

  bool _isFutureScheduledPickup(Map<String, dynamic> data) {
    final pickupType = (data['pickupType'] ?? '').toString().toLowerCase();
    if (pickupType == 'now') return false;

    final startTs =
        _asTimestamp(data['windowStart']) ?? _asTimestamp(data['scheduledAt']);
    if (startTs == null) return false;

    return startTs.toDate().isAfter(DateTime.now());
  }

  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;
  }

  Future<void> _writeLiveLocationToRequests({
    required String collectorId,
    required Position position,
    required bool sharing,
  }) async {
    final activeDocs = await _activeCollectorRequestsQuery(collectorId).get();
    if (activeDocs.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in activeDocs.docs) {
      batch.set(
        doc.reference,
        {
          'collectorLiveLocation':
              sharing ? GeoPoint(position.latitude, position.longitude) : null,
          'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
          'sharingLiveLocation': sharing,
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> _updateCollectorUserLiveLocation(Position position) async {
    final user = _currentUser;
    if (user == null) return;

    await _userRef(user.uid).set(
      {
        'collectorLiveLocation': GeoPoint(position.latitude, position.longitude),
        'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
        'isOnline': true,
        'isAvailableForHousehold': true,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _startDashboardLiveTracking() async {
    final user = _currentUser;
    if (user == null || _isSendingLiveLocation) return;

    final hasPermission = await _ensureLocationPermission();
    _log('Location permission: $hasPermission');
    if (!hasPermission) return;

    _isSendingLiveLocation = true;

    final firstPosition = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    await _updateCollectorUserLiveLocation(firstPosition);
    await _writeLiveLocationToRequests(
      collectorId: user.uid,
      position: firstPosition,
      sharing: true,
    );

    await _liveLocationSub?.cancel();
    _liveLocationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((position) async {
      final currentUser = _currentUser;
      if (currentUser == null) return;

      await _updateCollectorUserLiveLocation(position);
      await _writeLiveLocationToRequests(
        collectorId: currentUser.uid,
        position: position,
        sharing: true,
      );
    });
  }

  Future<void> _stopDashboardLiveTracking({bool clearFirestore = false}) async {
    final user = _currentUser;

    await _liveLocationSub?.cancel();
    _liveLocationSub = null;
    _isSendingLiveLocation = false;

    if (user != null) {
      await _userRef(user.uid).set(
        {'collectorLiveUpdatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
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

  Future<void> _activateReadyScheduledPickups() async {
    final user = _currentUser;
    if (user == null) return;

    final snap = await _requestsRef
        .where('type', isEqualTo: 'pickup')
        .where('collectorId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'scheduled')
        .where('acceptedForLater', isEqualTo: true)
        .get();

    if (snap.docs.isEmpty) return;

    final now = DateTime.now();
    final batch = _db.batch();

    for (final doc in snap.docs) {
      final data = doc.data();
      final startTs =
          _asTimestamp(data['windowStart']) ?? _asTimestamp(data['scheduledAt']);

      if (startTs != null && !startTs.toDate().isAfter(now)) {
        batch.update(doc.reference, {
          'status': 'accepted',
          'active': true,
          'acceptedForLater': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();
  }

  Future<void> _setOnline(bool online) async {
    final user = _currentUser;
    if (user == null) return;

    try {
      await _userRef(user.uid).set(
        {
          'isOnline': online,
          'lastSeen': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      _log('setOnline failed: $e');
    }
  }

  Future<void> _saveFcmToken() async {
    final user = _currentUser;
    if (user == null) return;

    try {
      final fcm = FirebaseMessaging.instance;
      await fcm.requestPermission(alert: true, badge: true, sound: true);

      final token = await fcm.getToken();
      if (token == null || token.trim().isEmpty) return;

      await _userRef(user.uid).set(
        {
          'fcmToken': token,
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        await _userRef(user.uid).set(
          {
            'fcmToken': newToken,
            'fcmUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      _log('saveFcmToken failed: $e');
    }
  }

  Future<void> _logout(BuildContext context) async {
    await _setOnline(false);
    await _stopDashboardLiveTracking(clearFirestore: true);
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  Future<void> _handleLogoutPressed(BuildContext context) async {
    final user = _currentUser;
    if (user == null) return;

    final activeDocs = await _activeCollectorRequestsQuery(user.uid).get();
    if (activeDocs.docs.isNotEmpty) {
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: bgColor,
          title: const Text(
            'Logout unavailable',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'You cannot log out while a pickup is ongoing. Please finish the current pickup first.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    await _logout(context);
  }

  Future<void> _acceptPickup(String requestId) async {
    final user = _currentUser;
    if (user == null) return;

    final requestRef = _requestsRef.doc(requestId);

    try {
      final activeDocs = await _activeCollectorRequestsQuery(user.uid).get();
      final currentActiveKg = activeDocs.docs.fold<double>(
        0,
        (sum, doc) => sum + _getRequestKg(doc.data()),
      );

      bool acceptedForLater = false;

      await _db.runTransaction((tx) async {
        final requestSnap = await tx.get(requestRef);
        if (!requestSnap.exists) {
          throw Exception('Request not found.');
        }

        final data = requestSnap.data() as Map<String, dynamic>;
        final status = (data['status'] ?? '').toString().toLowerCase();
        final collectorId = (data['collectorId'] ?? '').toString();
        final requestKg = _getRequestKg(data);

        if (!openPickupStatuses.contains(status)) {
          throw Exception('This pickup is no longer available.');
        }

        if (collectorId.isNotEmpty && collectorId != user.uid) {
          throw Exception('This pickup was already accepted by another collector.');
        }

        if ((currentActiveKg + requestKg) > maxCapacityKg) {
          await _userNotificationsRef(user.uid).add({
            'type': 'capacity_full',
            'title': 'Capacity Full',
            'message':
                'You cannot accept this pickup because your current load is '
                '${currentActiveKg.toStringAsFixed(1)} kg out of '
                '${maxCapacityKg.toStringAsFixed(1)} kg.',
            'status': 'unread',
            'createdAt': FieldValue.serverTimestamp(),
          });

          throw Exception(
            'Capacity exceeded. '
            'Current load: ${currentActiveKg.toStringAsFixed(1)} kg, '
            'request: ${requestKg.toStringAsFixed(1)} kg, '
            'max: ${maxCapacityKg.toStringAsFixed(1)} kg.',
          );
        }

        acceptedForLater = _isFutureScheduledPickup(data);

        tx.update(requestRef, {
          'status': acceptedForLater ? 'scheduled' : 'accepted',
          'active': !acceptedForLater,
          'collectorId': user.uid,
          'acceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'acceptedForLater': acceptedForLater,
          'queueNumber': acceptedForLater ? null : activeDocs.docs.length + 1,
        });
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            acceptedForLater
                ? 'Scheduled pickup accepted. It will become active at the scheduled time.'
                : 'Pickup accepted.',
          ),
        ),
      );

      await _startDashboardLiveTracking();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Accept failed: $e')),
      );
    }
  }

  Future<void> _declinePickup(
    String requestId, {
    required String reason,
  }) async {
    final user = _currentUser;
    if (user == null) return;

    final ref = _requestsRef.doc(requestId);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) throw Exception('Request not found');

        final data = snap.data() as Map<String, dynamic>;
        final householdId = (data['householdId'] ?? '').toString().trim();

        final collectorDoc = await _userRef(user.uid).get();
        final collectorData = collectorDoc.data() ?? {};
        final collectorName = (collectorData['Name'] ??
                collectorData['displayName'] ??
                user.displayName ??
                'Collector')
            .toString();

        tx.update(ref, {
          'status': 'declined',
          'active': false,
          'declinedBy': FieldValue.arrayUnion([user.uid]),
          'collectorDeclineReason': reason.trim(),
          'collectorDeclinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (householdId.isNotEmpty) {
          tx.set(_userNotificationsRef(householdId).doc(), {
            'type': 'collector_declined_pickup',
            'title': 'Pickup declined',
            'message': '$collectorName declined the pickup request.',
            'reason': reason.trim(),
            'requestId': requestId,
            'pickupAddress': _pickupAddress(data),
            'status': 'unread',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pickup declined.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Decline failed: $e')),
      );
    }
  }

  Future<String?> _pickDeclineReason() async {
    String selectedReason = declineReasons.first;

    return showDialog<String>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            return AlertDialog(
              backgroundColor: bgColor,
              title: const Text(
                'Select reason',
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
                    setStateDialog(() => selectedReason = value);
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, selectedReason),
                  child: const Text(
                    'Submit',
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
          'Decline request?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to decline this pickup request?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'No',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Yes',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final reason = await _pickDeclineReason();
    if (reason == null || reason.trim().isEmpty) return;

    await _declinePickup(requestId, reason: reason);
  }

  Future<void> _clearAllCancelledPickupNotifications() async {
    final user = _currentUser;
    if (user == null) return;

    try {
      final snap = await _userNotificationsRef(user.uid).get();
      final batch = _db.batch();

      for (final doc in snap.docs) {
        if (_isCancelledPickupNotification(doc.data())) {
          batch.delete(doc.reference);
        }
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cancelled pickup notifications cleared.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clear notifications: $e')),
      );
    }
  }

  Future<void> markArrivedOnce(BuildContext context, String requestId) async {
    final requestRef = _requestsRef.doc(requestId);

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(requestRef);
        if (!snap.exists) {
          throw Exception('Request not found.');
        }

        final data = snap.data() as Map<String, dynamic>;
        final currentStatus = (data['status'] ?? '').toString().toLowerCase();

        if (currentStatus == 'arrived') {
          throw Exception('You have already arrived.');
        }

        if (currentStatus != 'accepted' && currentStatus != 'scheduled') {
          throw Exception('This pickup cannot be marked as arrived.');
        }

        tx.update(requestRef, {
          'status': 'arrived',
          'arrived': true,
          'arrivedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You have arrived.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    }
  }

  Future<void> _promptPickupAction({
    required String requestId,
    required Map<String, dynamic> data,
  }) async {
    final address = _pickupAddress(data, fallback: 'Unknown address');
    final household = _householdName(data);
    final bagLabel = (data['bagLabel'] ?? '').toString();
    final bagKgNum = _getRequestKg(data);
    final showBagKg = bagKgNum > 0;
    final distanceKm =
        data['distanceKm'] is num ? (data['distanceKm'] as num).toDouble() : null;
    final etaMinutes =
        data['etaMinutes'] is num ? (data['etaMinutes'] as num).toInt() : null;
    final scheduleText = _formatPickupSchedule(data);
    final source = (data['pickupSource'] ?? '').toString();
    final phoneNumber = _phoneNumber(data);

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pickup Request'),
        content: SingleChildScrollView(
          child: Text(
            'Household: $household\n'
            '${phoneNumber.isNotEmpty ? "Mobile: $phoneNumber\n" : ""}'
            'Address: $address\n'
            '${bagLabel.isNotEmpty ? "Bag: $bagLabel${showBagKg ? " (${bagKgNum.toStringAsFixed(1)} kg)" : ""}\n" : ""}'
            '${distanceKm != null ? "Distance: ${distanceKm.toStringAsFixed(2)} km\n" : ""}'
            '${etaMinutes != null ? "ETA: $etaMinutes min\n" : ""}'
            'Schedule: $scheduleText\n'
            '${source.isNotEmpty ? "Pickup Source: $source\n" : ""}',
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'decline'),
            child: const Text('DECLINE'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'accept'),
            child: const Text('ACCEPT'),
          ),
        ],
      ),
    );

    if (choice == 'accept') {
      await _acceptPickup(requestId);
    } else if (choice == 'decline') {
      await _confirmAndDeclinePickup(requestId);
    }
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
    final isUnread = status != 'read';

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
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: isUnread ? 1 : 0,
            child: Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 10, top: 6),
              decoration: const BoxDecoration(
                color: primaryColor,
                shape: BoxShape.circle,
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
                  Align(alignment: Alignment.centerLeft, child: trailing),
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

        String title = 'Active pickup in progress';
        if (status == 'ongoing') {
          title = 'You have an ongoing pickup';
        } else if (status == 'arrived') {
          title = "You're at a pickup location";
        } else if (status == 'scheduled') {
          title = 'Upcoming scheduled pickup';
        }

        final subtitle =
            status == 'scheduled' ? '$household • $scheduleText' : '$household • $address';

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
                    builder: (_) => CollectorPickupMapPage(requestIds: [doc.id]),
                  ),
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: primaryColor.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
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

  Widget _collectorProfileDrawer(BuildContext context) {
    final user = _currentUser;

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
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Icon(Icons.person, size: 80, color: Colors.white54),
          const SizedBox(height: 16),
          Text(
            user?.displayName ?? 'Collector',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            user?.email ?? 'No email',
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _handleLogoutPressed(context),
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
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
    final status = collectorStatus.toLowerCase();

    String title = 'Collector account pending';
    String body = 'Your account is not verified yet.\nPlease wait for approval.';

    if (status == 'pending') {
      title = 'Collector request submitted';
      body = 'Please wait for admin approval.';
    } else if (status == 'adminapproved') {
      title = 'Admin approved';
      body = 'You may now access the Collector Dashboard.';
    } else if (status == 'rejected') {
      title = 'Request rejected';
      body = 'Your collector request was rejected.\nYou may submit again.';
    }

    if (collectorStatus.isEmpty) {
      if (!legacyAdminOk) {
        title = 'Collector account pending';
        body = 'Please wait for admin approval.';
      } else if (!legacyJunkshopOk) {
        title = 'Admin approved';
        body = 'Now wait for junkshop verification.';
      } else if (!legacyActive) {
        title = 'Almost ready';
        body = 'Your account is verified but not yet active.';
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
                  onPressed: () => _handleLogoutPressed(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
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
        (data?['Roles'] ?? data?['role'] ?? '').toString().trim().toLowerCase();
    return rolesRaw == 'collector' || rolesRaw == 'collectors';
  }

  bool _isCollectorAdminApproved(Map<String, dynamic>? data) {
    final status = (data?['collectorStatus'] ?? '').toString().trim().toLowerCase();
    return status == 'adminapproved';
  }

  bool _isLegacyCollectorVerified(Map<String, dynamic>? data) {
    final legacyAdminOk = data?['adminVerified'] == true;
    final legacyAdminStatus = (data?['adminStatus'] ?? '').toString().toLowerCase();
    final legacyJunkshopOk = data?['junkshopVerified'] == true;
    final legacyActive = data?['collectorActive'] == true;

    return legacyAdminOk &&
        legacyAdminStatus == 'approved' &&
        legacyJunkshopOk &&
        legacyActive;
  }

  Widget _buildCollectorNotifBell() {
    final uid = _currentUser?.uid;

    if (uid == null) {
      return _notificationBellButton(hasUnread: false);
    }

    final userDocStream = _userRef(uid).snapshots();

    final mineQuery = _pickupRequestsQuery(
      collectorId: uid,
      active: true,
      statuses: openPickupStatuses,
      orderByUpdatedAt: true,
    ).limit(1);

    final scheduledMineQuery = _scheduledAcceptedMineQuery(uid).limit(1);
    final scheduledInboxQuery = _scheduledInboxQuery(uid).limit(1);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, userSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: mineQuery.snapshots(),
          builder: (context, mineSnap) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: scheduledMineQuery.snapshots(),
              builder: (context, scheduledSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: scheduledInboxQuery.snapshots(),
                  builder: (context, inboxSnap) {
                    final hasUnreadMine =
                        (mineSnap.data?.docs.isNotEmpty ?? false);
                    final hasUnreadScheduled =
                        (scheduledSnap.data?.docs.isNotEmpty ?? false);
                    final hasUnreadInbox =
                        (inboxSnap.data?.docs.isNotEmpty ?? false);

                    final userData = userSnap.data?.data() ?? {};
                    final lastSeen = _asTimestamp(userData['lastNotifSeenAt']);

                    final hasUnread =
                        hasUnreadMine || hasUnreadScheduled || hasUnreadInbox || lastSeen == null;

                    return _notificationBellButton(hasUnread: hasUnread);
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _notificationBellButton({required bool hasUnread}) {
    final uid = _currentUser?.uid;

    return InkWell(
      onTap: () async {
        if (uid != null) {
          await _userRef(uid).set(
            {'lastNotifSeenAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
        }
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
                color: hasUnread ? Colors.amberAccent : Colors.grey.shade300,
              ),
            ),
          ),
          if (hasUnread)
            const Positioned(
              right: 8,
              top: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 8, height: 8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _notificationsDrawer() {
    final user = _currentUser;
    if (user == null) {
      return const Center(
        child: Text(
          'Not logged in',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    final notifStream = _userNotificationsRef(user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();

    final mineQuery = _openMineRequestsQuery(user.uid);
    final scheduledMineQuery = _scheduledAcceptedMineQuery(user.uid);
    final scheduledInboxQuery = _scheduledInboxQuery(user.uid);

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
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: mineQuery.snapshots(),
              builder: (context, mineSnap) {
                if (mineSnap.hasError) {
                  return _errorText('Failed to load pickups:\n${mineSnap.error}');
                }
                if (mineSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: scheduledMineQuery.snapshots(),
                  builder: (context, scheduledSnap) {
                    if (scheduledSnap.hasError) {
                      return _errorText(
                        'Failed to load scheduled pickups:\n${scheduledSnap.error}',
                      );
                    }
                    if (scheduledSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: scheduledInboxQuery.snapshots(),
                      builder: (context, inboxSnap) {
                        if (inboxSnap.hasError) {
                          return _errorText(
                            'Failed to load scheduled requests:\n${inboxSnap.error}',
                          );
                        }
                        if (inboxSnap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: notifStream,
                          builder: (context, notifSnap) {
                            final uid = user.uid;

                            final pickupDocs =
                                (mineSnap.data?.docs ?? []).where((doc) {
                              final declinedBy =
                                  (doc.data()['declinedBy'] as List?) ?? [];
                              return !declinedBy.contains(uid);
                            }).toList()
                                  ..sort((a, b) {
                                    final ta = _asTimestamp(a.data()['updatedAt']) ??
                                        _asTimestamp(a.data()['createdAt']);
                                    final tb = _asTimestamp(b.data()['updatedAt']) ??
                                        _asTimestamp(b.data()['createdAt']);
                                    return (tb?.millisecondsSinceEpoch ?? 0)
                                        .compareTo(ta?.millisecondsSinceEpoch ?? 0);
                                  });

                            final scheduledDocs =
                                (scheduledSnap.data?.docs ?? []).where((doc) {
                              final declinedBy =
                                  (doc.data()['declinedBy'] as List?) ?? [];
                              return !declinedBy.contains(uid);
                            }).toList();

                            final scheduledInboxDocs =
                                (inboxSnap.data?.docs ?? []).where((doc) {
                              final declinedBy =
                                  (doc.data()['declinedBy'] as List?) ?? [];
                              return !declinedBy.contains(uid);
                            }).toList();

                            final currentLoadKg = pickupDocs.fold<double>(
                              0,
                              (sum, doc) => sum + _getRequestKg(doc.data()),
                            );

                            final notifDocs = notifSnap.data?.docs ?? [];

                            return ListView(
                              padding: const EdgeInsets.only(bottom: 20),
                              children: [
                                if (currentLoadKg >= maxCapacityKg)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _notifTile(
                                      title: 'Capacity Full',
                                      subtitle:
                                          'You are already at full capacity (${currentLoadKg.toStringAsFixed(1)} kg / ${maxCapacityKg.toStringAsFixed(1)} kg). Complete an active pickup first before accepting a new one.',
                                      timeText: '',
                                      status: 'unread',
                                    ),
                                  ),
                                if (pickupDocs.isEmpty &&
                                    scheduledDocs.isEmpty &&
                                    scheduledInboxDocs.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: Text(
                                        'No pending pickup requests.',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                    ),
                                  ),
                                ...scheduledInboxDocs.map(_buildScheduledInboxCard),
                                ...scheduledDocs.map(_buildAcceptedScheduledCard),
                                ...pickupDocs.map(_buildPickupRequestCard),
                                if (notifDocs.isNotEmpty) ...[
                                  _buildNotificationsHeader(),
                                  ...notifDocs.map(_buildNotificationCard),
                                ],
                                const SizedBox(height: 24),
                              ],
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

  Widget _errorText(String text) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildScheduledInboxCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final household = _householdName(data);
    final scheduleText = _formatPickupSchedule(data);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (doc == doc) ...[
              const Text(
                'NEW SCHEDULED REQUESTS',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              household,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Scheduled: $scheduleText',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _confirmAndDeclinePickup(doc.id),
                    child: const Text('DECLINE'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _acceptPickup(doc.id),
                    child: const Text('ACCEPT'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcceptedScheduledCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final household = _householdName(data);
    final scheduleText = _formatPickupSchedule(data);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _notifTile(
        title: 'Scheduled pickup accepted',
        subtitle:
            '$household • $scheduleText\nThis pickup will become active at the scheduled time.',
        timeText: '',
        status: 'unread',
      ),
    );
  }

  Widget _buildPickupRequestCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final household = _householdName(data);
    final address = _pickupAddress(data);
    final phone = _phoneNumber(data);
    final bagLabel = (data['bagLabel'] ?? '').toString();
    final bagKg = _getRequestKg(data);
    final distanceKm =
        data['distanceKm'] is num ? (data['distanceKm'] as num).toDouble() : null;
    final etaMinutes =
        data['etaMinutes'] is num ? (data['etaMinutes'] as num).toInt() : null;
    final scheduleText = _formatPickupSchedule(data);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _promptPickupAction(requestId: doc.id, data: data),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.local_shipping_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        household,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        address.isEmpty ? 'No address' : address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Mobile: $phone',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                Icon(Icons.chevron_right, color: Colors.grey.shade500),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill('Schedule: $scheduleText'),
              if (bagLabel.isNotEmpty)
                _pill(
                  'Bag: $bagLabel${bagKg > 0 ? " • ${bagKg.toStringAsFixed(0)}kg" : ""}',
                ),
              if (distanceKm != null)
                _pill('Distance: ${distanceKm.toStringAsFixed(2)} km'),
              if (etaMinutes != null) _pill('ETA: $etaMinutes min'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _confirmAndDeclinePickup(doc.id),
                  child: const Text('DECLINE'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _acceptPickup(doc.id),
                  child: const Text('ACCEPT'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.white.withOpacity(0.10),
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'NOTIFICATIONS',
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
            onPressed: _clearAllCancelledPickupNotifications,
            child: const Text(
              'Clear',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final n = doc.data();
    final title = (n['title'] ?? 'Notification').toString();
    final message = (n['message'] ?? '').toString();
    final reason =
        (n['reason'] ?? n['collectorDeclineReason'] ?? 'No reason provided.')
            .toString();
    final status = (n['status'] ?? 'unread').toString();
    final createdAt = n['createdAt'] as Timestamp?;
    final timeText = createdAt != null ? _formatNotifTime(createdAt) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _notifTile(
        title: title,
        subtitle: message,
        timeText: timeText,
        status: status,
        onTap: () async {
          await showDialog<void>(
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
                child: SingleChildScrollView(
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
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Reason: ',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              reason,
                              style: const TextStyle(
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
            ),
          );

          if (status != 'read') {
            await doc.reference.update({
              'status': 'read',
              'readAt': FieldValue.serverTimestamp(),
            });
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Text(
            'Not logged in',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userRef(user.uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: bgColor,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final userData = snap.data?.data();
        final collectorStatus =
            (userData?['collectorStatus'] ?? '').toString().trim();
        final legacyAdminOk = userData?['adminVerified'] == true;
        final legacyJunkshopOk = userData?['junkshopVerified'] == true;
        final legacyActive = userData?['collectorActive'] == true;

        final canAccessDashboard = _isCollectorRole(userData) &&
            (_isCollectorAdminApproved(userData) ||
                _isLegacyCollectorVerified(userData));

        if (!canAccessDashboard) {
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

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: bgColor,
          endDrawer: Drawer(
            backgroundColor: bgColor,
            child: SafeArea(child: _notificationsDrawer()),
          ),
          drawer: Drawer(
            backgroundColor: bgColor,
            child: SafeArea(child: _collectorProfileDrawer(context)),
          ),
          appBar: AppBar(
            backgroundColor: bgColor,
            elevation: 0,
            title: const Text(
              'Collector Dashboard',
              style: TextStyle(color: Colors.white),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildCollectorNotifBell(),
              ),
            ],
          ),
          body: Column(
            children: [
              _ongoingPickupBanner(),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _openUnassignedRequestsQuery().snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _errorText('Failed to load requests:\n${snap.error}');
                    }

                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(
                        child: Text(
                          'No available pickup requests.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        return _buildPickupRequestCard(docs[index]);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
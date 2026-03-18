import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'collector_transaction_page.dart';
import '../chat/screens/chat_page.dart';
import '../chat/services/chat_services.dart';

extension OpacityFix on Color {
  Color o(double opacity) =>
      withValues(alpha: ((opacity * 255).clamp(0, 255)).toDouble());
}

class PickupStop {
  final String requestId;
  final String householdId;
  final String collectorId;
  final String householdName;
  final String pickupAddress;
  final GeoPoint pickupLocation;
  final String status;
  final String bagLabel;
  final int? bagKg;
  final String phoneNumber;
  final bool hasCollectorReceipt;
  final Timestamp? acceptedAt;

  PickupStop({
    required this.requestId,
    required this.householdId,
    required this.collectorId,
    required this.householdName,
    required this.pickupAddress,
    required this.pickupLocation,
    required this.status,
    required this.bagLabel,
    required this.bagKg,
    required this.phoneNumber,
    required this.hasCollectorReceipt,
    required this.acceptedAt,
  });

  LatLng get latLng => LatLng(pickupLocation.latitude, pickupLocation.longitude);

  PickupStop copyWith({
    String? requestId,
    String? householdId,
    String? collectorId,
    String? householdName,
    String? pickupAddress,
    GeoPoint? pickupLocation,
    String? status,
    String? bagLabel,
    int? bagKg,
    String? phoneNumber,
    bool? hasCollectorReceipt,
    Timestamp? acceptedAt,
  }) {
    return PickupStop(
      requestId: requestId ?? this.requestId,
      householdId: householdId ?? this.householdId,
      collectorId: collectorId ?? this.collectorId,
      householdName: householdName ?? this.householdName,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      status: status ?? this.status,
      bagLabel: bagLabel ?? this.bagLabel,
      bagKg: bagKg ?? this.bagKg,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      hasCollectorReceipt: hasCollectorReceipt ?? this.hasCollectorReceipt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
    );
  }

  static PickupStop? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;

    final gp = data['pickupLocation'];
    if (gp is! GeoPoint) return null;

    final rawBagKg = data['bagKg'] ?? data['bagEstimatedKg'];
    int? parsedBagKg;
    if (rawBagKg is int) {
      parsedBagKg = rawBagKg;
    } else if (rawBagKg is num) {
      parsedBagKg = rawBagKg.toInt();
    } else {
      parsedBagKg = int.tryParse((rawBagKg ?? '').toString());
    }

    return PickupStop(
      requestId: doc.id,
      householdId: (data['householdId'] ?? '').toString(),
      collectorId: (data['collectorId'] ?? '').toString(),
      householdName: (data['householdName'] ?? 'Household').toString(),
      pickupAddress:
          (data['fullAddress'] ?? data['pickupAddress'] ?? '').toString(),
      pickupLocation: gp,
      status: (data['status'] ?? '').toString(),
      bagLabel: (data['bagLabel'] ?? '').toString(),
      bagKg: parsedBagKg,
      phoneNumber: (data['phoneNumber'] ?? '').toString(),
      hasCollectorReceipt: data['hasCollectorReceipt'] == true,
      acceptedAt:
          data['acceptedAt'] is Timestamp ? data['acceptedAt'] as Timestamp : null,
    );
  }
}

class RouteSegment {
  final List<LatLng> points;
  final String distanceText;
  final String durationText;
  final int durationSec;

  RouteSegment({
    required this.points,
    required this.distanceText,
    required this.durationText,
    required this.durationSec,
  });
}

class CollectorPickupMapPage extends StatefulWidget {
  final List<String> requestIds;

  const CollectorPickupMapPage({
    super.key,
    required this.requestIds,
  });

  @override
  State<CollectorPickupMapPage> createState() => _CollectorPickupMapPageState();
}

class _CollectorPickupMapPageState extends State<CollectorPickupMapPage> {
  static const Color _bg = Color(0xFF0F172A);
  static const Color _card = Color(0xFF111928);
  static const Color _accent = Color(0xFF1FA9A7);
  static const String _junkshopUid = "07Wi7N8fALh2yqNdt1CQgIYVGE43";
  static const String _junkshopName = "Mores Scrap";

  static const String _darkMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{ "color": "#0b1220" }]
  },
  {
    "elementType": "labels.icon",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#8b9bb4" }]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{ "color": "#0b1220" }]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry",
    "stylers": [{ "color": "#1e293b" }]
  },
  {
    "featureType": "administrative.country",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#cbd5e1" }]
  },
  {
    "featureType": "administrative.land_parcel",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#cbd5e1" }]
  },
  {
    "featureType": "poi",
    "elementType": "geometry",
    "stylers": [{ "color": "#111827" }]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#94a3b8" }]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [{ "color": "#0f1f1d" }]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#6ee7b7" }]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{ "color": "#1f2937" }]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [{ "color": "#0f172a" }]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#cbd5e1" }]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{ "color": "#243244" }]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [{ "color": "#111827" }]
  },
  {
    "featureType": "road.highway",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#f8fafc" }]
  },
  {
    "featureType": "transit",
    "elementType": "geometry",
    "stylers": [{ "color": "#111827" }]
  },
  {
    "featureType": "transit.station",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#cbd5e1" }]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{ "color": "#07111f" }]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#7dd3fc" }]
  }
]
''';

  final ChatService _chat = ChatService();
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  GoogleMapController? _map;
  Position? _pos;

  BitmapDescriptor? _collectorMarkerIcon;
  BitmapDescriptor? _householdMarkerIcon;

  bool _topExpanded = false;
  bool _loadingStops = true;
  bool _loadingRoute = false;
  bool _junkshopChatEnsured = false;
  bool _isSendingLiveLocation = false;

  List<PickupStop> _stops = [];
  int _currentStopIndex = 0;

  List<LatLng> _route = [];
  String _distanceText = "";
  String _durationText = "";
  int? _durationValueSec;

  StreamSubscription<Position>? _liveLocationSub;

  @override
  void initState() {
    super.initState();
    _setupPage();
  }

  Future<void> _setupPage() async {
    await _loadMarkerIcons();
    await _initPage();
  }

  PickupStop? get _currentStop {
    if (_stops.isEmpty) return null;
    if (_currentStopIndex < 0 || _currentStopIndex >= _stops.length) {
      return null;
    }
    return _stops[_currentStopIndex];
  }

  LatLng? get _originLatLng {
    if (_pos == null) return null;
    return LatLng(_pos!.latitude, _pos!.longitude);
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<BitmapDescriptor> _iconToMarker({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required Color borderColor,
    double size = 112,
    double iconSize = 54,
  }) async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    final painter = _MarkerPainter(
      icon: icon,
      iconColor: iconColor,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      size: size,
      iconSize: iconSize,
    );

    painter.paint(canvas, Size(size, size));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _loadMarkerIcons() async {
    try {
      _collectorMarkerIcon = await _iconToMarker(
        icon: Icons.shopping_cart_rounded,
        iconColor: Colors.white,
        backgroundColor: _accent,
        borderColor: Colors.white.withOpacity(0.18),
      );

      _householdMarkerIcon = await _iconToMarker(
        icon: Icons.house_rounded,
        iconColor: Colors.white,
        backgroundColor: const Color(0xFF334155),
        borderColor: Colors.white.withOpacity(0.18),
      );

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint("❌ Failed to build marker icons: $e");
    }
  }

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

  Future<void> _markChatRead(String chatId) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (me.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
        'lastReadBy': {me: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("❌ Failed to mark chat read: $e");
    }
  }

  Future<void> _startLiveLocationSharing() async {
    final stop = _currentStop;
    if (stop == null) return;

    final status = stop.status.toLowerCase();
    final shouldShare =
        status == 'accepted' || status == 'arrived' || status == 'scheduled';

    if (!shouldShare) return;

    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return;

    _isSendingLiveLocation = true;

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    if (mounted) {
      setState(() {
        _pos = position;
      });
    }

    await FirebaseFirestore.instance
        .collection('requests')
        .doc(stop.requestId)
        .set({
      'collectorLiveLocation': GeoPoint(position.latitude, position.longitude),
      'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
      'collectorHeading': position.heading,
      'collectorSpeedMps': position.speed,
      'sharingLiveLocation': true,
    }, SetOptions(merge: true));

    await _liveLocationSub?.cancel();
    _liveLocationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((position) async {
      final currentStop = _currentStop;
      if (currentStop == null) return;

      try {
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(currentStop.requestId)
            .set({
          'collectorLiveLocation':
              GeoPoint(position.latitude, position.longitude),
          'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
          'collectorHeading': position.heading,
          'collectorSpeedMps': position.speed,
          'sharingLiveLocation': true,
        }, SetOptions(merge: true));

        if (mounted) {
          setState(() {
            _pos = position;
          });
        }
      } catch (e) {
        debugPrint("❌ live location write failed: $e");
      }
    });
  }

  Future<void> _stopLiveLocationSharing({bool clearFirestore = false}) async {
    await _liveLocationSub?.cancel();
    _liveLocationSub = null;
    _isSendingLiveLocation = false;

    if (!clearFirestore) return;

    final stop = _currentStop;
    if (stop == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(stop.requestId)
          .set({
        'sharingLiveLocation': false,
        'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ stop live location sharing failed: $e');
    }
  }

  Future<void> _initPage() async {
    await _initLocation();
    await _loadStops();

    if (_stops.isNotEmpty) {
      await _ensureJunkshopChatIfNeeded();
      await _buildMultiStopRoute();
      await _focusCameraOnCurrentStop();
      await _startLiveLocationSharing();
    }
  }

  Future<void> _initLocation() async {
    final ok = await _ensureLocationPermission();
    if (!ok) return;

    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      if (!mounted) return;
      setState(() => _pos = p);
    } catch (e) {
      debugPrint("❌ _initLocation error: $e");
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();

    if (!enabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please turn on location services.")),
        );
      }
      return false;
    }

    var perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.denied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied.")),
        );
      }
      return false;
    }

    if (perm == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Location permission permanently denied. Open app settings.",
            ),
          ),
        );
      }
      await Geolocator.openAppSettings();
      return false;
    }

    return true;
  }

  Future<void> _loadStops() async {
    try {
      if (widget.requestIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loadingStops = false;
          _stops = [];
        });
        return;
      }

      final ids = widget.requestIds.toSet().toList();
      final futures = ids.map(
        (id) => FirebaseFirestore.instance.collection('requests').doc(id).get(),
      );

      final docs = await Future.wait(futures);

      final loadedStops = <PickupStop>[];
      for (final doc in docs) {
        final stop = PickupStop.fromDoc(doc);
        if (stop != null) loadedStops.add(stop);
      }

      if (_originLatLng != null && loadedStops.isNotEmpty) {
        loadedStops.sort((a, b) {
          final aAccepted = a.acceptedAt?.toDate();
          final bAccepted = b.acceptedAt?.toDate();
          if (aAccepted == null && bAccepted == null) return 0;
          if (aAccepted == null) return 1;
          if (bAccepted == null) return -1;
          return aAccepted.compareTo(bAccepted);
        });

        final ordered = _orderStopsNearest(
          start: _originLatLng!,
          stops: loadedStops,
        );

        if (!mounted) return;
        setState(() {
          _stops = ordered;
          _currentStopIndex = 0;
          _loadingStops = false;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _stops = loadedStops;
          _currentStopIndex = 0;
          _loadingStops = false;
        });
      }
    } catch (e) {
      debugPrint("❌ _loadStops error: $e");
      if (!mounted) return;
      setState(() {
        _loadingStops = false;
      });
    }
  }

  double _distanceSquared(LatLng a, LatLng b) {
    final dx = a.latitude - b.latitude;
    final dy = a.longitude - b.longitude;
    return dx * dx + dy * dy;
  }

  List<PickupStop> _orderStopsNearest({
    required LatLng start,
    required List<PickupStop> stops,
  }) {
    final remaining = List<PickupStop>.from(stops);
    final ordered = <PickupStop>[];
    var current = start;

    while (remaining.isNotEmpty) {
      remaining.sort((a, b) {
        final da = _distanceSquared(current, a.latLng);
        final db = _distanceSquared(current, b.latLng);
        return da.compareTo(db);
      });

      final next = remaining.removeAt(0);
      ordered.add(next);
      current = next.latLng;
    }

    return ordered;
  }

  Future<void> _ensureJunkshopChatIfNeeded() async {
    if (_junkshopChatEnsured) return;
    final stop = _currentStop;
    if (stop == null) return;

    final s = stop.status.toLowerCase();
    if (!(s == "accepted" || s == "arrived" || s == "scheduled")) return;

    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    final collectorUid =
        stop.collectorId.trim().isNotEmpty ? stop.collectorId.trim() : me;
    if (collectorUid.isEmpty) return;

    try {
      _junkshopChatEnsured = true;
      await _chat.ensureJunkshopChatForRequest(
        requestId: stop.requestId,
        junkshopUid: _junkshopUid,
        collectorUid: collectorUid,
      );
    } catch (e) {
      debugPrint("❌ ensureJunkshopChatForRequest failed: $e");
    }
  }

  Future<RouteSegment?> _getRouteSegment(
      LatLng origin, LatLng destination) async {
    try {
      final callable = _functions.httpsCallable('getDirections');
      final result = await callable.call({
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': 'driving',
      });

      final data = result.data;
      if (data is! Map) return null;

      final points = data['points'] as String?;
      if (points == null || points.isEmpty) return null;

      final dist = (data['distanceText'] ?? '').toString();
      final dur = (data['durationText'] ?? '').toString();
      final durVal = data['durationValueSec'];

      final decoded = _decodePolyline(points);

      return RouteSegment(
        points: decoded,
        distanceText: dist,
        durationText: dur,
        durationSec: durVal is int ? durVal : 0,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint("❌ getDirections failed: ${e.code} ${e.message}");
      return null;
    } catch (e) {
      debugPrint("❌ getDirections crashed: $e");
      return null;
    }
  }

  Future<void> _callCurrentStop() async {
    final stop = _currentStop;
    if (stop == null || stop.phoneNumber.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No mobile number available.")),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: stop.phoneNumber.trim());

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open dialer.")),
      );
    }
  }

  Future<void> _buildMultiStopRoute() async {
    if (_originLatLng == null || _stops.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _loadingRoute = true;
    });

    final routePoints = <LatLng>[];
    int totalDurationSec = 0;
    final distanceParts = <String>[];

    LatLng current = _originLatLng!;

    for (int i = _currentStopIndex; i < _stops.length; i++) {
      final stop = _stops[i];
      final segment = await _getRouteSegment(current, stop.latLng);
      if (segment == null) {
        current = stop.latLng;
        continue;
      }

      if (routePoints.isEmpty) {
        routePoints.addAll(segment.points);
      } else if (segment.points.isNotEmpty) {
        routePoints.addAll(segment.points.skip(1));
      }

      totalDurationSec += segment.durationSec;
      if (segment.distanceText.isNotEmpty) distanceParts.add(segment.distanceText);

      current = stop.latLng;
    }

    if (!mounted) return;
    setState(() {
      _route = routePoints;
      _durationValueSec = totalDurationSec;
      _distanceText = distanceParts.isNotEmpty ? distanceParts.join(" + ") : "";
      _durationText = totalDurationSec > 0 ? _formatDuration(totalDurationSec) : "";
      _loadingRoute = false;
    });
  }

  String _formatDuration(int totalSeconds) {
    final totalMinutes = (totalSeconds / 60).round();
    if (totalMinutes < 60) return "$totalMinutes min";

    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (mins == 0) return "$hours hr";
    return "$hours hr $mins min";
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  Future<void> _focusCameraOnCurrentStop() async {
    final stop = _currentStop;
    if (stop == null || _map == null) return;

    await _map!.animateCamera(
      CameraUpdate.newLatLngZoom(stop.latLng, 15),
    );
  }

  Future<void> _openJunkshopChat() async {
    final stop = _currentStop;
    if (stop == null) return;

    final s = stop.status.toLowerCase();
    final canChat = s == "accepted" || s == "arrived" || s == "scheduled";

    if (!canChat) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Junkshop chat is available once pickup is accepted."),
        ),
      );
      return;
    }

    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    var collectorUid = stop.collectorId.trim();

    if (me.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Collector ID not loaded yet.")),
      );
      return;
    }

    if (collectorUid.isEmpty) {
      collectorUid = me;
      try {
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(stop.requestId)
            .update({
          'collectorId': me,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final idx = _stops.indexWhere((x) => x.requestId == stop.requestId);
        if (idx != -1 && mounted) {
          setState(() {
            _stops[idx] = _stops[idx].copyWith(collectorId: me);
          });
        }
      } catch (e) {
        debugPrint("❌ Failed to write collectorId for junkshop chat: $e");
      }
    }

    try {
      await _chat.ensureJunkshopChatForRequest(
        requestId: stop.requestId,
        junkshopUid: _junkshopUid,
        collectorUid: collectorUid,
      );

      final chatId = "junkshop_pickup_${stop.requestId}";
      await _markChatRead(chatId);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            chatId: chatId,
            title: _junkshopName,
            otherUserId: _junkshopUid,
          ),
        ),
      );
    } catch (e) {
      debugPrint("❌ Failed to open junkshop chat: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to open junkshop chat: $e")),
      );
    }
  }

  Future<void> _openPickupChat() async {
    final stop = _currentStop;
    if (stop == null) return;

    final s = stop.status.toLowerCase();
    final canChat = s == "accepted" || s == "arrived" || s == "scheduled";

    if (!canChat) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat is available once pickup is accepted.")),
      );
      return;
    }

    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    final householdUid = stop.householdId.trim();
    var collectorUid = stop.collectorId.trim();

    if (me.isEmpty || householdUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat IDs not loaded yet. Please try again.")),
      );
      return;
    }

    if (collectorUid.isEmpty) {
      collectorUid = me;
      try {
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(stop.requestId)
            .update({
          'collectorId': me,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        final idx = _stops.indexWhere((s) => s.requestId == stop.requestId);
        if (idx != -1 && mounted) {
          setState(() {
            _stops[idx] = _stops[idx].copyWith(collectorId: me);
          });
        }
      } catch (e) {
        debugPrint("❌ Failed to write collectorId: $e");
      }
    }

    if (collectorUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Collector not assigned yet.")),
      );
      return;
    }

    final chatId = await _chat.ensurePickupChat(
      requestId: stop.requestId,
      householdUid: householdUid,
      collectorUid: collectorUid,
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          chatId: chatId,
          title: stop.householdName.isEmpty ? "Household" : stop.householdName,
          otherUserId: householdUid,
        ),
      ),
    );
  }

  Future<void> _openStopChat(PickupStop stop) async {
    final s = stop.status.toLowerCase();
    final canChat = s == "accepted" || s == "arrived" || s == "scheduled";

    if (!canChat) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat is available once pickup is accepted.")),
      );
      return;
    }

    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    final householdUid = stop.householdId.trim();
    var collectorUid = stop.collectorId.trim();

    if (me.isEmpty || householdUid.isEmpty) return;

    if (collectorUid.isEmpty) {
      collectorUid = me;
    }

    final chatId = await _chat.ensurePickupChat(
      requestId: stop.requestId,
      householdUid: householdUid,
      collectorUid: collectorUid,
    );

    await _markChatRead(chatId);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          chatId: chatId,
          title: stop.householdName.isEmpty ? "Household" : stop.householdName,
          otherUserId: householdUid,
        ),
      ),
    );
  }

  Future<void> _openCollectorReceipt() async {
    final stop = _currentStop;
    if (stop == null) return;

    final s = stop.status.toLowerCase();
    if (s != "arrived") {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Create receipt is available once you are ARRIVED.")),
      );
      return;
    }

    try {
      final reqDoc = await FirebaseFirestore.instance
          .collection('requests')
          .doc(stop.requestId)
          .get();

      final data = reqDoc.data() ?? {};
      final hasReceipt = data['hasCollectorReceipt'] == true;

      if (hasReceipt) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Receipt already created for this pickup.")),
        );
        return;
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CollectorTransactionPage(
          requestId: stop.requestId,
          embedded: false,
        ),
      ),
    );
  }

  Future<void> _moveToNextStopAfterComplete() async {
    final nextIndex = _currentStopIndex + 1;

    if (!mounted) return;

    if (nextIndex < _stops.length) {
      setState(() {
        _currentStopIndex = nextIndex;
      });

      await _startLiveLocationSharing();
      await _ensureJunkshopChatIfNeeded();
      await _buildMultiStopRoute();
      await _focusCameraOnCurrentStop();

      final stop = _currentStop;
      if (!mounted || stop == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Moved to next stop: ${stop.householdName}")),
      );
    } else {
      await _stopLiveLocationSharing(clearFirestore: true);

      if (!mounted) return;
      setState(() {
        _stops = [];
        _currentStopIndex = 0;
        _route = [];
        _distanceText = "";
        _durationText = "";
        _durationValueSec = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("All pickup stops completed.")),
      );
    }
  }

  Future<void> _markArrivedOrComplete() async {
    final stop = _currentStop;
    if (stop == null) return;

    final s = stop.status.toLowerCase();

    if (s == 'arrived') {
      try {
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(stop.requestId)
            .update({
          'status': 'completed',
          'active': false,
          'completedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'junkshopId': _junkshopUid,
          'junkshopName': _junkshopName,
          'sharingLiveLocation': false,
        });

        final idx = _stops.indexWhere((x) => x.requestId == stop.requestId);
        if (idx != -1 && mounted) {
          setState(() {
            _stops[idx] = _stops[idx].copyWith(status: 'completed');
          });
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Marked as completed.")),
        );

        await _stopLiveLocationSharing(clearFirestore: true);
        await _moveToNextStopAfterComplete();
      } on FirebaseException catch (e) {
        debugPrint("❌ Complete failed: ${e.code} | ${e.message}");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Complete failed: ${e.code}")),
        );
      } catch (e) {
        debugPrint("❌ Complete failed: $e");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Complete failed: $e")),
        );
      }
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(stop.requestId)
          .update({
        'status': 'arrived',
        'arrived': true,
        'arrivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final idx = _stops.indexWhere((x) => x.requestId == stop.requestId);
      if (idx != -1 && mounted) {
        setState(() {
          _stops[idx] = _stops[idx].copyWith(status: 'arrived');
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Marked as arrived.")),
      );
    } on FirebaseException catch (e) {
      debugPrint("❌ Arrived failed: ${e.code} | ${e.message}");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Arrived failed: ${e.code}")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_stopLiveLocationSharing(clearFirestore: true));
    _map?.dispose();
    super.dispose();
  }

  Future<void> _goToStop(int index) async {
    if (index < 0 || index >= _stops.length) return;

    await _stopLiveLocationSharing();

    setState(() {
      _currentStopIndex = index;
    });

    await _ensureJunkshopChatIfNeeded();
    await _buildMultiStopRoute();
    await _focusCameraOnCurrentStop();
    await _startLiveLocationSharing();
  }

  Set<Marker> _buildMarkers() {
    return <Marker>{
      if (_pos != null)
        Marker(
          markerId: const MarkerId("me"),
          position: LatLng(_pos!.latitude, _pos!.longitude),
          infoWindow: const InfoWindow(title: "You / Collector"),
          icon: _collectorMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          zIndex: 3,
        ),
      ..._stops.asMap().entries.map((entry) {
        final index = entry.key;
        final stop = entry.value;
        final isCurrent = index == _currentStopIndex;

        return Marker(
          markerId: MarkerId(stop.requestId),
          position: stop.latLng,
          infoWindow: InfoWindow(
            title: "Stop ${index + 1}: ${stop.householdName}",
            snippet: stop.pickupAddress,
          ),
          icon: _householdMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
          zIndex: isCurrent ? 2 : 1,
        );
      }),
    };
  }

  Set<Polyline> _buildPolylines() {
    if (_route.isEmpty) return <Polyline>{};

    return {
      Polyline(
        polylineId: const PolylineId("route"),
        points: _route,
        width: 6,
        color: _accent,
      ),
    };
  }

  Widget _buildEmptyLiveState() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          children: [
            Row(
              children: [
                _circularButton(
                  Icons.arrow_back,
                  onTap: () {
                    if (Navigator.of(context).canPop()) Navigator.pop(context);
                  },
                ),
              ],
            ),
            const Spacer(),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.52),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(0.14),
                          shape: BoxShape.circle,
                          border: Border.all(color: _accent.withOpacity(0.35)),
                        ),
                        child: const Icon(
                          Icons.local_shipping_outlined,
                          color: _accent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "No active pickups",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "New pickup requests will appear here automatically.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.68),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sync,
                              size: 15,
                              color: Colors.white.withOpacity(0.82),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              "Waiting for assignments",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentStop = _currentStop;
    final markers = _buildMarkers();
    final polylines = _buildPolylines();

    if (!_loadingStops && _stops.isEmpty) {
      return Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            Positioned.fill(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _pos != null
                      ? LatLng(_pos!.latitude, _pos!.longitude)
                      : const LatLng(14.5995, 120.9842),
                  zoom: 13,
                ),
                onMapCreated: (c) async {
                  _map = c;
                  await _map?.setMapStyle(_darkMapStyle);
                },
                myLocationEnabled: _pos != null,
                markers: markers,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
              ),
            ),
            _buildEmptyLiveState(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: currentStop?.latLng ?? const LatLng(14.5995, 120.9842),
                zoom: 15,
              ),
              onMapCreated: (c) async {
                _map = c;
                await _map?.setMapStyle(_darkMapStyle);
              },
              myLocationEnabled: _pos != null,
              markers: markers,
              polylines: polylines,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _circularButton(
                        Icons.arrow_back,
                        onTap: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _topExpanded = !_topExpanded),
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: _topExpanded ? 190 : 56,
                              ),
                              child: _glass(
                                radius: 16,
                                blur: 12,
                                opacity: 0.55,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.local_shipping,
                                          size: 18,
                                          color: _accent,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            currentStop == null
                                                ? "Pickup Route"
                                                : "Stop ${_currentStopIndex + 1}/${_stops.length} • ${currentStop.householdName}",
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          _topExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          color: Colors.white.withOpacity(0.85),
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                    if (_topExpanded && currentStop != null) ...[
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          physics:
                                              const BouncingScrollPhysics(),
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              _pillChip(
                                                icon:
                                                    Icons.inventory_2_outlined,
                                                text: currentStop.bagLabel.isEmpty
                                                    ? "Bag: —"
                                                    : "Bag: ${currentStop.bagLabel}${currentStop.bagKg == null ? "" : " (${currentStop.bagKg}kg)"}",
                                              ),
                                              _pillChip(
                                                icon: Icons.info_outline,
                                                text: currentStop.status.isEmpty
                                                    ? "Status: —"
                                                    : "Status: ${currentStop.status.toUpperCase()}",
                                              ),
                                              _pillChip(
                                                icon: Icons.place_outlined,
                                                text: currentStop
                                                        .pickupAddress.isEmpty
                                                    ? "Address: —"
                                                    : currentStop.pickupAddress,
                                              ),
                                              if (currentStop
                                                  .phoneNumber.isNotEmpty)
                                                _pillChip(
                                                  icon: Icons.phone_outlined,
                                                  text:
                                                      "Mobile: ${currentStop.phoneNumber}",
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.30,
            minChildSize: 0.18,
            maxChildSize: 0.78,
            builder: (context, scrollController) {
              return ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(22)),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withOpacity(0.10),
                        ),
                      ),
                    ),
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_loadingStops)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _miniStat(
                                  Icons.access_time,
                                  _loadingRoute
                                      ? "Loading..."
                                      : (_durationText.isEmpty
                                          ? "—"
                                          : _durationText),
                                ),
                                _miniStat(
                                  Icons.navigation_outlined,
                                  _loadingRoute
                                      ? "..."
                                      : (_distanceText.isEmpty
                                          ? "—"
                                          : _distanceText),
                                ),
                                _miniStat(
                                  Icons.route,
                                  "${_stops.length} stop${_stops.length == 1 ? '' : 's'}",
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius: BorderRadius.circular(16),
                              border:
                                  Border.all(color: Colors.white.withOpacity(0.08)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Stops (${_stops.length})",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                for (int i = 0; i < _stops.length; i++) ...[
                                  _stopTile(i, _stops[i]),
                                  if (i != _stops.length - 1)
                                    const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _actionWide(
                                  icon: Icons.chat_bubble_outline,
                                  title: "CHAT",
                                  subtitle: "Message junkshop",
                                  bg: Colors.white.withOpacity(0.10),
                                  fg: Colors.white,
                                  border: Colors.white.withOpacity(0.14),
                                  onTap: _openJunkshopChat,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _actionWide(
                                  icon: currentStop?.status.toLowerCase() ==
                                          'arrived'
                                      ? Icons.check_circle
                                      : Icons.location_on_outlined,
                                  title: currentStop?.status.toLowerCase() ==
                                          'arrived'
                                      ? "COMPLETE"
                                      : "ARRIVED",
                                  subtitle: currentStop?.status.toLowerCase() ==
                                          'arrived'
                                      ? "Finish current stop"
                                      : "Mark current stop",
                                  bg: _accent,
                                  fg: _bg,
                                  onTap: _markArrivedOrComplete,
                                ),
                              ),
                            ],
                          ),
                        
                          const SizedBox(height: 10),
                          if (currentStop?.phoneNumber.trim().isNotEmpty == true)
                            _actionWide(
                              icon: Icons.call_outlined,
                              title: "CALL",
                              subtitle: "Contact household",
                              bg: Colors.white.withOpacity(0.10),
                              fg: Colors.white,
                              border: Colors.white.withOpacity(0.14),
                              onTap: _callCurrentStop,
                            ),
                          const SizedBox(height: 10),
                          if (currentStop?.status.toLowerCase() == "arrived")
                            _actionWide(
                              icon: (currentStop?.hasCollectorReceipt == true)
                                  ? Icons.receipt
                                  : Icons.receipt_long,
                              title: (currentStop?.hasCollectorReceipt == true)
                                  ? "RECEIPT SAVED"
                                  : "RECEIPT",
                              subtitle:
                                  (currentStop?.hasCollectorReceipt == true)
                                      ? "Already created"
                                      : "Create buying receipt",
                              bg: Colors.white.withOpacity(0.10),
                              fg: Colors.white,
                              border: Colors.white.withOpacity(0.14),
                              onTap: (currentStop?.hasCollectorReceipt == true)
                                  ? null
                                  : _openCollectorReceipt,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _stopTile(int index, PickupStop stop) {
    final isCurrent = index == _currentStopIndex;

    return InkWell(
      onTap: () => _goToStop(index),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrent
              ? _accent.withOpacity(0.14)
              : const Color(0xFF0F1A2E).withOpacity(0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent
                ? _accent.withOpacity(0.70)
                : Colors.white.withOpacity(0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.16),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isCurrent ? _accent : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                "${index + 1}",
                style: TextStyle(
                  color: isCurrent ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.householdName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stop.pickupAddress.isEmpty
                        ? "No address available"
                        : stop.pickupAddress,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.68),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _tinyBadge(Icons.home_outlined, "Household"),
                      _tinyBadge(Icons.info_outline, stop.status.toUpperCase()),
                      if (stop.phoneNumber.isNotEmpty)
                        _tinyBadge(Icons.call_outlined, stop.phoneNumber),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildStopChatButton(stop),
          ],
        ),
      ),
    );
  }

  Widget _buildStopChatButton(PickupStop stop) {
    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    final chatId = "pickup_${stop.requestId}";

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .snapshots(),
      builder: (context, snap) {
        bool hasUnread = false;

        final chat = snap.data?.data();
        if (chat != null && me.isNotEmpty) {
          final lastMessageAt = chat['lastMessageAt'];
          final lastMessageSenderId =
              (chat['lastMessageSenderId'] ?? '').toString();

          final lastReadBy = chat['lastReadBy'];
          Timestamp? myLastRead;

          if (lastReadBy is Map && lastReadBy[me] is Timestamp) {
            myLastRead = lastReadBy[me] as Timestamp;
          }

          if (lastMessageAt is Timestamp &&
              lastMessageSenderId.isNotEmpty &&
              lastMessageSenderId != me) {
            if (myLastRead == null ||
                myLastRead.millisecondsSinceEpoch <
                    lastMessageAt.millisecondsSinceEpoch) {
              hasUnread = true;
            }
          }
        }

        return InkWell(
          onTap: () => _openStopChat(stop),
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.10)),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              if (hasUnread)
                Positioned(
                  top: -1,
                  right: -1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF111928),
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
  }

  Widget _tinyBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white.withOpacity(0.85)),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white.withOpacity(0.85)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _glass({
    required Widget child,
    double blur = 12,
    double opacity = 0.55,
    double radius = 16,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(opacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _circularButton(IconData icon, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _bg.o(0.92),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.o(0.14)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.o(0.35),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }

  Widget _pillChip({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withOpacity(0.90)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionWide({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color bg,
    required Color fg,
    Color? border,
    VoidCallback? onTap,
  }) {
    final disabled = onTap == null;

    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (border ?? Colors.white.withOpacity(0.10))
                  .withOpacity(disabled ? 0.55 : 1.0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(disabled ? 0.10 : 0.18),
                blurRadius: 14,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(
                    disabled
                        ? 0.10
                        : (bg == Colors.white || bg == _accent ? 0.06 : 0.18),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: fg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg.withOpacity(0.80),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
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
}

class _MarkerPainter {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final double size;
  final double iconSize;

  _MarkerPainter({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.size,
    required this.iconSize,
  });

  void paint(Canvas canvas, Size s) {
    final center = Offset(s.width / 2, s.height / 2);
    final radius = s.width / 2.6;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawCircle(center.translate(0, 4), radius, shadowPaint);

    final fillPaint = Paint()..color = backgroundColor;
    canvas.drawCircle(center, radius, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    canvas.drawCircle(center, radius, borderPaint);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: iconSize,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: iconColor,
      ),
    );
    textPainter.layout();

    final iconOffset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - textPainter.height / 2,
    );

    textPainter.paint(canvas, iconOffset);
  }
}
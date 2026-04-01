import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../collector/collectors_dashboard.dart';
import '../household/household_dashboard.dart';

extension TrackingOpacityFix on Color {
  Color o(double opacity) => withValues(alpha: opacity.clamp(0.0, 1.0));
}

class CollectorTrackingPage extends StatefulWidget {
  final String? requestId;
  final LatLng? fixedDestination;
  final String destinationTitle;
  final String destinationAddress;
  final bool useCurrentLocationAsOrigin;
  final bool showChatButton;
  final bool showCancelButton;
  final bool showArrivedButton;
  final String trackingType; // "pickup" or "sell"
  final String? sellRequestId;

  const CollectorTrackingPage({
    super.key,
    this.requestId,
    this.fixedDestination,
    this.destinationTitle = "Destination",
    this.destinationAddress = "",
    this.useCurrentLocationAsOrigin = false,
    this.showChatButton = false,
    this.showCancelButton = false,
    this.showArrivedButton = false,
    this.trackingType = "pickup",
    this.sellRequestId,
  }) : assert(
          requestId != null || fixedDestination != null,
          'Provide either requestId or fixedDestination',
        );

  @override
  State<CollectorTrackingPage> createState() => _CollectorTrackingPageState();
}

class _CollectorTrackingPageState extends State<CollectorTrackingPage> {
  static const Color _bg = Color(0xFF0B1220);
  static const Color _sheet = Color(0xFF121C2E);
  static const Color _surface = Color(0xFF162235);
  static const Color _surfaceAlt = Color(0xFF1B2A40);
  static const Color _border = Color(0xFF26364F);
  static const Color _accent = Color(0xFF1FA9A7);
  static const Color _blue = Color(0xFF60A5FA);
  static const Color _warning = Color(0xFFF59E0B);
  static const Color _danger = Color(0xFFEF4444);

  static const Color _textPrimary = Color(0xFFE2E8F0);
  static const Color _textSecondary = Color(0xFF94A3B8);
  static const Color _textMuted = Color(0xFF64748B);

  static const String _moresUid = "07Wi7N8fALh2yqNdt1CQgIYVGE43";

  static const Duration _markerAnimDuration = Duration(milliseconds: 900);
  static const int _markerAnimSteps = 45;

  static const String _darkMapStyle = r'''
[
  {"elementType":"geometry","stylers":[{"color":"#0b1220"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8aa0b8"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0b1220"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#2b3445"}]},
  {"featureType":"administrative","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.business","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.business","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#0f1a2a"}]},
  {"featureType":"poi.park","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#162235"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#0b1220"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#93a8bf"}]},
  {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#1f2f48"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#0b1220"}]},
  {"featureType":"road.highway","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"transit.station","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#06101c"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#6f879f"}]}
]
''';

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  GoogleMapController? _mapController;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _requestSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sellRequestSub;
  Timer? _markerAnimationTimer;

  LatLng? _pickupLatLng;
  LatLng? _collectorLatLng;
  LatLng? _myLatLng;

  String _collectorName = "Collector";
  String _status = "";
  String _street = "";
  String _subdivision = "";
  String _landmark = "";
  String _phoneNumber = "";

  String _routeDistanceText = "";
  String _routeDurationText = "";
  List<LatLng> _collectorRoutePoints = [];

  bool _initialFitDone = false;
  bool _loading = true;
  bool _markingArrived = false;
  bool _collectorArrivedToMores = false;
  bool _sellTransactionAudited = false;
  bool _isCollectorLive = false;
  bool _sentToDashboard = false;

  double _collectorHeading = 0;

  BitmapDescriptor? _collectorIcon;
  BitmapDescriptor? _householdMarkerIcon;
  BitmapDescriptor? _moresMarkerIcon;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  bool get _isFixedDestinationMode => widget.fixedDestination != null;

  bool get _hasValidRequestId =>
      widget.requestId != null && widget.requestId!.trim().isNotEmpty;

  bool get _isSellTracking => widget.trackingType == "sell";

  DocumentReference<Map<String, dynamic>> get _requestDoc =>
      _db.collection('requests').doc(widget.requestId);

  DocumentReference<Map<String, dynamic>> get _sellRequestDoc => _db
      .collection('Users')
      .doc(_moresUid)
      .collection('sell_requests')
      .doc(widget.sellRequestId);

  String get _displayCollectorName =>
      _collectorName.trim().isEmpty ? "Collector" : _collectorName;

  String get _displayAddress {
    final parts = [
      if (_street.trim().isNotEmpty) _street.trim(),
      if (_subdivision.trim().isNotEmpty) _subdivision.trim(),
    ];
    return parts.join(", ");
  }

  String get _locationSectionLabel =>
      _isFixedDestinationMode ? "DESTINATION" : "PICKUP LOCATION";

  String get _locationSectionValue {
    if (_displayAddress.isNotEmpty) return _displayAddress;
    return _isFixedDestinationMode
        ? widget.destinationTitle
        : "Pinned / GPS pickup location";
  }

  String get _liveStatusText {
    if (_collectorLatLng != null) {
      if (_isFixedDestinationMode) {
        return "Live route to ${widget.destinationTitle}";
      }
      return _isCollectorLive
          ? "$_displayCollectorName is sharing live location"
          : "$_displayCollectorName last known location";
    }

    return _isFixedDestinationMode
        ? "Waiting for your current location"
        : "Waiting for collector location update";
  }

  String get _topBarTitle => _isFixedDestinationMode
      ? "Route to ${widget.destinationTitle}"
      : "Track Collector";

  @override
  void initState() {
    super.initState();
    _initPage();
    if (_isSellTracking) {
      _listenToSellRequest();
    }
  }

  @override
  void dispose() {
    _markerAnimationTimer?.cancel();
    _requestSub?.cancel();
    _sellRequestSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initPage() async {
    await _loadMarkerIcons();
    await _initMyLocation();

    if (_isFixedDestinationMode) {
      await _setupFixedDestinationMode();
    } else {
      _listenToRequest();
    }
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

double _easeInOut(double t) {
  if (t < 0.5) return 2 * t * t;
  return 1 - (math.pow(-2 * t + 2, 2) / 2);
}

  double _shortestAngleLerp(double from, double to, double t) {
    final delta = ((to - from + 540) % 360) - 180;
    return (from + delta * t + 360) % 360;
  }

  void _animateCollectorMarker({
    required LatLng from,
    required LatLng to,
    required double fromHeading,
    required double toHeading,
  }) {
    _markerAnimationTimer?.cancel();

    int step = 0;
    final stepMs =
        (_markerAnimDuration.inMilliseconds / _markerAnimSteps).round();

    _markerAnimationTimer =
        Timer.periodic(Duration(milliseconds: stepMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      step++;
      final rawT = step / _markerAnimSteps;
      final t = _easeInOut(rawT.clamp(0.0, 1.0));

      setState(() {
        _collectorLatLng = _lerpLatLng(from, to, t);
        _collectorHeading = _shortestAngleLerp(fromHeading, toHeading, t);
      });

      if (step >= _markerAnimSteps) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _collectorLatLng = to;
            _collectorHeading = toHeading;
          });
        }
      }
    });
  }

  void _goToDashboardIfTransactionEnded(Map<String, dynamic> data) {
    if (_sentToDashboard || !mounted) return;

    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    final active = data['active'] == true;

    final isFinished = !active ||
        status == 'completed' ||
        status == 'done' ||
        status == 'cancelled' ||
        status == 'canceled' ||
        status == 'declined';

    if (!isFinished) return;

    _sentToDashboard = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DashboardPage()),
        (route) => false,
      );
    });
  }

  void _listenToSellRequest() {
    if (widget.sellRequestId == null || widget.sellRequestId!.trim().isEmpty) {
      return;
    }

    _sellRequestSub?.cancel();
    _sellRequestSub = _sellRequestDoc.snapshots().listen((doc) async {
      if (!doc.exists || !mounted) return;

      final data = doc.data() ?? {};
      final collectorArrived = data['collectorArrived'] == true;
      final status = (data['status'] ?? '').toString().trim().toLowerCase();

      final audited = status == 'completed' ||
          status == 'audited' ||
          status == 'done' ||
          status == 'receipt_saved';

      setState(() {
        _collectorArrivedToMores = collectorArrived;
        _sellTransactionAudited = audited;
      });

      if (!audited) return;

      await _restoreCollectorAvailability();

      if (_sentToDashboard || !mounted) return;
      _sentToDashboard = true;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Transaction completed"),
          duration: Duration(seconds: 1),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 800));

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const CollectorsDashboardPage()),
          (route) => false,
        );
      });
    });
  }

  Future<void> _restoreCollectorAvailability() async {
    final collectorId = _currentUser?.uid;
    if (collectorId == null) return;

    await _db.collection('Users').doc(collectorId).set({
      "isOnline": true,
      "availabilityStatus": "available",
      "isAvailableForHousehold": true,
      "activeMoresSellRequestId": FieldValue.delete(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _setupFixedDestinationMode() async {
    final destination = widget.fixedDestination;
    if (destination == null) return;

    if (!mounted) return;
    setState(() {
      _pickupLatLng = destination;
      _collectorLatLng = _myLatLng;
      _status = "ongoing";
      _street = widget.destinationAddress;
      _subdivision = "";
      _landmark = "";
      _phoneNumber = "";
      _loading = false;
    });

    if (_collectorLatLng != null && _pickupLatLng != null) {
      await _buildCollectorRouteToPickup(
        collectorLatLng: _collectorLatLng!,
        pickupLatLng: _pickupLatLng!,
      );
    }

    await _fitMap();
    _initialFitDone = true;
  }

  Future<void> _onChatPressed() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Chat coming soon.")),
    );
  }

  Future<void> _onArrivedPressed() async {
    if (_markingArrived || _collectorArrivedToMores || _sellTransactionAudited) {
      return;
    }

    if (widget.sellRequestId == null || widget.sellRequestId!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing sell request ID.")),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          "Confirm Arrival",
          style: TextStyle(color: _textPrimary),
        ),
        content: const Text(
          "Are you now at Mores Scrap?\n\n"
          "Tap Confirm only if you have already arrived. "
          "After confirming, this button will be locked until "
          "Mores Scrap saves and audits the transaction.",
          style: TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: _bg,
            ),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _markingArrived = true);

    try {
      await _sellRequestDoc.update({
        "status": "arrived",
        "collectorArrived": true,
        "updatedAt": FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      setState(() {
        _collectorArrivedToMores = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Arrival confirmed. Please wait for Mores Scrap to save and audit the transaction.",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to mark arrived: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => _markingArrived = false);
      }
    }
  }

  Future<void> _onCancelPressed() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          "Cancel trip?",
          style: TextStyle(color: _textPrimary),
        ),
        content: const Text(
          "Are you sure you want to cancel this trip to Mores Scrap?",
          style: TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
            ),
            child: const Text("Yes, cancel"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    if (widget.sellRequestId == null || widget.sellRequestId!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing sell request ID.")),
      );
      return;
    }

    try {
      await _sellRequestDoc.update({
        "status": "cancelled",
        "updatedAt": FieldValue.serverTimestamp(),
      });

      await _restoreCollectorAvailability();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Trip cancelled.")),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to cancel trip: $e")),
      );
    }
  }

  Future<BitmapDescriptor> _iconToMarker({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required Color borderColor,
    double size = 112,
    double iconSize = 54,
    String? label,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final painter = _TrackingMarkerPainter(
      icon: icon,
      iconColor: iconColor,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      size: size,
      iconSize: iconSize,
      label: label,
    );

    painter.paint(canvas, Size(size, size));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _loadMarkerIcons() async {
    try {
      _collectorIcon = await _iconToMarker(
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

      _moresMarkerIcon = await _iconToMarker(
        icon: Icons.storefront_rounded,
        iconColor: Colors.white,
        backgroundColor: const Color(0xFF16A34A),
        borderColor: Colors.white.withOpacity(0.20),
        size: 260,
        iconSize: 52,
        label: "Mores Scrap",
      );

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Failed to build marker icons: $e");
    }
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    await controller.setMapStyle(_darkMapStyle);

    if (_pickupLatLng != null && !_initialFitDone) {
      await _fitMap();
    }
  }

  void _listenToRequest() {
    _requestSub?.cancel();

    if (!_hasValidRequestId) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    _requestSub = _requestDoc.snapshots().listen((doc) async {
      if (!doc.exists) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final data = doc.data() ?? {};
      _goToDashboardIfTransactionEnded(data);

      final pickupGp = data['pickupLocation'];
      final collectorGp =
          data['collectorLiveLocation'] ?? data['collectorLocation'];
      final isLive = data['sharingLiveLocation'] == true;

      final headingRaw = data['collectorHeading'];
      final heading = headingRaw is num ? headingRaw.toDouble() : 0.0;

      LatLng? pickup;
      LatLng? collector;

      if (pickupGp is GeoPoint) {
        pickup = LatLng(pickupGp.latitude, pickupGp.longitude);
      }
      if (collectorGp is GeoPoint) {
        collector = LatLng(collectorGp.latitude, collectorGp.longitude);
      }

      final previousCollector = _collectorLatLng;
      final previousPickup = _pickupLatLng;
      final previousCollectorWasNull = _collectorLatLng == null;
      final oldHeading = _collectorHeading;

      if (!mounted) return;
      setState(() {
        _pickupLatLng = pickup;
        _isCollectorLive = isLive;
        _collectorName = (data['collectorName'] ?? 'Collector').toString();
        _status = (data['status'] ?? '').toString().trim().toLowerCase();
        _street = (data['street'] ?? '').toString();
        _subdivision = (data['subdivision'] ?? '').toString();
        _landmark = (data['landmark'] ?? '').toString();
        _phoneNumber = (data['phoneNumber'] ?? '').toString();
        _loading = false;
      });

      if (collector != null) {
        if (previousCollector == null) {
          setState(() {
            _collectorLatLng = collector;
            _collectorHeading = heading;
          });
        } else if (previousCollector.latitude != collector.latitude ||
            previousCollector.longitude != collector.longitude ||
            oldHeading != heading) {
          _animateCollectorMarker(
            from: previousCollector,
            to: collector,
            fromHeading: oldHeading,
            toHeading: heading,
          );
        }
      } else {
        setState(() {
          _collectorLatLng = null;
        });
      }

      final activeCollector = collector ?? _collectorLatLng;

      final collectorChanged =
          previousCollector?.latitude != activeCollector?.latitude ||
              previousCollector?.longitude != activeCollector?.longitude;

      final pickupChanged = previousPickup?.latitude != _pickupLatLng?.latitude ||
          previousPickup?.longitude != _pickupLatLng?.longitude;

      if (activeCollector != null && _pickupLatLng != null) {
        if (collectorChanged || pickupChanged || _collectorRoutePoints.isEmpty) {
          await _buildCollectorRouteToPickup(
            collectorLatLng: activeCollector,
            pickupLatLng: _pickupLatLng!,
          );
        }
      } else {
        if (!mounted) return;
        setState(() {
          _collectorRoutePoints = [];
          _routeDistanceText = "";
          _routeDurationText = "";
        });
      }

      if (!_initialFitDone && _pickupLatLng != null) {
        if (activeCollector != null || _mapController != null) {
          await _fitMap();
          _initialFitDone = true;
        }
      } else if (previousCollectorWasNull && activeCollector != null) {
        await _fitMap();
      }
    });
  }

  Future<void> _buildCollectorRouteToPickup({
    required LatLng collectorLatLng,
    required LatLng pickupLatLng,
  }) async {
    try {
      final callable = _functions.httpsCallable('getDirections');
      final result = await callable.call({
        'origin': '${collectorLatLng.latitude},${collectorLatLng.longitude}',
        'destination': '${pickupLatLng.latitude},${pickupLatLng.longitude}',
        'mode': 'driving',
      });

      final data = result.data;
      if (data is! Map) return;

      final distanceText = (data['distanceText'] ?? '').toString();
      final durationText = (data['durationText'] ?? '').toString();
      final points = data['points'] as String?;

      if (points == null || points.isEmpty) {
        if (!mounted) return;
        setState(() {
          _collectorRoutePoints = [];
          _routeDistanceText = "";
          _routeDurationText = "";
        });
        return;
      }

      final decoded = _decodePolyline(points);

      if (!mounted) return;
      setState(() {
        _collectorRoutePoints = decoded;
        _routeDistanceText = distanceText;
        _routeDurationText = durationText;
      });
    } catch (e) {
      debugPrint("collector route failed: $e");
      if (!mounted) return;
      setState(() {
        _collectorRoutePoints = [];
        _routeDistanceText = "";
        _routeDurationText = "";
      });
    }
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

  Future<void> _initMyLocation() async {
    final ok = await _ensureLocationPermission();
    if (!ok) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      if (!mounted) return;
      setState(() {
        _myLatLng = LatLng(pos.latitude, pos.longitude);
      });
    } catch (e) {
      debugPrint("current location error: $e");
    }
  }

  Future<void> _fitMap() async {
    if (_mapController == null || _pickupLatLng == null) return;

    if (_collectorLatLng == null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_pickupLatLng!, 16),
      );
      return;
    }

    final pickup = _pickupLatLng!;
    final collector = _collectorLatLng!;

    final south = math.min(pickup.latitude, collector.latitude);
    final north = math.max(pickup.latitude, collector.latitude);
    final west = math.min(pickup.longitude, collector.longitude);
    final east = math.max(pickup.longitude, collector.longitude);

    final bounds = LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 90),
    );
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

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    if (_pickupLatLng != null) {
      markers.add(
        Marker(
          markerId: MarkerId(
            _isSellTracking
                ? "mores_${_moresMarkerIcon?.hashCode ?? 0}"
                : "pickup",
          ),
          position: _pickupLatLng!,
          anchor: _isSellTracking
              ? const Offset(0.20, 0.52)
              : const Offset(0.5, 0.55),
          icon: _isSellTracking
              ? (_moresMarkerIcon ??
                  BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen,
                  ))
              : (_householdMarkerIcon ?? BitmapDescriptor.defaultMarker),
        ),
      );
    }

    if (_collectorLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId("collector"),
          position: _collectorLatLng!,
          rotation: _collectorHeading,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          icon: _collectorIcon ?? BitmapDescriptor.defaultMarker,
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_collectorRoutePoints.isEmpty) return <Polyline>{};

    return {
      Polyline(
        polylineId: const PolylineId("collector_route"),
        points: _collectorRoutePoints,
        width: 5,
        color: _blue,
      ),
    };
  }

  String get _statusLabel {
    if (_isFixedDestinationMode) {
      return "Heading to ${widget.destinationTitle}";
    }

    switch (_status) {
      case 'pending':
        return 'Waiting for collector';
      case 'scheduled':
        return 'Pickup scheduled';
      case 'accepted':
        return 'Collector accepted your request';
      case 'ongoing':
        return 'Collector is on the way';
      case 'arrived':
        return 'Collector arrived';
      case 'completed':
        return 'Pickup completed';
      case 'cancelled':
      case 'canceled':
        return 'Pickup cancelled';
      case 'declined':
        return 'Pickup declined';
      default:
        return _status.isEmpty ? 'Tracking pickup' : _status.toUpperCase();
    }
  }

  Color get _statusColor {
    switch (_status) {
      case 'accepted':
      case 'ongoing':
      case 'completed':
        return _accent;
      case 'arrived':
        return _blue;
      case 'pending':
      case 'scheduled':
        return _warning;
      case 'cancelled':
      case 'canceled':
      case 'declined':
        return _danger;
      default:
        return _textSecondary;
    }
  }

  IconData get _statusIcon {
    switch (_status) {
      case 'accepted':
      case 'ongoing':
        return Icons.local_shipping_outlined;
      case 'arrived':
        return Icons.location_on_outlined;
      case 'completed':
        return Icons.check_circle_outline;
      case 'pending':
      case 'scheduled':
        return Icons.schedule_outlined;
      case 'cancelled':
      case 'canceled':
      case 'declined':
        return Icons.cancel_outlined;
      default:
        return Icons.route_outlined;
    }
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
    double radius = 24,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _sheet.o(0.92),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: _border),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _topBar() {
    return Positioned(
      top: 56,
      left: 16,
      right: 16,
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _surface.o(0.96),
                shape: BoxShape.circle,
                border: Border.all(color: _border),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: _textPrimary,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _glassCard(
              radius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_searching,
                    color: _accent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _topBarTitle,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (_collectorLatLng != null)
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: _accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Icon(icon, color: _textSecondary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? _textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPanel() {
    return DraggableScrollableSheet(
      initialChildSize: 0.33,
      minChildSize: 0.20,
      maxChildSize: 0.62,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: _sheet.o(0.97),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(34)),
                border: const Border(top: BorderSide(color: _border)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        color: _textMuted.o(0.40),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: _surfaceAlt,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _border),
                        ),
                        child: Icon(_statusIcon, color: _statusColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _statusLabel,
                              style: const TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _liveStatusText,
                              style: const TextStyle(
                                color: _textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _infoTile(
                    icon: Icons.place_outlined,
                    label: _locationSectionLabel,
                    value: _locationSectionValue,
                    valueColor: _textPrimary,
                  ),
                  if (_landmark.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _infoTile(
                      icon: Icons.landscape_outlined,
                      label: "LANDMARK",
                      value: _landmark,
                    ),
                  ],
                  if (_phoneNumber.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _infoTile(
                      icon: Icons.phone_outlined,
                      label: "PHONE",
                      value: _phoneNumber,
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _infoTile(
                          icon: Icons.route_outlined,
                          label: "DISTANCE",
                          value: _routeDistanceText.isEmpty
                              ? "Calculating..."
                              : _routeDistanceText,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _infoTile(
                          icon: Icons.schedule_outlined,
                          label: "ETA",
                          value: _routeDurationText.isEmpty
                              ? "Calculating..."
                              : _routeDurationText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _fitMap,
                      icon: const Icon(Icons.fit_screen_outlined),
                      label: const Text("Fit Map"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textPrimary,
                        side: const BorderSide(color: _border),
                        backgroundColor: _surface,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  if (_isSellTracking) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (widget.showChatButton)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _onChatPressed,
                              icon: const Icon(Icons.chat_bubble_outline_rounded),
                              label: const Text("Chat"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _textPrimary,
                                side: const BorderSide(color: _border),
                                backgroundColor: _surface,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        if (widget.showChatButton && widget.showCancelButton)
                          const SizedBox(width: 12),
                        if (widget.showCancelButton)
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _onCancelPressed,
                              icon: const Icon(Icons.close_rounded),
                              label: const Text("Cancel"),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _danger,
                                side: const BorderSide(color: _border),
                                backgroundColor: _surface,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (widget.showArrivedButton) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_markingArrived ||
                                  _collectorArrivedToMores ||
                                  _sellTransactionAudited)
                              ? null
                              : _onArrivedPressed,
                          icon: const Icon(Icons.location_on_outlined),
                          label: Text(
                            _markingArrived
                                ? "CONFIRMING..."
                                : _collectorArrivedToMores
                                    ? "ARRIVED"
                                    : "YOU HAVE ARRIVED",
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            disabledBackgroundColor: _surfaceAlt,
                            disabledForegroundColor: _textSecondary,
                            foregroundColor: _bg,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _sellTransactionAudited
                            ? "Transaction completed and audited by Mores Scrap."
                            : _collectorArrivedToMores
                                ? "You have marked yourself as arrived. Waiting for Mores Scrap to save and audit the transaction."
                                : "Press this only when you are already at Mores Scrap.",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text("Done"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: _bg,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _loadingOverlay() {
    if (!_loading) return const SizedBox.shrink();

    return Container(
      color: _bg,
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = _pickupLatLng ?? const LatLng(14.198630, 121.117270);

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: initialTarget,
                zoom: 15,
              ),
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: false,
              indoorViewEnabled: false,
              trafficEnabled: false,
              tiltGesturesEnabled: false,
              rotateGesturesEnabled: true,
              compassEnabled: false,
              markers: _buildMarkers(),
              polylines: _buildPolylines(),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 110,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _bg.o(0.94),
                    _bg.o(0.14),
                  ],
                ),
              ),
            ),
          ),
          _topBar(),
          _statusPanel(),
          _loadingOverlay(),
        ],
      ),
    );
  }
}

class _TrackingMarkerPainter {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final double size;
  final double iconSize;
  final String? label;

  _TrackingMarkerPainter({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.size,
    required this.iconSize,
    this.label,
  });

  void paint(Canvas canvas, Size s) {
    final hasLabel = label != null && label!.trim().isNotEmpty;

    if (!hasLabel) {
      final center = Offset(s.width / 2, s.height / 2);
      final radius = s.width / 2.9;

      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(center.translate(0, 4), radius, shadowPaint);

      final fillPaint = Paint()..color = backgroundColor;
      canvas.drawCircle(center, radius, fillPaint);

      final borderPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      canvas.drawCircle(center, radius, borderPaint);

      final iconPainter = TextPainter(textDirection: TextDirection.ltr);
      iconPainter.text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: iconSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: iconColor,
        ),
      );
      iconPainter.layout();

      final iconOffset = Offset(
        center.dx - iconPainter.width / 2,
        center.dy - iconPainter.height / 2,
      );
      iconPainter.paint(canvas, iconOffset);
      return;
    }

    final markerCenter = Offset(s.width * 0.20, s.height * 0.52);
    final markerRadius = s.width * 0.15;

    final markerShadow = Paint()
      ..color = Colors.black.withOpacity(0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(markerCenter.translate(0, 4), markerRadius, markerShadow);

    final markerFill = Paint()..color = backgroundColor;
    canvas.drawCircle(markerCenter, markerRadius, markerFill);

    final markerBorder = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(markerCenter, markerRadius, markerBorder);

    final iconPainter = TextPainter(textDirection: TextDirection.ltr);
    iconPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: iconSize,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: iconColor,
      ),
    );
    iconPainter.layout();

    final iconOffset = Offset(
      markerCenter.dx - iconPainter.width / 2,
      markerCenter.dy - iconPainter.height / 2,
    );
    iconPainter.paint(canvas, iconOffset);

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );

    textPainter.text = TextSpan(
      text: label!,
      style: TextStyle(
        color: const Color(0xFFE2E8F0),
        fontSize: s.width * 0.085,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    );
    textPainter.layout();

    final shadowPainter = TextPainter(textDirection: TextDirection.ltr);
    shadowPainter.text = TextSpan(
      text: label!,
      style: TextStyle(
        color: Colors.black.withOpacity(0.6),
        fontSize: s.width * 0.085,
        fontWeight: FontWeight.w700,
      ),
    );
    shadowPainter.layout();

    final textOffset = Offset(
      markerCenter.dx + markerRadius + 10,
      markerCenter.dy - textPainter.height / 2,
    );

    shadowPainter.paint(canvas, textOffset.translate(1.5, 1.5));
    textPainter.paint(canvas, textOffset);
  }
}
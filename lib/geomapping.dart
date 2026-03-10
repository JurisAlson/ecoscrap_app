import 'dart:async';
import 'dart:ui';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'pickup_request_page.dart';
import 'package:firebase_core/firebase_core.dart';


extension OpacityFix on Color {
  Color o(double opacity) =>
      withValues(alpha: ((opacity * 255).clamp(0, 255)).toDouble());
}

/// Trip stages (kept for future extensibility)
enum TripStage { planning, pickup, delivering }

class GeoMappingPage extends StatefulWidget {
  const GeoMappingPage({super.key});

  @override
  State<GeoMappingPage> createState() => _GeoMappingPageState();
}

class _GeoMappingPageState extends State<GeoMappingPage> {
  // ===== Theme / Colors =====
  static const Color _bg = Color(0xFF0B1220);
  static const Color _sheet = Color(0xFF121C2E);
  static const Color _surface = Color(0xFF162235);
  static const Color _surfaceAlt = Color(0xFF1B2A40);
  static const Color _border = Color(0xFF26364F);
  static const Color _accent = Color(0xFF10B981);
  static const Color _teal = Color(0xFF1FA9A7);
  static const Color _blue = Color(0xFF60A5FA);
  

  // Text colors
  static const Color _textPrimary = Color(0xFFE2E8F0);
  static const Color _textSecondary = Color(0xFF94A3B8);
  static const Color _textMuted = Color(0xFF64748B);

  // Time
  late String _timeString;
  late Timer _timer;

  bool _pinMode = false;

  // Map
  GoogleMapController? _mapController;

  // Default camera center (only used before GPS is ready)
  final LatLng _paloAltoCenter = const LatLng(14.18695, 121.11299);

  // ✅ Fixed destination: MORES only
  final LatLng _moresLatLng = const LatLng(14.198630, 121.117270);
  final String _moresName = "Mores Scrap Trading";
  final String _moresSubtitle = "brgy palo alto, Calamba";
  final String _moresJunkshopUid = "07Wi7N8fALh2yqNdt1CQgIYVGE43";

  // Location
  bool _locationReady = false;
  Position? _currentPosition;
  StreamSubscription<Position>? _posSub;

  // Route polyline
  List<LatLng> _routePoints = [];
  String _dirDistanceText = "";
  String _dirDurationText = "";
  int? _dirDurationValueSec;

  String? _activeDropoffRequestId;

    // ===== Collector live tracking =====
  String? _activePickupRequestId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _pickupReqSub;
  

  LatLng? _collectorLatLng;
  String? _collectorName;

  List<LatLng> _collectorRoutePoints = [];

  // Trip stage
  TripStage _tripStage = TripStage.planning;

  bool get _isPickup => _tripStage == TripStage.pickup;
  bool get _isDelivering => _tripStage == TripStage.delivering;

  LatLng get _originLatLng {
    final p = _currentPosition;
    if (p == null) return _paloAltoCenter; // fallback only
    return LatLng(p.latitude, p.longitude);
  }

  LatLng get _destLatLng => _moresLatLng;

  double get _distanceKm {
    final meters = Geolocator.distanceBetween(
      _originLatLng.latitude,
      _originLatLng.longitude,
      _destLatLng.latitude,
      _destLatLng.longitude,
    );
    return meters / 1000.0;
  }

  // ✅ Simple consistent ETA
  int get _etaMinutes {
    final sec = _dirDurationValueSec;
    if (sec != null && sec > 0) {
      final m = (sec / 60).round();
      return m.clamp(3, 999);
    }
    final base = (_distanceKm * 4.0).round();
    return base.clamp(3, 999);
  }

  // Dark map style JSON
  static const String _darkMapStyle = r'''
[
  {"elementType":"geometry","stylers":[{"color":"#0b1220"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8aa0b8"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0b1220"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#2b3445"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#7d93aa"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#0f1a2a"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#162235"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#0b1220"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#93a8bf"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#1f2f48"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#0b1220"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#142033"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#06101c"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#6f879f"}]}
]
''';

  // ----- Available collectors dropdown -----
  String? _selectedCollectorId;
  List<Map<String, String>> _availableCollectors = []; // [{uid,name}]


  // ===== Pickup location selection (Option B simplified) =====
  LatLng? _pinnedPickupLatLng; // null => use GPS
  String _pickupSource = "gps"; // "gps" | "pin"

  static const List<String> _dropoffCancelReasons = [
    "Changed my mind",
    "Going later instead",
    "Wrong destination selected",
    "Travel issue",
    "Too far right now",
    "Other",
  ];

  String _dropoffStatus = ""; // en_route | arrived | cancelled | completed

  LatLng get _effectivePickupLatLng => _pinnedPickupLatLng ?? _originLatLng;

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  Future<void> _buildRouteTo(LatLng dest) async {
    if (_currentPosition == null) {
      if (mounted) setState(() => _routePoints = []);
      return;
    }

    final origin = _originLatLng;
    debugPrint("projectId=${Firebase.app().options.projectId}");

    try {
      final callable = _functions.httpsCallable('getDirections');
      final result = await callable.call({
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${dest.latitude},${dest.longitude}',
        'mode': 'driving',
      });

      final data = result.data;
      if (data is! Map) return;

      final points = data['points'] as String?;
      final distText = (data['distanceText'] ?? '').toString();
      final durText = (data['durationText'] ?? '').toString();
      final durVal = data['durationValueSec'];

      if (points == null || points.isEmpty) {
        if (!mounted) return;
        setState(() => _routePoints = []);
        return;
      }

      final decoded = _decodePolyline(points);

      if (!mounted) return;
      setState(() {
        _routePoints = decoded;
        _dirDistanceText = distText;
        _dirDurationText = durText;
        _dirDurationValueSec = durVal is int
            ? durVal
            : (durVal is num ? durVal.toInt() : _dirDurationValueSec);
      });

      debugPrint("Route loaded: $distText • $durText");
    } on FirebaseFunctionsException catch (e) {
      debugPrint("❌ getDirections failed: ${e.code} ${e.message}");
      if (!mounted) return;
      setState(() => _routePoints = []);
    } catch (e) {
      debugPrint("❌ getDirections crashed: $e");
      if (!mounted) return;
      setState(() => _routePoints = []);
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint("✅ GeoMappingPage initState called");

    _timeString = _formatTime(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _timeString = _formatTime(DateTime.now()));
    });

    _initLocation();
    _listenAvailableCollectors();
  }

  @override
  void dispose() {
    _timer.cancel();
    _posSub?.cancel();
    _pickupReqSub?.cancel();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  void _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    await _mapController!.setMapStyle(_darkMapStyle);
  }

  Future<void> _initLocation() async {
    final ok = await _ensureLocationPermission();
    if (!ok) {
      if (!mounted) return;
      setState(() => _locationReady = false);
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    if (!mounted) return;
    setState(() {
      _currentPosition = pos;
      _locationReady = true;
    });

      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5,
      ),
    ).listen((p) async {
      if (!mounted) return;
      setState(() => _currentPosition = p);

      if (_isDelivering) {
        await _buildRouteTo(_moresLatLng);
      }
    });

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15),
    );
    await _restoreActiveDropoffIfAny();
  }

  Widget _glass({
    required Widget child,
    double blur = 12,
    double opacity = 0.88,
    double radius = 24,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _sheet.o(opacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: _border),
          ),
          child: child,
        ),
      ),
    );
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) _snack("Please enable Location Services.");
      return false;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (mounted) _snack("Location permission is required.");
      return false;
    }

    return true;
  }

  void _snack(String msg, {Color? bg}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: bg ?? _surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _border),
        ),
      ),
    );
  }

  void _listenAvailableCollectors() {
    FirebaseFirestore.instance
        .collection('Users')
        .where('Roles', isEqualTo: 'collector')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      final list = <Map<String, String>>[];
      debugPrint("✅ collectors found: ${snap.docs.length}");

      for (final d in snap.docs) {
        final data = d.data();
        final uid = d.id;
        final name =
            (data['Name'] ?? data['displayName'] ?? "Collector").toString();

        list.add({'uid': uid, 'name': name});
      }

      if (!mounted) return;
      setState(() {
        _availableCollectors = list;

        final stillThere = _selectedCollectorId != null &&
            _availableCollectors.any((c) => c['uid'] == _selectedCollectorId);

        if (!stillThere) {
          _selectedCollectorId = null;
        }
      });
    });
  }

    void _listenToActivePickupRequest(String requestId) {
    _pickupReqSub?.cancel();

    _pickupReqSub = FirebaseFirestore.instance
        .collection('requests')
        .doc(requestId)
        .snapshots()
        .listen((doc) async {
      if (!doc.exists) return;

      final data = doc.data() ?? {};
      final collectorName = (data['collectorName'] ?? 'Collector').toString();

      final gp = data['collectorLocation'];
      LatLng? liveCollector;

      if (gp is GeoPoint) {
        liveCollector = LatLng(gp.latitude, gp.longitude);
      }

      if (!mounted) return;

      final shouldFit = _collectorLatLng == null && liveCollector != null;

      setState(() {
        _collectorName = collectorName;
        _collectorLatLng = liveCollector;
      });

      if (liveCollector != null) {
        await _buildCollectorRouteToPickup(liveCollector);
      }

      if (shouldFit) {
        await _fitCollectorAndPickup();
      }
    });
  }
  

  void _onMapTap(LatLng tapped) {
    if (!_pinMode) return;

    setState(() {
      _pinnedPickupLatLng = tapped;
      _pickupSource = "pin";
    });

    _snack("Pickup location pinned.", bg: _surface);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(tapped, 16));
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // ✅ Always show Mores marker
    markers.add(
      Marker(
        markerId: const MarkerId("mores_dropoff"),
        position: _moresLatLng,
        infoWindow: InfoWindow(
          title: _moresName,
          snippet: _moresSubtitle,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );

    // ✅ User location marker
    final p = _currentPosition;
    if (p != null) {
      markers.add(
        Marker(
          markerId: const MarkerId("user_pos"),
          position: LatLng(p.latitude, p.longitude),
          infoWindow: const InfoWindow(title: "You"),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }

    // ✅ Pickup pin marker (if user pinned a different pickup point)
    if (_pinnedPickupLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId("pickup_pin"),
          position: _pinnedPickupLatLng!,
          infoWindow: const InfoWindow(
            title: "Pickup Location",
            snippet: "Pinned by household",
          ),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ),
      );
    }
        // ✅ Collector live location marker
    if (_collectorLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId("collector_live"),
          position: _collectorLatLng!,
          infoWindow: InfoWindow(
            title: _collectorName ?? "Collector",
            snippet: "Approaching pickup location",
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueViolet,
          ),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    final polylines = <Polyline>{};

    if (_routePoints.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId("route"),
          points: _routePoints,
          width: 6,
          color: _teal,
        ),
      );
    }

    if (_collectorRoutePoints.isNotEmpty) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId("collector_route"),
          points: _collectorRoutePoints,
          width: 5,
          color: _blue,
        ),
      );
    }

    return polylines;
  }

  Future<void> _restoreActiveDropoffIfAny() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'drop-off')
        .where('householdId', isEqualTo: user.uid)
        .where('active', isEqualTo: true)
        .limit(5)
        .get();

    if (snap.docs.isEmpty) return;

    final docs = snap.docs.where((d) {
      final status = (d.data()['status'] ?? '').toString().trim().toLowerCase();
      return status == 'en_route';
    }).toList();

    if (docs.isEmpty) return;

    final doc = docs.first;
    final data = doc.data();

    final status = (data['status'] ?? '').toString().trim().toLowerCase();

    if (!mounted) return;

    setState(() {
      _activeDropoffRequestId = doc.id;
      _tripStage = TripStage.delivering;
      _dropoffStatus = status;
      _activePickupRequestId = null;
      _collectorLatLng = null;
      _collectorName = null;
      _collectorRoutePoints = [];
    });

    await _buildRouteTo(_moresLatLng);
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_moresLatLng, 16),
    );
  }

  Future<void> _startDirectionsToMores() async {
    _pickupReqSub?.cancel();

    setState(() {
      _pinMode = false;
      _tripStage = TripStage.delivering;
      _collectorLatLng = null;
      _collectorName = null;
      _collectorRoutePoints = [];
      _activePickupRequestId = null;
      _dropoffStatus = "en_route";
    });

    final dropoffId = await _createDropoffRequest();

    if (!mounted) return;

    setState(() {
      _activeDropoffRequestId = dropoffId;
    });

    await _buildRouteTo(_moresLatLng);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_moresLatLng, 16));
    _snack("Showing directions to $_moresName.", bg: _surface);
  }

  Future<String?> _findExistingActiveDropoffRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final snap = await FirebaseFirestore.instance
        .collection('requests')
        .where('type', isEqualTo: 'drop-off')
        .where('householdId', isEqualTo: user.uid)
        .where('active', isEqualTo: true)
        .limit(5)
        .get();

    for (final doc in snap.docs) {
      final status = (doc.data()['status'] ?? '').toString().trim().toLowerCase();
      if (status == 'en_route') return doc.id;
    }

    return null;
  }

  Future<void> _buildCollectorRouteToPickup(LatLng collectorLatLng) async {
    try {
      final callable = _functions.httpsCallable('getDirections');
      final result = await callable.call({
        'origin': '${collectorLatLng.latitude},${collectorLatLng.longitude}',
        'destination':
            '${_effectivePickupLatLng.latitude},${_effectivePickupLatLng.longitude}',
        'mode': 'driving',
      });

      final data = result.data;
      if (data is! Map) return;

      final points = data['points'] as String?;
      if (points == null || points.isEmpty) {
        if (!mounted) return;
        setState(() => _collectorRoutePoints = []);
        return;
      }

      final decoded = _decodePolyline(points);

      if (!mounted) return;
      setState(() {
        _collectorRoutePoints = decoded;
      });
    } catch (e) {
      debugPrint("❌ collector route failed: $e");
      if (!mounted) return;
      setState(() => _collectorRoutePoints = []);
    }
  }

  // =========================
  // DROP-OFF
  // =========================

  Future<String?> _createDropoffRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final actorName =
        await _getUserName(user.uid, fallback: user.email ?? "User");

    final doc = await FirebaseFirestore.instance.collection('requests').add({
      'type': 'drop-off',
      'active': true,
      'status': 'en_route',
      'actorId': user.uid,
      'actorName': actorName,
      'householdId': user.uid,
      'householdName': actorName,
      'junkshopId': _moresJunkshopUid,
      'junkshopName': _moresName,
      'destinationLocation':
          GeoPoint(_moresLatLng.latitude, _moresLatLng.longitude),
      'originLocation':
          GeoPoint(_originLatLng.latitude, _originLatLng.longitude),
      'distanceKm': double.parse(_distanceKm.toStringAsFixed(2)),
      'etaMinutes': _etaMinutes,
      'arrived': false,
      'arrivedAt': null,
      'completedAt': null,
      'cancelledAt': null,
      'cancelReason': null,
      'receiptFilled': false,
      'readByJunkshop': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return doc.id;
  }

  Future<void> _markDropoffArrived() async {
    final requestId = _activeDropoffRequestId;
    if (requestId == null) return;

    try {
      final snap = await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .get();
      
      debugPrint("ARRIVED requestId=$requestId");
      debugPrint("ARRIVED doc exists=${snap.exists}");
      debugPrint("ARRIVED doc data=${snap.data()}");
      debugPrint("ARRIVED uid=${FirebaseAuth.instance.currentUser?.uid}");

      await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .update({
        'status': 'arrived',
        'arrived': true,
        'arrivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'readByJunkshop': false,
        'testPing': true,
        'debugTouch': FieldValue.serverTimestamp(),
      });
      
      if (!mounted) return;
      setState(() => _dropoffStatus = "arrived");
      _snack("Marked as arrived at $_moresName.", bg: _accent);
    } catch (e) {
      debugPrint("❌ mark arrived failed: $e");
      if (!mounted) return;
      _snack("Failed to mark arrival.", bg: Colors.redAccent);
    }
  }

  Future<void> _focusDropoffRoute() async {
    if (_mapController == null) return;

    if (_currentPosition == null) {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(_moresLatLng, 16),
      );
      return;
    }

    final me = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

    final south = me.latitude < _moresLatLng.latitude ? me.latitude : _moresLatLng.latitude;
    final north = me.latitude > _moresLatLng.latitude ? me.latitude : _moresLatLng.latitude;
    final west = me.longitude < _moresLatLng.longitude ? me.longitude : _moresLatLng.longitude;
    final east = me.longitude > _moresLatLng.longitude ? me.longitude : _moresLatLng.longitude;

    final bounds = LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 90),
    );
  }

  Future<String?> _pickDropoffCancelReason() async {
    String selected = _dropoffCancelReasons.first;

    return showDialog<String>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setD) {
            return AlertDialog(
              backgroundColor: _sheet,
              title: const Text(
                "Why do you want to cancel this transaction?",
                style: TextStyle(color: _textPrimary),
              ),
              content: DropdownButtonFormField<String>(
                value: selected,
                dropdownColor: _surface,
                style: const TextStyle(color: _textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: _surface,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _accent),
                  ),
                ),
                items: _dropoffCancelReasons
                    .map(
                      (r) => DropdownMenuItem<String>(
                        value: r,
                        child: Text(
                          r,
                          style: const TextStyle(color: _textPrimary),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setD(() => selected = v);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text(
                    "Back",
                    style: TextStyle(color: _textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, selected),
                  child: const Text(
                    "Submit",
                    style: TextStyle(color: _accent),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openPickupFlowPage() async {
    if (_availableCollectors.isEmpty) {
      _snack("No available collectors right now.", bg: _surface);
      return;
    }

    if (!_locationReady || _currentPosition == null) {
      _snack("Still getting your location. Please wait...", bg: _surface);
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PickupRequestPage(
          pickupLatLng: _effectivePickupLatLng,
          pickupSource: _pickupSource,
          distanceKm: _distanceKm,
          etaMinutes: _etaMinutes,
          moresName: _moresName,
          moresLatLng: _moresLatLng,
          availableCollectors: _availableCollectors,
        ),
      ),
    );

    if (result is String && result.isNotEmpty && mounted) {
      setState(() {
        _activePickupRequestId = result;
        _tripStage = TripStage.pickup;
        _activeDropoffRequestId = null;
        _dropoffStatus = "";
        _routePoints = [];
        _dirDistanceText = "";
        _dirDurationText = "";
        _dirDurationValueSec = null;
      });

      _listenToActivePickupRequest(result);
      _snack("Pickup request sent! Tracking collector...", bg: _accent);
    }
  }
  Future<void> _fitCollectorAndPickup() async {
    if (_collectorLatLng == null || _mapController == null) return;

    final pickup = _effectivePickupLatLng;
    final collector = _collectorLatLng!;

    final south = collector.latitude < pickup.latitude
        ? collector.latitude
        : pickup.latitude;
    final north = collector.latitude > pickup.latitude
        ? collector.latitude
        : pickup.latitude;
    final west = collector.longitude < pickup.longitude
        ? collector.longitude
        : pickup.longitude;
    final east = collector.longitude > pickup.longitude
        ? collector.longitude
        : pickup.longitude;

    final bounds = LatLngBounds(
      southwest: LatLng(south, west),
      northeast: LatLng(north, east),
    );

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80),
    );
  }

  Future<String> _getUserName(String uid, {String fallback = "Unknown"}) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      final data = doc.data() ?? {};
      final name = (data['Name'] ?? data['displayName'] ?? data['name'] ?? '')
          .toString()
          .trim();
      if (name.isNotEmpty) return name;

      final email = (data['email'] ?? '').toString().trim();
      if (email.isNotEmpty) return email;

      return fallback;
    } catch (_) {
      return fallback;
    }
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
  
  Future<void> _cancelDropoff() async {
    final requestId = _activeDropoffRequestId;
    if (requestId == null) return;

    final reason = await _pickDropoffCancelReason();
    if (reason == null || reason.trim().isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .update({
        'active': false,
        'status': 'cancelled',
        'cancelReason': reason.trim(),
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'readByJunkshop': false,
      });
      debugPrint("cancel requestId: $requestId");

      if (!mounted) return;
      setState(() {
        _tripStage = TripStage.planning;
        _activeDropoffRequestId = null;
        _dropoffStatus = "cancelled";
        _routePoints = [];
        _dirDistanceText = "";
        _dirDurationText = "";
        _dirDurationValueSec = null;
      });

      _snack("Drop-off cancelled.", bg: _surface);
    } catch (e) {
      debugPrint("❌ cancel dropoff failed: $e");
      if (!mounted) return;
      _snack("Failed to cancel drop-off.", bg: Colors.redAccent);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition:
                  CameraPosition(target: _paloAltoCenter, zoom: 14),
              myLocationEnabled: _locationReady,
              myLocationButtonEnabled: _locationReady,
              markers: _buildMarkers(),
              polylines: _buildPolylines(),
              onTap: _onMapTap,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              buildingsEnabled: false,
              indoorViewEnabled: false,
              trafficEnabled: false,
              tiltGesturesEnabled: false,
              rotateGesturesEnabled: true,
              compassEnabled: false,
            ),
          ),

          // Top status bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _bg.o(0.92),
                    _bg.o(0.18),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _timeString,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: _textPrimary,
                    ),
                  ),
                  const Row(
                    children: [
                      Icon(
                        Icons.signal_cellular_alt,
                        size: 14,
                        color: _textPrimary,
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.wifi, size: 14, color: _textPrimary),
                      SizedBox(width: 6),
                      Icon(
                        Icons.battery_full,
                        size: 14,
                        color: _textPrimary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Top bar
          Positioned(
            top: 62,
            left: 20,
            right: 20,
            child: Row(
              children: [
                _circularButton(
                  Icons.arrow_back,
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.pop(context);
                    } else {
                      _snack("No screen to go back to.", bg: _surface);
                    }
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: _glass(
                      radius: 16,
                      blur: 12,
                      opacity: 0.92,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.store_mall_directory,
                            size: 18,
                            color: _accent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _moresName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Positioned(
            top: 110,
            right: 16,
            bottom: 220,
            child: Column(
              children: [
                FloatingActionButton(
                  heroTag: "pinMode",
                  mini: true,
                  backgroundColor: _pinMode ? _accent : _surface,
                  elevation: 0,
                  onPressed: () {
                    setState(() => _pinMode = !_pinMode);
                    _snack(
                      _pinMode
                          ? "Pin mode ON: tap map to pin pickup."
                          : "Pin mode OFF.",
                      bg: _surface,
                    );
                  },
                  child: const Icon(Icons.push_pin_outlined, color: _textPrimary),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: "goMe",
                  mini: true,
                  backgroundColor: _surface,
                  elevation: 0,
                  onPressed: () {
                    if (_currentPosition == null) return;
                    final p = _currentPosition!;
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLngZoom(
                        LatLng(p.latitude, p.longitude),
                        16,
                      ),
                    );
                  },
                  child: const Icon(Icons.my_location, color: _textPrimary),
                ),
              ],
            ),
          ),

          // Bottom sheet
          DraggableScrollableSheet(
            initialChildSize: 0.40,
            minChildSize: 0.22,
            maxChildSize: 0.75,
            builder: (context, scrollController) {
              return ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(40)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    decoration: BoxDecoration(
                      color: _sheet.o(0.96),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(40)),
                      border: const Border(
                        top: BorderSide(color: _border),
                      ),
                    ),
                    child: ListView(
                      controller: scrollController,
                      children: [
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: _textMuted.o(0.45),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        Text(
                          _moresName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _moresSubtitle,
                          style: const TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),

                        const SizedBox(height: 14),

                        // Location summary
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: _border),
                          ),
                          child: Row(
                            children: [
                              Column(
                                children: [
                                  const Icon(
                                    Icons.radio_button_checked,
                                    color: _blue,
                                    size: 20,
                                  ),
                                  Container(
                                    width: 1,
                                    height: 30,
                                    color: _blue.o(0.35),
                                  ),
                                  const Icon(
                                    Icons.location_on,
                                    color: _accent,
                                    size: 20,
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "YOUR LOCATION",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: _textMuted,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      !_locationReady
                                          ? "Locating..."
                                          : _pinnedPickupLatLng != null
                                              ? "Pinned Location"
                                              : "Current Location",
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: _textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    const Text(
                                      "DESTINATION",
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: _textMuted,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _moresName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: _accent,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Stats / fee
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: _border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _statItem(
                                Icons.access_time,
                                _dirDurationText.isEmpty
                                    ? "$_etaMinutes min"
                                    : _dirDurationText,
                              ),
                              _statDivider(),
                              _statItem(
                                Icons.navigation_outlined,
                                _dirDistanceText.isEmpty
                                    ? "${_distanceKm.toStringAsFixed(1)} km"
                                    : _dirDistanceText,
                              ),
                              _statDivider(),
                              _statItem(Icons.store_mall_directory, "Mores"),
                            ],
                          ),
                        ),

                        if (_isDelivering) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: _border),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _dropoffStatus == "arrived"
                                      ? Icons.check_circle_outline
                                      : Icons.local_shipping_outlined,
                                  color: _dropoffStatus == "arrived"
                                      ? _accent
                                      : _blue,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _dropoffStatus == "arrived"
                                        ? "You have arrived at $_moresName"
                                        : "You are on the way to $_moresName",
                                    style: const TextStyle(
                                      color: _textPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 54,
                                  child: ElevatedButton.icon(
                                    onPressed: _focusDropoffRoute,
                                    icon: const Icon(Icons.center_focus_strong),
                                    label: const Text("FOCUS"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _surfaceAlt,
                                      foregroundColor: _textPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        side: const BorderSide(color: _border),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 54,
                                  
                                  child: ElevatedButton.icon(
                                    
                                    onPressed: _dropoffStatus == "arrived"
                                        ? null
                                        : _markDropoffArrived,
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text("ARRIVED"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _accent,
                                      foregroundColor: _textPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 54,
                                  child: ElevatedButton.icon(
                                    onPressed: _cancelDropoff,
                                    icon: const Icon(Icons.cancel_outlined),
                                    label: const Text("CANCEL"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: _textPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: ElevatedButton.icon(
                                    onPressed: _startDirectionsToMores,
                                    icon: const Icon(Icons.directions),
                                    label: const Text("DROP-OFF"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _surfaceAlt,
                                      foregroundColor: _textPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                        side: const BorderSide(color: _border),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 52,
                                  child: ElevatedButton.icon(
                                    onPressed: _openPickupFlowPage,
                                    icon: const Icon(Icons.local_shipping),
                                    label: const Text("PICKUP"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _accent,
                                      foregroundColor: _textPrimary,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 10),

                        Center(
                          child: Container(
                            width: 120,
                            height: 4,
                            decoration: BoxDecoration(
                              color: _textMuted.o(0.22),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: null,
    );
  }

  // ===== UI bits =====

  Widget _circularButton(IconData icon, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _surface.o(0.96),
          shape: BoxShape.circle,
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: _bg.o(0.40),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: _textPrimary),
      ),
    );
  }

  Widget _statItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: _textSecondary),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: _textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _statDivider() {
    return Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        color: _textMuted.o(0.45),
        shape: BoxShape.circle,
      ),
    );
  }
}
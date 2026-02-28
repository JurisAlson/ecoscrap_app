import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

extension OpacityFix on Color {
  Color o(double opacity) =>
      withValues(alpha: ((opacity * 255).clamp(0, 255)).toDouble());
}

/// Trip stages
enum TripStage { planning, pickup, delivering }

class Destination {
  final String id; // ✅ Firestore docId (junkshopId)
  final String name;
  final String subtitle;
  final LatLng latLng;

  const Destination({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.latLng,
  });
}

class GeoMappingPage extends StatefulWidget {
  const GeoMappingPage({super.key});

  @override
  State<GeoMappingPage> createState() => _GeoMappingPageState();
}

class _GeoMappingPageState extends State<GeoMappingPage> {
  // ===== Theme / Colors (consistent + readable) =====
  static const Color _bg = Color(0xFF0F172A);
  static const Color _sheet = Color(0xFF111928);
  static const Color _accent = Color(0xFF10B981);
  static const Color _teal = Color(0xFF1FA9A7);

  // Text colors (higher contrast)
  static const Color _textPrimary = Color(0xFFF8FAFC);
  static const Color _textSecondary = Color(0xFFCBD5E1);
  static const Color _textMuted = Color(0xFF94A3B8);
  
  // Time
  late String _timeString;
  late Timer _timer;

  // Map
  GoogleMapController? _mapController;

  // Default camera center (only used before GPS is ready)
  final LatLng _paloAltoCenter = const LatLng(14.18695, 121.11299);

  // Fallback destination if Firestore list is empty
  final Destination _moresFallback = const Destination(
  id: "mores",
  name: "Mores Scrap Trading",
  subtitle: "Fixed Drop-off",
  latLng: LatLng(14.198630, 121.117270),
);

  // If user taps map -> pin a custom drop-off
  LatLng? _customDestinationLatLng;

  // Location
  bool _locationReady = false;
  Position? _currentPosition;
  StreamSubscription<Position>? _posSub;

  // Route polyline
  List<LatLng> _routePoints = [];

  // Trip stage
  TripStage _tripStage = TripStage.planning;

  bool get _isPickup => _tripStage == TripStage.pickup;
  bool get _isDelivering => _tripStage == TripStage.delivering;

  // Earnings model (demo)
  double get _ratePerKm => 12.0;

  // ----- Junkshops from Firestore -----
  Destination? _selectedJunkshop;
  final List<Destination> _junkshops = [];

  // ----- Available collectors dropdown -----
  String? _selectedCollectorId;
  String? _selectedCollectorName;
  List<Map<String, String>> _availableCollectors = []; // [{uid,name}]

  LatLng get _originLatLng {
    final p = _currentPosition;
    if (p == null) return _paloAltoCenter; // fallback only
    return LatLng(p.latitude, p.longitude);
  }

  LatLng get _destLatLng {
    // priority: pinned custom > selected junkshop > fallback
    if (_customDestinationLatLng != null) return _customDestinationLatLng!;
    if (_selectedJunkshop != null) return _selectedJunkshop!.latLng;
    return _moresFallback.latLng;
  }

  LatLng get _dropOffLatLng => _moresFallback.latLng;

  String get _dropOffTitle => _moresFallback.name;
  String get _dropOffSubtitle => _moresFallback.subtitle;

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
    final base = (_distanceKm * 4.0).round();
    return base.clamp(3, 999);
  }

  double get _earned => _distanceKm * _ratePerKm;

  String get _destinationTitle {
    if (_customDestinationLatLng != null) return "Pinned Drop-off";
    if (_selectedJunkshop != null) return _selectedJunkshop!.name;
    return "Choose junkshop"; // ✅ not Mores
  }

  String get _destinationSubtitle {
    if (_customDestinationLatLng != null) return "Custom location";
    if (_selectedJunkshop != null) return _selectedJunkshop!.subtitle;
    return "Select a drop-off";
  }

    // ===== Pickup scheduling state =====
  String _pickupType = "now"; // "now" | "window"
  DateTime _scheduleDate = DateTime.now(); // date used for window pickups
  DateTime? _windowStart;
  DateTime? _windowEnd;

  // Window label options
  static const List<Map<String, dynamic>> _windowOptions = [
    {"label": "8–10 AM", "startHour": 8, "endHour": 10},
    {"label": "10–12 NN", "startHour": 10, "endHour": 12},
    {"label": "1–3 PM", "startHour": 13, "endHour": 15},
    {"label": "3–5 PM", "startHour": 15, "endHour": 17},
    {"label": "5–8 PM", "startHour": 17, "endHour": 20},
  ];

  String get _scheduleSummary {
    if (_pickupType == "now") return "Pickup: Now (ASAP)";
    if (_windowStart == null || _windowEnd == null) return "Pickup: Choose a time window";
    final d = _scheduleDate;
    final dateStr = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    final start = _formatHm(_windowStart!);
    final end = _formatHm(_windowEnd!);
    return "Pickup: $dateStr • $start–$end";
  }

  String _formatHm(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = h >= 12 ? "PM" : "AM";
    final hh = ((h + 11) % 12) + 1; // 0->12, 13->1
    return "$hh:$m $suffix";
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _pickScheduleDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduleDate.isBefore(now) ? now : _scheduleDate,
      firstDate: _dateOnly(now),
      lastDate: _dateOnly(now.add(const Duration(days: 30))),
    );
    if (picked == null) return;

    setState(() {
      _scheduleDate = picked;

      // If a window is already selected, re-apply it to the new date
      if (_windowStart != null && _windowEnd != null) {
        final startHour = _windowStart!.hour;
        final endHour = _windowEnd!.hour;
        _windowStart = DateTime(picked.year, picked.month, picked.day, startHour, 0);
        _windowEnd = DateTime(picked.year, picked.month, picked.day, endHour, 0);
      }
    });
  }

  void _selectNow() {
    setState(() {
      _pickupType = "now";
      _windowStart = null;
      _windowEnd = null;
      _scheduleDate = DateTime.now();
    });
  }


  String formatCountdown(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.isNegative) return "Started";
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return "Starts in ${h}h ${m}m";
    return "Starts in ${diff.inMinutes}m";
  }

  bool isActiveWindow(DateTime start, DateTime end) {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }


  void _selectWindow(int startHour, int endHour) {
    final d = _scheduleDate;
    final start = DateTime(d.year, d.month, d.day, startHour, 0);
    final end = DateTime(d.year, d.month, d.day, endHour, 0);

    final now = DateTime.now();

    // Don’t allow windows that already ended
    if (end.isBefore(now)) {
      _snack("That time window already ended. Choose a later window.", bg: Colors.red);
      return;
    }

    // If window starts too soon (e.g., less than 10 minutes from now), block it
    if (start.isBefore(now.add(const Duration(minutes: 10))) && _dateOnly(d) == _dateOnly(now)) {
      _snack("Please choose a window at least 10 minutes from now.", bg: Colors.red);
      return;
    }

    setState(() {
      _pickupType = "window";
      _windowStart = start;
      _windowEnd = end;
    });
  }

  Future<String?> _fetchPolylineFromBackend(LatLng origin, LatLng dest) async {
    try {
      final callable = _functions.httpsCallable('getDirections'); // must match index.js export name
      final result = await callable.call({
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${dest.latitude},${dest.longitude}',
        'mode': 'driving', // optional if you support it in backend
      });

      final data = result.data;
      if (data is Map && data['points'] is String) {
        return data['points'] as String;
      }
      return null;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ getDirections failed: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ getDirections crashed: $e');
      return null;
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
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
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

      if (_isPickup || _isDelivering) {
        await _buildRoute();
      }
    });

    await _buildRoute();

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15),
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

    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (mounted) _snack("Location permission is required.");
      return false;
    }

    return true;
  }

  void _snack(String msg, {Color? bg}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _textPrimary)),
        backgroundColor: bg ?? Colors.black87,
        behavior: SnackBarBehavior.floating,
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

        final uid = d.id; // or data['UserID']
        final name = (data['Name'] ?? data['displayName'] ?? "Collector").toString();

        list.add({
          'uid': uid,
          'name': name,
        });
      }

      if (!mounted) return;
      setState(() {
        _availableCollectors = list;

        // keep selected if still available, otherwise reset
        final stillThere = _selectedCollectorId != null &&
            _availableCollectors.any((c) => c['uid'] == _selectedCollectorId);

        if (!stillThere) {
          _selectedCollectorId = null;
          _selectedCollectorName = null;
        }
      });
      
    });
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // ✅ Always show Mores marker
    markers.add(
      Marker(
        markerId: const MarkerId("mores_dropoff"),
        position: _dropOffLatLng,
        infoWindow: InfoWindow(
          title: _dropOffTitle,
          snippet: _dropOffSubtitle,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );

    // ✅ Still show selected destination (junkshop/pin) if different from Mores
    if (_customDestinationLatLng != null || _selectedJunkshop != null) {
      markers.add(
        Marker(
          markerId: const MarkerId("selected_destination"),
          position: _destLatLng,
          infoWindow: InfoWindow(
            title: _customDestinationLatLng != null
                ? "Pinned Drop-off"
                : (_selectedJunkshop?.name ?? "Destination"),
            snippet: _customDestinationLatLng != null
                ? "Custom location"
                : (_selectedJunkshop?.subtitle ?? ""),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ),
      );
    }

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

    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_routePoints.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId("route"),
        points: _routePoints,
        width: 6,
        color: _teal,
      ),
    };
  }

  void _onMapTap(LatLng tapped) async {
    setState(() {
      _customDestinationLatLng = tapped;
      _tripStage = TripStage.planning;
    });

    await _buildRoute();
    if (!mounted) return;
    _snack("Custom drop-off pinned", bg: _sheet);
  }

  Future<void> _openDestinationPicker() async {
    // Build destination list from Firestore, fallback to Mores if empty
    final fireList = _junkshops.isNotEmpty; 

    final destinations = <Destination>[
      ..._junkshops,
      if (_customDestinationLatLng != null)
        Destination(
          id: "pinned",
          name: "Pinned Drop-off",
          subtitle: "Custom location",
          latLng: _customDestinationLatLng!,
        ),
    ];
    
    final picked = await showModalBottomSheet<Destination>(
      context: context,
      backgroundColor: _sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Icon(Icons.place_outlined, color: _accent),
                    SizedBox(width: 10),
                    Text(
                      "Choose destination",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: destinations.length,
                    itemBuilder: (_, i) {
                      final d = destinations[i];
                      final isPinned = d.name == "Pinned Drop-off";


                      final bool selected = isPinned
                          ? (_customDestinationLatLng != null)
                          : (_customDestinationLatLng == null &&
                              _selectedJunkshop?.name == d.name &&
                              _selectedJunkshop?.latLng == d.latLng);

                      return ListTile(
                        onTap: () => Navigator.pop(context, d),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: selected ? _accent.o(0.18) : Colors.white.o(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? _accent.o(0.55) : Colors.white.o(0.08),
                            ),
                          ),
                          child: Icon(
                            isPinned ? Icons.push_pin : Icons.store_mall_directory,
                            color: _accent,
                          ),
                        ),
                        title: Text(
                          d.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          d.subtitle,
                          style: const TextStyle(color: _textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: selected
                            ? const Icon(Icons.check_circle, color: _accent)
                            : const Icon(Icons.chevron_right, color: _textMuted),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null || !mounted) return;

    setState(() {
      _tripStage = TripStage.planning;

      if (picked.name == "Pinned Drop-off") {
        // keep pin
      } else {
        _selectedJunkshop = picked;
        _customDestinationLatLng = null;
      }
    });

    await _buildRoute();
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(picked.latLng, 16));
  }

  Future<void> _startDirectionsToMores() async {
    setState(() => _tripStage = TripStage.delivering);

    await _buildRouteTo(_dropOffLatLng);

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_dropOffLatLng, 16),
    );

    _snack("Showing directions to Mores Scrap Trading.", bg: _sheet);
  }

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  Future<void> _buildRouteTo(LatLng dest) async {
    if (_currentPosition == null) {
      if (mounted) setState(() => _routePoints = []);
      return;
    }

    final origin = _originLatLng;

    try {
      final callable = _functions.httpsCallable('getDirections');
      final result = await callable.call({
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${dest.latitude},${dest.longitude}',
        'mode': 'driving',
      });

      final data = result.data;
      final points = (data is Map) ? data['points'] as String? : null;

      if (points == null || points.isEmpty) {
        if (!mounted) return;
        setState(() => _routePoints = []);
        return;
      }

      final decoded = _decodePolyline(points);

      if (!mounted) return;
      setState(() => _routePoints = decoded);
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


  Future<void> requestPickupWithConfirm({
    required LatLng pickupLatLng,
    required String? pickupAddress,

  }) async {
    final bool isWindow = _pickupType == "window";
    if (isWindow && (_windowStart == null || _windowEnd == null)) {
      _snack("Please select a time window.", bg: Colors.red);
      return;
    }
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_selectedCollectorId == null) {
      _snack("Please choose an available collector first.", bg: Colors.red);
      return;
    }
    // ✅ OPTIONAL: block if household already has an active order
    try {
      final active = await FirebaseFirestore.instance
          .collection('requests')
          .where('householdId', isEqualTo: user.uid)
          .where('active', isEqualTo: true)
          .limit(1)
          .get();

      if (active.docs.isNotEmpty) {
        _snack(
          "You already have an active pickup order. Cancel it first from the Order tab.",
          bg: Colors.red,
        );
        return;
      }
    } catch (e) {
      // If this fails due to missing index or connection, you can still allow request
      debugPrint("Active-order check failed: $e");
    }

    final householdName = await _getUserName(user.uid, fallback: user.email ?? "Household");
    final collectorName = (_selectedCollectorName ?? "Collector").trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(  
        title: const Text("Confirm Pickup Request"),
        content: Text(
          "Send pickup request?\n\n"
          "Address: ${pickupAddress ?? "Unknown"}\n"
          "Collector: $collectorName\n"
          "Destination: $_destinationTitle\n"
          "$_scheduleSummary",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('requests').add({
        'type': 'pickup',
        'active': true,

        'householdId': user.uid,
        'householdName': householdName,

        'collectorId': _selectedCollectorId,
        'collectorName': collectorName,

        'pickupType': _pickupType, // "now" | "window"
        'windowStart': _windowStart == null ? null : Timestamp.fromDate(_windowStart!),
        'windowEnd': _windowEnd == null ? null : Timestamp.fromDate(_windowEnd!),

        'scheduledAt': _windowStart == null ? null : Timestamp.fromDate(_windowStart!),

        'status': (_pickupType == "now") ? 'pending' : 'scheduled',

        'pickupLocation': GeoPoint(pickupLatLng.latitude, pickupLatLng.longitude),
        'pickupAddress': pickupAddress ?? '',


        'junkshopId': _selectedJunkshop?.id ?? '',
        'junkshopName': _selectedJunkshop?.name ?? '',
        'junkshopLocation': _selectedJunkshop == null
            ? null
            : GeoPoint(_selectedJunkshop!.latLng.latitude, _selectedJunkshop!.latLng.longitude),

          // ✅ NEW: arrived + cancel defaults
        'arrived': false,
        'arrivedAt': null,
        'cancelledAt': null,

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),

      });
    } catch (e, st) {
      debugPrint("❌ pickupRequests add failed: $e");
      debugPrint("$st");
      debugPrint("❌ requests.add permission error: $e");
      debugPrint("$st");

      if (mounted) _snack("Pickup failed: $e", bg: Colors.red);
      return;
    }

    if (!mounted) return;
    _snack("Pickup request sent!", bg: _accent);
  }

  

  Future<String> _getUserName(String uid, {String fallback = "Unknown"}) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      final data = doc.data() ?? {};
      final name = (data['Name'] ?? data['displayName'] ?? data['name'] ?? '').toString().trim();

      if (name.isNotEmpty) return name;

      final email = (data['email'] ?? '').toString().trim();
      if (email.isNotEmpty) return email;

      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _buildRoute() async {
    await _buildRouteTo(_destLatLng);
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

  @override
  Widget build(BuildContext context) {
    final bool hasCollectors = _availableCollectors.isNotEmpty;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Map
          Positioned.fill(
            child: GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(target: _paloAltoCenter, zoom: 14),
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
                    Colors.black.o(0.55),
                    Colors.black.o(0.05),
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
                      Icon(Icons.signal_cellular_alt, size: 14, color: _textPrimary),
                      SizedBox(width: 6),
                      Icon(Icons.wifi, size: 14, color: _textPrimary),
                      SizedBox(width: 6),
                      Icon(Icons.battery_full, size: 14, color: _textPrimary),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Search bar
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
                      _snack("No screen to go back to.", bg: Colors.black87);
                    }
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _openDestinationPicker,
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: _bg.o(0.94),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.o(0.14)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.o(0.35),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 18, color: _textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _destinationTitle.isEmpty ? "Where to drop off?" : _destinationTitle,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.tune, size: 16, color: _textSecondary),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom sheet
          DraggableScrollableSheet(
            initialChildSize: 0.46,
            minChildSize: 0.22,
            maxChildSize: 0.82,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                decoration: BoxDecoration(
                  color: _sheet,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                  border: Border(top: BorderSide(color: Colors.white.o(0.10))),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.o(0.55),
                      blurRadius: 44,
                      offset: const Offset(0, -12),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
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
                    const SizedBox(height: 18),

                    const Text(
                      "Set Pickup",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ===== Collectors =====
                    const Text(
                      "AVAILABLE COLLECTORS",
                      style: TextStyle(
                        fontSize: 10,
                        color: _textMuted,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.o(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.o(0.10)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCollectorId,
                          dropdownColor: _sheet,
                          hint: Text(
                            hasCollectors ? "Choose a driver" : "No collectors online",
                            style: const TextStyle(color: _textSecondary),
                          ),
                          iconEnabledColor: _textSecondary,
                          items: _availableCollectors.map((c) {
                            final uid = c['uid']!;
                            final name = c['name']!;

                            return DropdownMenuItem<String>(
                              value: uid,
                              child: Row(
                                children: [
                                  // 🟢 Online indicator
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),

                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(color: _textPrimary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: hasCollectors
                              ? (uid) {
                                  if (uid == null) return;
                                  final found = _availableCollectors.firstWhere((c) => c['uid'] == uid);
                                  setState(() {
                                    _selectedCollectorId = uid;
                                    _selectedCollectorName = found['name'];
                                  });
                                }
                              : null,
                        ),
                      ),
                    ),

                    // ✅ FIX: add spacing so it DOESN’T visually overlap
                    const SizedBox(height: 12),

                    // ===== Location + Destination card =====
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.o(0.06),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.o(0.10)),
                      ),
                      child: Row(
                        children: [
                          Column(
                            children: [
                              const Icon(Icons.radio_button_checked, color: Colors.blue, size: 20),
                              Container(width: 1, height: 30, color: Colors.blue.o(0.35)),
                              const Icon(Icons.location_on, color: _accent, size: 20),
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
                                // YOUR LOCATION VALUE
                                Text(
                                  _locationReady && _currentPosition != null
                                      ? "${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}"
                                      : "Locating...",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: _textSecondary,   // 👈 softer than white
                                    fontWeight: FontWeight.w600,
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
                                // DESTINATION VALUE
                                Text(
                                  _destinationTitle,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: _accent,   // 👈 makes destination stand out
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (_customDestinationLatLng != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    "Pinned: ${_customDestinationLatLng!.latitude.toStringAsFixed(4)}, ${_customDestinationLatLng!.longitude.toStringAsFixed(4)}",
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: _openDestinationPicker,
                            child: const Icon(Icons.chevron_right, color: _textMuted),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    _pickupScheduleSection(),
                    const SizedBox(height: 18),
                    
                    // Stats
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.o(0.20),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.o(0.10)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _statItem(Icons.access_time, "$_etaMinutes min"),
                          _statDivider(),
                          _statItem(Icons.navigation_outlined, "${_distanceKm.toStringAsFixed(1)} km"),
                          _statDivider(),
                          Text(
                            "₱${_earned.toStringAsFixed(2)}",
                            style: const TextStyle(
                              color: _accent,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: _startDirectionsToMores,
                              icon: const Icon(Icons.directions),
                              label: const Text("DROP-OFF"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: _bg,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                if (!hasCollectors) {
                                  _snack("No available collectors right now.", bg: Colors.black87);
                                  return;
                                }
                                if (!_locationReady || _currentPosition == null) {
                                  _snack("Still getting your location. Please wait...", bg: Colors.black87);
                                  return;
                                }
                                await requestPickupWithConfirm(
                                  pickupLatLng: _originLatLng,
                                  pickupAddress:
                                      "${_originLatLng.latitude.toStringAsFixed(5)}, ${_originLatLng.longitude.toStringAsFixed(5)}",
                                );
                              },
                              icon: const Icon(Icons.local_shipping),
                              label: const Text("PICKUP"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: _bg,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Center(
                      child: Container(
                        width: 120,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ],
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
      decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
    );
  }
  Widget _pickupScheduleSection() {
    final bool isWindow = _pickupType == "window";

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.o(0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.o(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "PICKUP SCHEDULE",
            style: TextStyle(
              fontSize: 10,
              color: _textMuted,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),

          // Summary line
          Text(
            _scheduleSummary,
            style: const TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),

          // Now / Schedule toggle
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ChoiceChip(
                label: const Text("Now (ASAP)"),
                selected: _pickupType == "now",
                onSelected: (_) => _selectNow(),
                selectedColor: _accent.o(0.22),
                backgroundColor: Colors.white.o(0.06),
                labelStyle: TextStyle(
                  color: _pickupType == "now" ? _textPrimary : _textSecondary,
                  fontWeight: FontWeight.w800,
                ),
                side: BorderSide(color: _pickupType == "now" ? _accent.o(0.55) : Colors.white.o(0.10)),
              ),
              ChoiceChip(
                label: const Text("Schedule (Window)"),
                selected: isWindow,
                onSelected: (_) {
                  // If switching to window, require choosing a window
                  setState(() => _pickupType = "window");
                },
                selectedColor: _accent.o(0.22),
                backgroundColor: Colors.white.o(0.06),
                labelStyle: TextStyle(
                  color: isWindow ? _textPrimary : _textSecondary,
                  fontWeight: FontWeight.w800,
                ),
                side: BorderSide(color: isWindow ? _accent.o(0.55) : Colors.white.o(0.10)),
              ),
            ],
          ),

          // Window options
          if (isWindow) ...[
            const SizedBox(height: 12),

            // Date picker row
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _pickScheduleDate,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.o(0.20),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.o(0.10)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16, color: _textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "${_scheduleDate.year}-${_scheduleDate.month.toString().padLeft(2, '0')}-${_scheduleDate.day.toString().padLeft(2, '0')}",
                              style: const TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: _textMuted),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Window chips
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _windowOptions.map((w) {
                final label = w["label"] as String;
                final startHour = w["startHour"] as int;
                final endHour = w["endHour"] as int;

                final selected = _windowStart != null &&
                    _windowEnd != null &&
                    _windowStart!.hour == startHour &&
                    _windowEnd!.hour == endHour;

                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => _selectWindow(startHour, endHour),
                  selectedColor: _accent.o(0.22),
                  backgroundColor: Colors.white.o(0.06),
                  labelStyle: TextStyle(
                    color: selected ? _textPrimary : _textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                  side: BorderSide(color: selected ? _accent.o(0.55) : Colors.white.o(0.10)),
                );
              }).toList(),
            ),

            // Hint if no window selected
            if (_windowStart == null || _windowEnd == null) ...[
              const SizedBox(height: 10),
              const Text(
                "Select a time window so the collector can arrive anytime within that range.",
                style: TextStyle(
                  color: _textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

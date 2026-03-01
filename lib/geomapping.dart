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

/// Trip stages (kept for future extensibility)
enum TripStage { planning, pickup, delivering }

class GeoMappingPage extends StatefulWidget {
  const GeoMappingPage({super.key});

  @override
  State<GeoMappingPage> createState() => _GeoMappingPageState();
}

class _GeoMappingPageState extends State<GeoMappingPage> {
  // ===== Theme / Colors =====
  static const Color _bg = Color(0xFF0F172A);
  static const Color _sheet = Color(0xFF111928);
  static const Color _accent = Color(0xFF10B981);
  static const Color _teal = Color(0xFF1FA9A7);
  static const Color _dropdown = Color(0xFF1F2937); // slightly lighter than _sheet

  // Text colors
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

  // ✅ Fixed destination: MORES only
  final LatLng _moresLatLng = const LatLng(14.198630, 121.117270);
  final String _moresName = "Mores Scrap Trading";
  final String _moresSubtitle = "Official Drop-off";

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

  // Delivery fee model (demo)
  double get _ratePerKm => 12.0;

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
    final base = (_distanceKm * 4.0).round();
    return base.clamp(3, 999);
  }

  double get _deliveryFee => _distanceKm * _ratePerKm;

  // ----- Available collectors dropdown -----
  String? _selectedCollectorId;
  String? _selectedCollectorName;
  List<Map<String, String>> _availableCollectors = []; // [{uid,name}]

  // ===== Pickup scheduling state =====
  String _pickupType = "now"; // "now" | "window"
  DateTime _scheduleDate = DateTime.now();
  DateTime? _windowStart;
  DateTime? _windowEnd;

  // ===== Pickup location selection (Option B simplified) =====
  LatLng? _pinnedPickupLatLng;       // null => use GPS
  String _pickupSource = "gps";      // "gps" | "pin"

  LatLng get _effectivePickupLatLng => _pinnedPickupLatLng ?? _originLatLng;

  String get _pickupLocationLabel {
    if (_pinnedPickupLatLng == null) return "Current Location (GPS)";
    return "Pinned Location";
  }

  // ===== Bag size requirement =====
  // Values are also saved to Firestore for collector
  static const List<Map<String, dynamic>> _bagOptions = [
    {"key": "small", "label": "Small Bag", "kg": 2},
    {"key": "medium", "label": "Medium Bag", "kg": 5},
    {"key": "large", "label": "Large Bag", "kg": 10},
  ];
  String? _selectedBagKey; // required

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
    final dateStr =
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    final start = _formatHm(_windowStart!);
    final end = _formatHm(_windowEnd!);
    return "Pickup: $dateStr • $start–$end";
  }

  String _formatHm(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = h >= 12 ? "PM" : "AM";
    final hh = ((h + 11) % 12) + 1;
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

    // If window starts too soon, block it
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

  Future<void> _buildRoute() async {
    await _buildRouteTo(_moresLatLng);
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
        final uid = d.id;
        final name = (data['Name'] ?? data['displayName'] ?? "Collector").toString();

        list.add({'uid': uid, 'name': name});
      }

      if (!mounted) return;
      setState(() {
        _availableCollectors = list;

        final stillThere = _selectedCollectorId != null &&
            _availableCollectors.any((c) => c['uid'] == _selectedCollectorId);

        if (!stillThere) {
          _selectedCollectorId = null;
          _selectedCollectorName = null;
        }
      });
    });
  }

  void _onMapTap(LatLng tapped) {
    setState(() {
      _pinnedPickupLatLng = tapped;
      _pickupSource = "pin";
    });

    _snack("Pickup location pinned.", bg: _sheet);

    // Optional: zoom to the pin so user sees it clearly
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
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
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

  Future<void> _startDirectionsToMores() async {
    setState(() => _tripStage = TripStage.delivering);

    await _buildRouteTo(_moresLatLng);

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_moresLatLng, 16),
    );

    _snack("Showing directions to $_moresName.", bg: _sheet);
  }

  // =========================
  // PICKUP FLOW (new)
  // =========================

  Future<void> _openPickupFlowSheet() async {
    if (_availableCollectors.isEmpty) {
      _snack("No available collectors right now.", bg: Colors.black87);
      return;
    }
    if (!_locationReady || _currentPosition == null) {
      _snack("Still getting your location. Please wait...", bg: Colors.black87);
      return;
    }

    // Reset required selections each time (optional; remove if you want to keep previous selections)
    setState(() {
      _pickupType = "now";
      _windowStart = null;
      _windowEnd = null;
      _scheduleDate = DateTime.now();
      _selectedBagKey = null;
      // keep collector selection if you want, or reset:
      // _selectedCollectorId = null;
      // _selectedCollectorName = null;
    });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final hasCollectors = _availableCollectors.isNotEmpty;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: StatefulBuilder(
              builder: (context, setLocal) {
                void localSet(VoidCallback fn) {
                  setState(fn);
                  setLocal(fn);
                }

                final bagPicked = _selectedBagKey != null;
                final collectorPicked = _selectedCollectorId != null;
                final isWindow = _pickupType == "window";
                final windowOk = !isWindow || (_windowStart != null && _windowEnd != null);

                final canSubmit = bagPicked && collectorPicked && windowOk;

                final bagMeta = _bagOptions.firstWhere(
                  (b) => b["key"] == _selectedBagKey,
                  orElse: () => {"label": "-", "kg": 0, "key": ""},
                );
                final bagLabel = bagMeta["label"] as String;
                final bagKg = bagMeta["kg"] as int;

                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
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

                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _accent.o(0.16),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _accent.o(0.35)),
                            ),
                            child: const Icon(Icons.local_shipping, color: _accent),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              "Request Pickup",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: _textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _miniInfoCard(
                        title: "Estimated Delivery Fee",
                        value: "₱${_deliveryFee.toStringAsFixed(2)} • ${_distanceKm.toStringAsFixed(1)} km • $_etaMinutes min",
                        icon: Icons.payments_outlined,
                        valueColor: _accent,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.o(0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.o(0.10)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "PICKUP LOCATION",
                              style: TextStyle(
                                fontSize: 10,
                                color: _textMuted, 
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 8),

                            Row(
                              children: [
                                Icon(
                                  _pinnedPickupLatLng == null ? Icons.my_location : Icons.push_pin,
                                  size: 16,
                                  color: _accent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _pickupLocationLabel,
                                    style: const TextStyle(
                                      color: _textMuted,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                if (_pinnedPickupLatLng != null)
                                TextButton(
                                  onPressed: () {
                                    localSet(() {
                                      _pinnedPickupLatLng = null;
                                      _pickupSource = "gps";
                                    });
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: _accent, // ✅ matches theme
                                  ),
                                  child: const Text("Use GPS"),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            Text(
                              _pinnedPickupLatLng == null
                                  ? "Using your current location. Tap the map to pin a different pickup point."
                                  : "Pinned at: ${_pinnedPickupLatLng!.latitude.toStringAsFixed(5)}, ${_pinnedPickupLatLng!.longitude.toStringAsFixed(5)}\nTap the map again to move the pin.",
                              style: const TextStyle(
                                color: _textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),
                      const Text(
                        "CHOOSE A DRIVER",
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
                            style: const TextStyle(color: _textPrimary, fontWeight: FontWeight.w800),
                            value: _selectedCollectorId,
                            dropdownColor: _dropdown,
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
                                mainAxisSize: MainAxisSize.min, // ✅ important
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    fit: FlexFit.loose,
                                    child: Text(
                                      name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _textMuted,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            }).toList(),
                            onChanged: hasCollectors
                                ? (uid) {
                                    if (uid == null) return;
                                    final found =
                                        _availableCollectors.firstWhere((c) => c['uid'] == uid);
                                    localSet(() {
                                      _selectedCollectorId = uid;
                                      _selectedCollectorName = found['name'];
                                    });
                                  }
                                : null,
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),
                      const Text(
                        "PICKUP SCHEDULE",
                        style: TextStyle(
                          fontSize: 10,
                          color: _textMuted,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _scheduleSummary,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),

                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ChoiceChip(
                            label: const Text("Now (ASAP)"),
                            selected: _pickupType == "now",
                            onSelected: (_) => localSet(() => _selectNow()),
                            selectedColor: _accent.o(0.22),
                            backgroundColor: Colors.white.o(0.06),
                            labelStyle: TextStyle(
                              color: _pickupType == "now" ? _textPrimary : _textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                            side: BorderSide(
                              color: _pickupType == "now" ? _accent.o(0.55) : Colors.white.o(0.10),
                            ),
                          ),
                          ChoiceChip(
                            label: const Text("Schedule (Window)"),
                            selected: _pickupType == "window",
                            onSelected: (_) {
                              localSet(() => _pickupType = "window");
                            },
                            selectedColor: _accent.o(0.22),
                            backgroundColor: Colors.white.o(0.06),
                            labelStyle: TextStyle(
                              color: _pickupType == "window" ? _textPrimary : _textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                            side: BorderSide(
                              color: _pickupType == "window" ? _accent.o(0.55) : Colors.white.o(0.10),
                            ),
                          ),
                        ],
                      ),

                      if (_pickupType == "window") ...[
                        const SizedBox(height: 12),

                        InkWell(
                          onTap: () async {
                            await _pickScheduleDate();
                            setLocal(() {});
                          },
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

                        const SizedBox(height: 12),

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
                              onSelected: (_) {
                                _selectWindow(startHour, endHour);
                                setLocal(() {});
                              },
                              selectedColor: _accent.o(0.22),
                              backgroundColor: Colors.white.o(0.06),
                              labelStyle: TextStyle(
                                color: selected ? _textPrimary : _textSecondary,
                                fontWeight: FontWeight.w800,
                              ),
                              side: BorderSide(
                                color: selected ? _accent.o(0.55) : Colors.white.o(0.10),
                              ),
                            );
                          }).toList(),
                        ),

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

                      const SizedBox(height: 18),
                      const Text(
                        "BAG SIZE (REQUIRED)",
                        style: TextStyle(
                          fontSize: 10,
                          color: _textMuted,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _bagOptions.map((b) {
                          final key = b["key"] as String;
                          final label = b["label"] as String;
                          final kg = b["kg"] as int;
                          final selected = _selectedBagKey == key;

                          return ChoiceChip(
                            label: Text("$label • ${kg}kg"),
                            selected: selected,
                            onSelected: (_) => localSet(() => _selectedBagKey = key),
                            selectedColor: _accent.o(0.22),
                            backgroundColor: Colors.white.o(0.06),
                            labelStyle: TextStyle(
                              color: selected ? _textPrimary : _textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                            side: BorderSide(
                              color: selected ? _accent.o(0.55) : Colors.white.o(0.10),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 18),

                      // Submit buttons
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _textPrimary,
                                  side: BorderSide(color: Colors.white.o(0.14)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: const Text(
                                  "CANCEL",
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: canSubmit
                                    ? () async {
                                        Navigator.pop(ctx);

                                        final pickupLatLng = _effectivePickupLatLng;

                                        await requestPickupWithConfirm(
                                          pickupLatLng: pickupLatLng,
                                          pickupAddress:
                                              "${pickupLatLng.latitude.toStringAsFixed(5)}, ${pickupLatLng.longitude.toStringAsFixed(5)}",
                                          bagKey: _selectedBagKey!,
                                          bagLabel: bagLabel,
                                          bagKg: bagKg,
                                          deliveryFee: _deliveryFee,
                                          distanceKm: _distanceKm,
                                          etaMinutes: _etaMinutes,
                                        );
                                      }
                                    : () {
                                        if (!collectorPicked) {
                                          _snack("Please choose a driver.", bg: Colors.red);
                                        } else if (!windowOk) {
                                          _snack("Please select a time window.", bg: Colors.red);
                                        } else if (!bagPicked) {
                                          _snack("Please select a bag size (required).", bg: Colors.red);
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: _bg,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  "CONFIRM PICKUP",
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      Text(
                        "Note: Delivery fee is sent to the collector with this request.",
                        style: TextStyle(
                          color: _textSecondary.o(0.90),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _miniInfoCard({
    required String title,
    required String value,
    required IconData icon,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.o(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.o(0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.black.o(0.20),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.o(0.10)),
            ),
            child: Icon(icon, color: _textSecondary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: _textMuted,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? _textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // Firestore request (updated fields)
  // =========================
  Future<void> requestPickupWithConfirm({
    required LatLng pickupLatLng,
    required String? pickupAddress,
    required String bagKey,
    required String bagLabel,
    required int bagKg,
    required double deliveryFee,
    required double distanceKm,
    required int etaMinutes,
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

    if (_selectedBagKey == null) {
      _snack("Please select a bag size (required).", bg: Colors.red);
      return;
    }

    // OPTIONAL: block if household already has an active order
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
      debugPrint("Active-order check failed: $e");
    }

    final householdName =
        await _getUserName(user.uid, fallback: user.email ?? "Household");
    final collectorName = (_selectedCollectorName ?? "Collector").trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Pickup Request"),
        content: Text(
          "Send pickup request to $collectorName?\n\n"
          "Destination: $_moresName\n"
          "Address: ${pickupAddress ?? "Unknown"}\n"
          "$_scheduleSummary\n"
          "Bag: $bagLabel (${bagKg}kg)\n"
          "Distance/ETA: ${distanceKm.toStringAsFixed(1)} km • $etaMinutes min\n"
          "Delivery Fee: ₱${deliveryFee.toStringAsFixed(2)}\n",
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

        // schedule
        'pickupType': _pickupType, // "now" | "window"
        'windowStart': _windowStart == null ? null : Timestamp.fromDate(_windowStart!),
        'windowEnd': _windowEnd == null ? null : Timestamp.fromDate(_windowEnd!),
        'scheduledAt': _windowStart == null ? null : Timestamp.fromDate(_windowStart!),
        'status': (_pickupType == "now") ? 'pending' : 'scheduled',

        // pickup location
        'pickupLocation': GeoPoint(pickupLatLng.latitude, pickupLatLng.longitude),
        'pickupAddress': pickupAddress ?? '',
        'pickupSource': _pickupSource, // add this

        // ✅ fixed destination (Mores only)
        'destinationId': 'mores',
        'destinationName': _moresName,
        'destinationLocation': GeoPoint(_moresLatLng.latitude, _moresLatLng.longitude),

        // ✅ new: bag requirement
        'bagKey': bagKey,
        'bagLabel': bagLabel,
        'bagKg': bagKg,

        // ✅ new: fee + route summary (collector can see this)
        'deliveryFee': double.parse(deliveryFee.toStringAsFixed(2)),
        'distanceKm': double.parse(distanceKm.toStringAsFixed(2)),
        'etaMinutes': etaMinutes,

        // arrived + cancel defaults
        'arrived': false,
        'arrivedAt': null,
        'cancelledAt': null,

        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      debugPrint("❌ requests.add failed: $e");
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

  @override
  Widget build(BuildContext context) {
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
              // ✅ disabled pinning; Mores only
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

          // Top bar (fixed destination pill)
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
                        const Icon(Icons.store_mall_directory, size: 18, color: _accent),
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
              ],
            ),
          ),

          // Bottom sheet (overview + actions)
          DraggableScrollableSheet(
            initialChildSize: 0.40,
            minChildSize: 0.22,
            maxChildSize: 0.75,
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
                      style: TextStyle(
                        color: _textSecondary.o(0.95),
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Location summary
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
                              const Icon(Icons.radio_button_checked,
                                  color: Colors.blue, size: 20),
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
                                Text(
                                  _locationReady && _currentPosition != null
                                      ? "${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}"
                                      : "Locating...",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: _textSecondary,
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
                            "₱${_deliveryFee.toStringAsFixed(2)}",
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
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18)),
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
                              onPressed: _openPickupFlowSheet,
                              icon: const Icon(Icons.local_shipping),
                              label: const Text("PICKUP"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: _bg,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18)),
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
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(2),
                        ),
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
}
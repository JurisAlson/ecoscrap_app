import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Avoid deprecated withOpacity() by using withValues(alpha: double)
extension OpacityFix on Color {
  Color o(double opacity) =>
      withValues(alpha: ((opacity * 255).clamp(0, 255)).toDouble());
}

/// ✅ Put your real Directions API key here
/// (Polyline will work as long as Directions API is enabled + billing is on)
const String _googleDirectionsApiKey = "AIzaSyAJVP8YXeKKBvr5rSsGwOUqWEAOPZ10dGg";

/// Trip stages
enum TripStage { planning, pickup, delivering }

class Destination {
  final String name;
  final String subtitle;
  final LatLng latLng;

  const Destination({
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

  // Destination
  final Destination _mores = const Destination(
    name: "Mores Scrap Trading",
    subtitle: "Junkshop • Drop-off",
    latLng: LatLng(14.198490, 121.117035),
  );

  late Destination _selectedDestination;

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

  LatLng get _originLatLng {
    final p = _currentPosition;
    if (p == null) return _paloAltoCenter; // fallback only
    return LatLng(p.latitude, p.longitude);
  }

  LatLng get _destLatLng => _customDestinationLatLng ?? _selectedDestination.latLng;

  double get _distanceKm {
    final meters = Geolocator.distanceBetween(
      _originLatLng.latitude,
      _originLatLng.longitude,
      _destLatLng.latitude,
      _destLatLng.longitude,
    );
    return meters / 1000.0;
  }

  // ✅ Simple consistent ETA (no fast/normal toggle)
  int get _etaMinutes {
    final base = (_distanceKm * 4.0).round();
    return base.clamp(3, 999);
  }

  double get _earned => _distanceKm * _ratePerKm;

  @override
  void initState() {
    super.initState();
    _selectedDestination = _mores;

    _timeString = _formatTime(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _timeString = _formatTime(DateTime.now()));
    });

    _initLocation();
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

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // Destination marker
    markers.add(
      Marker(
        markerId: const MarkerId("selected_destination"),
        position: _destLatLng,
        infoWindow: InfoWindow(
          title: _customDestinationLatLng != null ? "Pinned Drop-off" : _selectedDestination.name,
          snippet: _customDestinationLatLng != null ? "Custom location" : _selectedDestination.subtitle,
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );

    // User marker (optional)
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
    final destinations = <Destination>[
      _mores,
      if (_customDestinationLatLng != null)
        Destination(
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
                ...destinations.map((d) {
                  final isPinned = d.name == "Pinned Drop-off";
                  final selected = isPinned ? (_customDestinationLatLng != null) : (_customDestinationLatLng == null);

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
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_circle, color: _accent)
                        : const Icon(Icons.chevron_right, color: _textMuted),
                  );
                }),
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
        _selectedDestination = picked;
        _customDestinationLatLng = null;
      }
    });

    await _buildRoute();
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(picked.latLng, 16));
  }

  Future<void> _startPickup() async {
    setState(() => _tripStage = TripStage.pickup);
    await _buildRoute();
    if (!mounted) return;
    _snack("Pickup started — routing...", bg: _accent);
  }

  Future<void> _arrivedDeliver() async {
    setState(() => _tripStage = TripStage.delivering);
    await _buildRoute();
    if (!mounted) return;
    _snack("Deliver mode — confirm drop-off.", bg: _sheet);
  }

  void _finishDelivery() {
    setState(() => _tripStage = TripStage.planning);
    _snack("Delivered — trip complete.", bg: _sheet);
  }

  void _cancelPickup() {
    setState(() => _tripStage = TripStage.planning);
    _snack("Pickup canceled.", bg: _sheet);
  }

  Future<void> _buildRoute() async {
    // ✅ Only skip if user didn't replace the key
    if (_googleDirectionsApiKey.isEmpty || _googleDirectionsApiKey == "API_KEY_HERE") {
      if (mounted) setState(() => _routePoints = []);
      return;
    }

    final origin = _originLatLng;
    final dest = _destLatLng;

    final uri = Uri.parse(
      "https://maps.googleapis.com/maps/api/directions/json"
      "?origin=${origin.latitude},${origin.longitude}"
      "&destination=${dest.latitude},${dest.longitude}"
      "&mode=driving"
      "&key=$_googleDirectionsApiKey",
    );

    try {
      final res = await http.get(uri);
      final data = jsonDecode(res.body) as Map<String, dynamic>;

      if (data["status"] != "OK") {
        if (!mounted) return;
        setState(() => _routePoints = []);
        _snack("Directions: ${data["status"]}", bg: Colors.black87);
        return;
      }

      final routes = data["routes"] as List<dynamic>;
      if (routes.isEmpty) {
        if (mounted) setState(() => _routePoints = []);
        return;
      }

      final encoded = routes.first["overview_polyline"]["points"] as String;
      final decoded = _decodePolyline(encoded);

      if (!mounted) return;
      setState(() => _routePoints = decoded);
    } catch (_) {
      if (!mounted) return;
      setState(() => _routePoints = []);
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
    final destinationTitle = _customDestinationLatLng != null ? "Pinned Drop-off" : _selectedDestination.name;

    final String primaryButtonLabel = _tripStage == TripStage.planning
        ? "START PICKUP"
        : _tripStage == TripStage.pickup
            ? "ARRIVED / DELIVER"
            : "FINISH DELIVERY";

    final bool showCancel = _tripStage == TripStage.pickup;

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
                              destinationTitle.isEmpty ? "Where to drop off?" : destinationTitle,
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
            initialChildSize: 0.44,
            minChildSize: 0.22,
            maxChildSize: 0.80,
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

                    // Address card
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
                                Text(
                                  _locationReady && _currentPosition != null
                                      ? "${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}"
                                      : "Locating...",
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
                                  destinationTitle,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: _textPrimary,
                                    fontWeight: FontWeight.w700,
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
                          const Icon(Icons.chevron_right, color: _textMuted),
                        ],
                      ),
                    ),

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

                    // Primary button
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (_tripStage == TripStage.planning) {
                            await _startPickup();
                          } else if (_tripStage == TripStage.pickup) {
                            await _arrivedDeliver();
                          } else {
                            _finishDelivery();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _tripStage == TripStage.pickup ? Colors.white : _accent,
                          foregroundColor: _bg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                        child: Text(
                          primaryButtonLabel,
                          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2),
                        ),
                      ),
                    ),

                    if (showCancel) ...[
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _cancelPickup,
                        child: const Text(
                          "Cancel pickup",
                          style: TextStyle(color: _textSecondary, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],

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

      // ✅ Clean UI: no bottom navbar
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

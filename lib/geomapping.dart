import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'household/household_dashboard.dart';
import 'image_detection.dart';

/// Avoid deprecated withOpacity() by using withValues(alpha: double)
extension OpacityFix on Color {
  Color o(double opacity) =>
      withValues(alpha: ((opacity * 255).clamp(0, 255)).toDouble());
}

/// ===== OPTIONAL (Routing) =====
/// Put your Directions API key here when ready.
/// If left as-is, routing polyline will simply not draw (no crash).
const String _googleDirectionsApiKey = "PUT_YOUR_DIRECTIONS_API_KEY_HERE";

enum PlasticType { pet, pp, hdpe }

/// NEW: trip stages
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
  // Footer nav
  final int _selectedIndex = 2;

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;

    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ImageDetectionPage()),
      );
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardPage()),
      );
    }
  }

  // Time
  late String _timeString;
  late Timer _timer;

  // Map
  GoogleMapController? _mapController;

  // Center: Brgy Palo Alto, Calamba, Laguna (center point)
  final LatLng _paloAltoCenter = const LatLng(14.18695, 121.11299);

  // Main destination: Mores Scrap Trading (given coords)
  final Destination _mores = const Destination(
    name: "Mores Scrap Trading",
    subtitle: "Junkshop • Drop-off",
    latLng: LatLng(14.198490, 121.117035),
  );

  // Selected destination
  late Destination _selectedDestination;

  // If user taps map: create a pinned drop-off
  LatLng? _customDestinationLatLng;

  // Location
  bool _locationReady = false;
  Position? _currentPosition;
  StreamSubscription<Position>? _posSub;

  // Route polyline (Directions API)
  List<LatLng> _routePoints = [];

  // UI state
  bool _fastRoute = true;
  PlasticType _selectedPlastic = PlasticType.pet;

  /// NEW: trip stage instead of _pickupActive
  TripStage _tripStage = TripStage.planning;

  bool get _isPickup => _tripStage == TripStage.pickup;
  bool get _isDelivering => _tripStage == TripStage.delivering;

  /// Navbar is hidden ONLY during pickup stage
  bool get _showNavbar => _tripStage != TripStage.pickup;

  // Earnings model (just demo, tune later)
  double get _ratePerKm {
    switch (_selectedPlastic) {
      case PlasticType.pet:
        return 12.0; // PET
      case PlasticType.pp:
        return 10.0; // PP
      case PlasticType.hdpe:
        return 14.0; // HDPE
    }
  }

  LatLng get _originLatLng {
    final p = _currentPosition;
    if (p == null) return _paloAltoCenter;
    return LatLng(p.latitude, p.longitude);
  }

  LatLng get _destLatLng => _customDestinationLatLng ?? _selectedDestination.latLng;

  // Distance estimate:
  // - If Directions polyline is present, you can later compute real distance from legs.
  // - For now: straight-line distance (works without Directions).
  double get _distanceKm {
    final meters = Geolocator.distanceBetween(
      _originLatLng.latitude,
      _originLatLng.longitude,
      _destLatLng.latitude,
      _destLatLng.longitude,
    );
    return meters / 1000.0;
  }

  int get _etaMinutes {
    final base = (_distanceKm * 4.0).round().clamp(3, 999);
    return _fastRoute ? (base * 0.85).round().clamp(3, 999) : base;
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

    // Live updates
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((p) async {
      if (!mounted) return;
      setState(() => _currentPosition = p);

      // Update route during pickup/delivering
      if (_isPickup || _isDelivering) {
        await _buildRoute();
      }
    });

    // Initial route (optional)
    await _buildRoute();

    // Camera to user
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 15),
    );
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Please enable Location Services."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Location permission is required."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    return true;
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};

    // Destination marker (selected)
    markers.add(
      Marker(
        markerId: const MarkerId("selected_destination"),
        position: _destLatLng,
        infoWindow: InfoWindow(title: _selectedDestination.name, snippet: _selectedDestination.subtitle),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );

    // Current location marker (extra; Google also shows blue dot)
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
        width: 5,
        color: const Color(0xFF1FA9A7),
      ),
    };
  }

  void _onMapTap(LatLng tapped) async {
    setState(() {
      _customDestinationLatLng = tapped;

      // If user pins a new place, cancel pickup/deliver back to planning
      _tripStage = TripStage.planning;
    });

    await _buildRoute();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Custom drop-off pinned"), behavior: SnackBarBehavior.floating),
    );
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
      backgroundColor: const Color(0xFF111928),
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
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Icon(Icons.place_outlined, color: Color(0xFF10B981)),
                    SizedBox(width: 10),
                    Text("Choose destination", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                        color: selected ? const Color(0xFF10B981).o(0.15) : Colors.white.o(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? const Color(0xFF10B981).o(0.45) : Colors.white.o(0.06),
                        ),
                      ),
                      child: Icon(isPinned ? Icons.push_pin : Icons.recycling, color: const Color(0xFF10B981)),
                    ),
                    title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(d.subtitle),
                    trailing: selected
                        ? const Icon(Icons.check_circle, color: Color(0xFF10B981))
                        : const Icon(Icons.chevron_right),
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
      // Choosing any destination resets flow back to planning
      _tripStage = TripStage.planning;

      if (picked.name == "Pinned Drop-off") {
        // keep current pin active
      } else {
        _selectedDestination = picked;
        _customDestinationLatLng = null;
      }
    });

    await _buildRoute();
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(picked.latLng, 16));
  }

  void _selectPlastic(PlasticType type) {
    setState(() {
      _selectedPlastic = type;
      // Selecting plastic should not force deliver mode; go back to planning
      _tripStage = TripStage.planning;
    });
  }

  // ===== NEW FLOW BUTTON HANDLERS =====

  Future<void> _startPickup() async {
    setState(() => _tripStage = TripStage.pickup);
    await _buildRoute();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Pickup started — heading to ${_selectedDestination.name}"),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _arrivedDeliver() async {
    setState(() => _tripStage = TripStage.delivering);
    await _buildRoute();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Deliver mode — confirm drop-off."),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _finishDelivery() {
    setState(() => _tripStage = TripStage.planning);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Delivered — trip complete."),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _cancelPickup() {
    setState(() => _tripStage = TripStage.planning);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Pickup canceled."),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _buildRoute() async {
    // If you haven't set up Directions yet, quietly skip (no crash)
    if (_googleDirectionsApiKey == "PUT_YOUR_DIRECTIONS_API_KEY_HERE") {
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
        if (mounted) {
          setState(() => _routePoints = []);
          // keep this quiet if you prefer; leaving useful status for now
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Directions: ${data["status"]}"),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
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

    // Dynamic main button label based on stage
    final String primaryButtonLabel = _tripStage == TripStage.planning
        ? "START PICKUP"
        : _tripStage == TripStage.pickup
            ? "ARRIVED / DELIVER"
            : "FINISH DELIVERY";

    // Optional small secondary action while in pickup
    final bool showCancel = _tripStage == TripStage.pickup;

    return Scaffold(
      body: Stack(
        children: [
          // Google Map background
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

          // Status Bar Simulation
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              color: Colors.black.o(0.15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_timeString, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Row(
                    children: [
                      Icon(Icons.signal_cellular_alt, size: 14),
                      SizedBox(width: 4),
                      Icon(Icons.wifi, size: 14),
                      SizedBox(width: 4),
                      Icon(Icons.battery_full, size: 14),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Search Bar Area (tap works)
          Positioned(
            top: 60,
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("No screen to go back to."),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _openDestinationPicker,
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).o(0.92),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.o(0.10)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 18, color: Colors.blueGrey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              destinationTitle.isEmpty ? "Where to drop off?" : destinationTitle,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.tune, size: 16, color: Colors.blueGrey),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Sheet (EcoScrap style)
          DraggableScrollableSheet(
            initialChildSize: 0.44,
            minChildSize: 0.22,
            maxChildSize: 0.80,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF111928),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                  border: Border(top: BorderSide(color: Colors.white.o(0.10))),
                  boxShadow: [
                    BoxShadow(color: Colors.black.o(0.50), blurRadius: 40, offset: const Offset(0, -10)),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Set Pickup", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => setState(() => _fastRoute = !_fastRoute),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).o(_fastRoute ? 0.12 : 0.06),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF10B981).o(_fastRoute ? 0.25 : 0.12)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(radius: 3, backgroundColor: _fastRoute ? const Color(0xFF10B981) : Colors.white24),
                                const SizedBox(width: 6),
                                Text(
                                  _fastRoute ? "FAST ROUTE" : "NORMAL ROUTE",
                                  style: TextStyle(
                                    color: _fastRoute ? const Color(0xFF10B981) : Colors.white60,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Address Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.o(0.05),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.o(0.05)),
                      ),
                      child: Row(
                        children: [
                          Column(
                            children: [
                              const Icon(Icons.radio_button_checked, color: Colors.blue, size: 20),
                              Container(width: 1, height: 30, color: Colors.blue.o(0.30)),
                              const Icon(Icons.location_on, color: Color(0xFF10B981), size: 20),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "YOUR LOCATION",
                                  style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _locationReady && _currentPosition != null
                                      ? "${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}"
                                      : "Locating...",
                                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  "DESTINATION",
                                  style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  destinationTitle,
                                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                                ),
                                if (_customDestinationLatLng != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    "Pinned: ${_customDestinationLatLng!.latitude.toStringAsFixed(4)}, "
                                    "${_customDestinationLatLng!.longitude.toStringAsFixed(4)}",
                                    style: TextStyle(fontSize: 11, color: Colors.white.o(0.60)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Plastics-only chips
                    Row(
                      children: [
                        Expanded(
                          child: PlasticChip(
                            icon: Icons.local_drink_outlined,
                            label: "PET",
                            isSelected: _selectedPlastic == PlasticType.pet,
                            onTap: () => _selectPlastic(PlasticType.pet),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PlasticChip(
                            icon: Icons.kitchen_outlined,
                            label: "PP",
                            isSelected: _selectedPlastic == PlasticType.pp,
                            onTap: () => _selectPlastic(PlasticType.pp),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PlasticChip(
                            icon: Icons.water_drop_outlined,
                            label: "HDPE",
                            isSelected: _selectedPlastic == PlasticType.hdpe,
                            onTap: () => _selectPlastic(PlasticType.hdpe),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Stats Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _statItem(Icons.access_time, "${_etaMinutes} min"),
                        _statDivider(),
                        _statItem(Icons.navigation_outlined, "${_distanceKm.toStringAsFixed(1)} km"),
                        _statDivider(),
                        Text(
                          "₱${_earned.toStringAsFixed(2)} Earned",
                          style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Action Button (flow-based)
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (_tripStage == TripStage.planning) {
                            await _startPickup();
                          } else if (_tripStage == TripStage.pickup) {
                            await _arrivedDeliver(); // navbar returns here
                          } else {
                            _finishDelivery();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _tripStage == TripStage.pickup ? Colors.white : const Color(0xFF10B981),
                          foregroundColor: const Color(0xFF0F172A),
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
                        child: const Text("Cancel pickup", style: TextStyle(color: Colors.white70)),
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

      /// Navbar visibility rule:
      /// - Hidden only during pickup stage
      /// - Visible in planning and delivering
      bottomNavigationBar: _showNavbar ? _buildFooter() : null,
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
          color: const Color(0xFF0F172A).o(0.90),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.o(0.10)),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }

  Widget _statItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
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

  Widget _buildFooter() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.black,
      items: [
        _item(Icons.camera_alt_outlined, "Lens", 0),
        _item(Icons.home_outlined, "Home", 1),
        _item(Icons.map_outlined, "Map", 2),
      ],
    );
  }

  BottomNavigationBarItem _item(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;

    return BottomNavigationBarItem(
      label: "",
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1FA9A7) : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.black),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black),
            ),
          ],
        ),
      ),
    );
  }
}

class PlasticChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  const PlasticChip({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981).withValues(alpha: 31) : Colors.white.withValues(alpha: 13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981).withValues(alpha: 140) : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? const Color(0xFF10B981) : Colors.grey, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

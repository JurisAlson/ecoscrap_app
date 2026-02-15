import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class CollectorPickupMapPage extends StatefulWidget {
  final String requestId;
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;

  const CollectorPickupMapPage({
    super.key,
    required this.requestId,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
  });

  @override
  State<CollectorPickupMapPage> createState() => _CollectorPickupMapPageState();
}

class _CollectorPickupMapPageState extends State<CollectorPickupMapPage> {
  static const Color _bg = Color(0xFF0F172A);
  static const Color _accent = Color(0xFF1FA9A7);

  // ✅ put your Directions key
  static const String _directionsKey = "YOUR_DIRECTIONS_API_KEY";

  GoogleMapController? _map;
  Position? _pos;

  List<LatLng> _route = [];

  LatLng get _pickup => LatLng(widget.pickupLat, widget.pickupLng);
  LatLng get _origin => _pos == null ? _pickup : LatLng(_pos!.latitude, _pos!.longitude);

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final ok = await _ensureLocationPermission();
    if (!ok) return;

    final p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
    if (!mounted) return;
    setState(() => _pos = p);

    await _buildRoute();

    _map?.animateCamera(CameraUpdate.newLatLngZoom(_origin, 15));
  }

  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return false;

    return true;
  }

  Future<void> _buildRoute() async {
    if (_directionsKey == "YOUR_DIRECTIONS_API_KEY") return;

    final o = _origin;
    final d = _pickup;

    final uri = Uri.parse(
      "https://maps.googleapis.com/maps/api/directions/json"
      "?origin=${o.latitude},${o.longitude}"
      "&destination=${d.latitude},${d.longitude}"
      "&mode=driving"
      "&key=$_directionsKey",
    );

    try {
      final res = await http.get(uri);
      final data = jsonDecode(res.body) as Map<String, dynamic>;

      if (data["status"] != "OK") {
        if (!mounted) return;
        setState(() => _route = []);
        return;
      }

      final routes = (data["routes"] as List<dynamic>);
      if (routes.isEmpty) return;

      final encoded = routes.first["overview_polyline"]["points"] as String;
      final decoded = _decodePolyline(encoded);

      if (!mounted) return;
      setState(() => _route = decoded);
    } catch (_) {
      if (!mounted) return;
      setState(() => _route = []);
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
    final markers = <Marker>{
      Marker(markerId: const MarkerId("pickup"), position: _pickup, infoWindow: InfoWindow(title: "Pickup", snippet: widget.pickupAddress)),
      if (_pos != null) Marker(markerId: const MarkerId("me"), position: _origin, infoWindow: const InfoWindow(title: "You")),
    };

    final polylines = _route.isEmpty
        ? <Polyline>{}
        : {
            Polyline(
              polylineId: const PolylineId("route"),
              points: _route,
              width: 6,
              color: _accent,
            )
          };

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: const Text("Go to Pickup"),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: _pickup, zoom: 15),
              onMapCreated: (c) => _map = c,
              myLocationEnabled: _pos != null,
              markers: markers,
              polylines: polylines,
              zoomControlsEnabled: false,
            ),
          ),
  
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                widget.pickupAddress.isEmpty ? "Pickup address: Unknown" : "Pickup address:\n${widget.pickupAddress}",
                style: const TextStyle(color: Colors.white),
              ),
            ),
          )
        ],
      ),
    );
  }
}
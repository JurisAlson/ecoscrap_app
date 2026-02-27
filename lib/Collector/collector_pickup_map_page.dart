import 'dart:convert';
import 'dart:ui';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ✅ chat imports
import '../chat/services/chat_services.dart';
import '../chat/screens/chat_page.dart';

class CollectorPickupMapPage extends StatefulWidget {
  final String requestId;

  const CollectorPickupMapPage({
    super.key,
    required this.requestId,
  });

  @override
  State<CollectorPickupMapPage> createState() => _CollectorPickupMapPageState();
}

class _CollectorPickupMapPageState extends State<CollectorPickupMapPage> {
  GeoPoint? _pickupGp;
  String _pickupAddress = "";
  String _householdName = "Household";
  String _status = "";

  // ✅ IDs from request doc
  String _householdId = "";
  String _collectorId = "";

  static const Color _bg = Color(0xFF0F172A);
  static const Color _accent = Color(0xFF1FA9A7);

  GoogleMapController? _map;
  Position? _pos;

  List<LatLng> _route = [];

  // route stats
  String _distanceText = "";
  String _durationText = "";
  int? _durationValueSec;

  // ✅ chat service
  final ChatService _chat = ChatService();

  LatLng get _pickup {
    final gp = _pickupGp;
    if (gp == null) return const LatLng(0, 0);
    return LatLng(gp.latitude, gp.longitude);
  }

  LatLng get _origin => _pos == null ? _pickup : LatLng(_pos!.latitude, _pos!.longitude);

  @override
  void initState() {
    super.initState();
    _loadRequestInfo();
    _initLocation();
  }

  Future<void> _loadRequestInfo() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('requests').doc(widget.requestId).get();
      final data = doc.data() ?? {};
      final gp = data['pickupLocation'];

      if (!mounted) return;

      setState(() {
        _householdName = (data['householdName'] ?? 'Household').toString();
        _pickupAddress = (data['pickupAddress'] ?? '').toString();
        _status = (data['status'] ?? '').toString();
        _pickupGp = (gp is GeoPoint) ? gp : null;

        _householdId = (data['householdId'] ?? '').toString();
        _collectorId = (data['collectorId'] ?? '').toString();
      });

      if (_pickupGp != null && _pos != null) {
        await _buildRoute();
        _map?.animateCamera(CameraUpdate.newLatLngZoom(_origin, 15));
      }
    } catch (e) {
      // optional
    }
  }

  Future<void> _initLocation() async {
    final ok = await _ensureLocationPermission();
    if (!ok) return;

    final p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
    if (!mounted) return;
    setState(() => _pos = p);

    if (_pickupGp != null) {
      await _buildRoute();
      _map?.animateCamera(CameraUpdate.newLatLngZoom(_origin, 15));
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return false;

    return true;
  }

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  Future<void> _buildRoute() async {
    final o = _origin;
    final d = _pickup;

    try {
      final callable = _functions.httpsCallable('getDirections');
      final result = await callable.call({
        'origin': '${o.latitude},${o.longitude}',
        'destination': '${d.latitude},${d.longitude}',
        'mode': 'driving',
      });

      final data = result.data;
      if (data is! Map) return;

      final points = data['points'] as String?;
      final dist = (data['distanceText'] ?? '').toString();
      final dur = (data['durationText'] ?? '').toString();
      final durVal = data['durationValueSec'];

      if (points == null || points.isEmpty) {
        if (!mounted) return;
        setState(() {
          _route = [];
          _distanceText = "";
          _durationText = "";
          _durationValueSec = null;
        });
        return;
      }

      final decoded = _decodePolyline(points);

      if (!mounted) return;
      setState(() {
        _route = decoded;
        _distanceText = dist;
        _durationText = dur;
        _durationValueSec = (durVal is int) ? durVal : null;
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint("❌ getDirections failed: ${e.code} ${e.message}");
    } catch (e) {
      debugPrint("❌ getDirections crashed: $e");
    }
  }

  Future<void> _openGoogleMapsNavigation() async {
    final gp = _pickupGp;
    if (gp == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Pickup location not loaded yet.")),
      );
      return;
    }

    final url = Uri.parse(
      "https://www.google.com/maps/dir/?api=1"
      "&destination=${gp.latitude},${gp.longitude}"
      "&travelmode=driving",
    );

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open Google Maps.")),
      );
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

  // ✅ pickup chat only when accepted/arrived
  Future<void> _openPickupChat() async {
    final s = _status.toLowerCase();
    final canChat = s == "accepted" || s == "arrived";

    if (!canChat) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat is available once pickup is accepted.")),
      );
      return;
    }

    final me = FirebaseAuth.instance.currentUser?.uid ?? "";
    final householdUid = _householdId.trim();
    final collectorUid = _collectorId.trim().isNotEmpty ? _collectorId.trim() : me;

    if (householdUid.isEmpty || collectorUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat IDs not loaded yet. Please try again.")),
      );
      return;
    }

    final chatId = await _chat.ensurePickupChat(
      requestId: widget.requestId,
      householdUid: householdUid,
      collectorUid: collectorUid,
    );

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          chatId: chatId,
          title: _householdName.isEmpty ? "Chat" : _householdName,
          otherUserId: householdUid,
        ),
      ),
    );
  }

  /// ✅ ARRIVED -> COMPLETE (and delete chats)
  Future<void> _markArrivedOrComplete() async {
    final s = _status.toLowerCase();

    // COMPLETE
    if (s == 'arrived') {
      try {
        await FirebaseFirestore.instance.collection('requests').doc(widget.requestId).update({
          'status': 'completed',
          'active': false,
          'completedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),

          'junkshopId': "07Wi7N8fALh2yqNdt1CQgIYVGE43",
          'junkshopName': "Mores Scrap",
        });

        // ✅ delete both chats tied to request
        final requestId = widget.requestId;
        // await _chat.deleteChat("pickup_$requestId");
        // await _chat.deleteChat("junkshop_pickup_$requestId");

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Marked as completed.")),
        );
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Complete failed: $e")),
        );
      }
      return;
    }

    // ARRIVED
    try {
      await FirebaseFirestore.instance.collection('requests').doc(widget.requestId).update({
        'status': 'arrived',
        'arrived': true,
        'arrivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => _status = 'arrived');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Marked as arrived.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId("pickup"),
        position: _pickup,
        infoWindow: InfoWindow(title: "Pickup", snippet: _pickupAddress),
      ),
      if (_pos != null)
        Marker(
          markerId: const MarkerId("me"),
          position: _origin,
          infoWindow: const InfoWindow(title: "You"),
        ),
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withOpacity(0.10)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _accent.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.home_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _householdName.isEmpty ? "Household" : _householdName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  _pickupAddress.isEmpty ? "Unknown address" : _pickupAddress,
                                  style: TextStyle(
                                    color: Colors.grey.shade300,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _miniStat(Icons.access_time, _durationText.isEmpty ? "—" : _durationText),
                            _miniStat(Icons.navigation_outlined, _distanceText.isEmpty ? "—" : _distanceText),
                            _miniStat(Icons.route, _route.isEmpty ? "No route" : "Route ready"),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _openGoogleMapsNavigation,
                                icon: const Icon(Icons.directions),
                                label: const Text("NAVIGATE"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: _bg,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _openPickupChat,
                                icon: const Icon(Icons.chat_bubble_outline),
                                label: const Text("CHAT"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: _bg,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: _markArrivedOrComplete,
                                icon: Icon(_status.toLowerCase() == 'arrived'
                                    ? Icons.check_circle
                                    : Icons.location_on_outlined),
                                label: Text(_status.toLowerCase() == 'arrived' ? "COMPLETE" : "ARRIVED"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: _bg,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
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
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
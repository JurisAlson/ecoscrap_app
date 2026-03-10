import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

extension TrackingOpacityFix on Color {
  Color o(double opacity) =>
      withValues(alpha: ((opacity * 255).clamp(0, 255)).toDouble());
}

class CollectorTrackingPage extends StatefulWidget {
  final String requestId;

  const CollectorTrackingPage({
    super.key,
    required this.requestId,
  });

  @override
  State<CollectorTrackingPage> createState() => _CollectorTrackingPageState();
}

class _CollectorTrackingPageState extends State<CollectorTrackingPage> {
  // ===== Theme =====
  static const Color _bg = Color(0xFF0B1220);
  static const Color _sheet = Color(0xFF121C2E);
  static const Color _surface = Color(0xFF162235);
  static const Color _surfaceAlt = Color(0xFF1B2A40);
  static const Color _border = Color(0xFF26364F);
  static const Color _accent = Color(0xFF10B981);
  static const Color _blue = Color(0xFF60A5FA);
  static const Color _warning = Color(0xFFF59E0B);
  static const Color _danger = Color(0xFFEF4444);

  static const Color _textPrimary = Color(0xFFE2E8F0);
  static const Color _textSecondary = Color(0xFF94A3B8);
  static const Color _textMuted = Color(0xFF64748B);

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

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  GoogleMapController? _mapController;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _requestSub;

  LatLng? _pickupLatLng;
  LatLng? _destinationLatLng;
  LatLng? _collectorLatLng;

  String _collectorName = "Collector";
  String _status = "";
  String _pickupSource = "";
  String _street = "";
  String _subdivision = "";
  String _landmark = "";
  String _phoneNumber = "";

  List<LatLng> _collectorRoutePoints = [];

  bool _initialFitDone = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _listenToRequest();
  }

  @override
  void dispose() {
    _requestSub?.cancel();
    _mapController?.dispose();
    super.dispose();
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

    _requestSub = FirebaseFirestore.instance
        .collection('requests')
        .doc(widget.requestId)
        .snapshots()
        .listen((doc) async {
      if (!doc.exists) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      final data = doc.data() ?? {};

      final pickupGp = data['pickupLocation'];
      final destinationGp = data['destinationLocation'];
      final collectorGp = data['collectorLocation'];

      LatLng? pickup;
      LatLng? destination;
      LatLng? collector;

      if (pickupGp is GeoPoint) {
        pickup = LatLng(pickupGp.latitude, pickupGp.longitude);
      }
      if (destinationGp is GeoPoint) {
        destination = LatLng(destinationGp.latitude, destinationGp.longitude);
      }
      if (collectorGp is GeoPoint) {
        collector = LatLng(collectorGp.latitude, collectorGp.longitude);
      }

      final previousCollectorWasNull = _collectorLatLng == null;

      if (!mounted) return;
      setState(() {
        _pickupLatLng = pickup;
        _destinationLatLng = destination;
        _collectorLatLng = collector;
        _collectorName = (data['collectorName'] ?? 'Collector').toString();
        _status = (data['status'] ?? '').toString().trim().toLowerCase();
        _pickupSource = (data['pickupSource'] ?? '').toString();
        _street = (data['street'] ?? '').toString();
        _subdivision = (data['subdivision'] ?? '').toString();
        _landmark = (data['landmark'] ?? '').toString();
        _phoneNumber = (data['phoneNumber'] ?? '').toString();
        _loading = false;
      });

      if (_collectorLatLng != null && _pickupLatLng != null) {
        await _buildCollectorRouteToPickup(
          collectorLatLng: _collectorLatLng!,
          pickupLatLng: _pickupLatLng!,
        );
      } else {
        if (!mounted) return;
        setState(() => _collectorRoutePoints = []);
      }

      if (!_initialFitDone && _pickupLatLng != null) {
        if (_collectorLatLng != null || _mapController != null) {
          await _fitMap();
          _initialFitDone = true;
        }
      } else if (previousCollectorWasNull && _collectorLatLng != null) {
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
      debugPrint("collector route failed: $e");
      if (!mounted) return;
      setState(() => _collectorRoutePoints = []);
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

    final south = pickup.latitude < collector.latitude
        ? pickup.latitude
        : collector.latitude;
    final north = pickup.latitude > collector.latitude
        ? pickup.latitude
        : collector.latitude;
    final west = pickup.longitude < collector.longitude
        ? pickup.longitude
        : collector.longitude;
    final east = pickup.longitude > collector.longitude
        ? pickup.longitude
        : collector.longitude;

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
          markerId: const MarkerId('pickup'),
          position: _pickupLatLng!,
          infoWindow: const InfoWindow(
            title: 'Pickup Location',
            snippet: 'Household pickup point',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
        ),
      );
    }

    if (_destinationLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('junkshop'),
          position: _destinationLatLng!,
          infoWindow: const InfoWindow(
            title: 'Mores Scrap Trading',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }

    if (_collectorLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('collector'),
          position: _collectorLatLng!,
          infoWindow: InfoWindow(
            title: _collectorName,
            snippet: 'Approaching pickup location',
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
    if (_collectorRoutePoints.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId('collector_route'),
        points: _collectorRoutePoints,
        width: 6,
        color: _blue,
      ),
    };
  }

  String get _statusLabel {
    switch (_status) {
      case 'pending':
        return 'Waiting for collector';
      case 'scheduled':
        return 'Pickup scheduled';
      case 'accepted':
        return 'Collector accepted your request';
      case 'confirmed':
        return 'Pickup confirmed';
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
      case 'confirmed':
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
      case 'confirmed':
        return Icons.thumb_up_alt_outlined;
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
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
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
                  const Expanded(
                    child: Text(
                      "Track Collector",
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
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

  Widget _statusPanel() {
    final address = [
      if (_street.trim().isNotEmpty) _street.trim(),
      if (_subdivision.trim().isNotEmpty) _subdivision.trim(),
    ].join(", ");

    return DraggableScrollableSheet(
      initialChildSize: 0.33,
      minChildSize: 0.20,
      maxChildSize: 0.62,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: _sheet.o(0.97),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(34)),
                border: const Border(
                  top: BorderSide(color: _border),
                ),
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
                              _collectorLatLng != null
                                  ? "${_collectorName.isEmpty ? 'Collector' : _collectorName} is sharing live location"
                                  : "Waiting for collector location update",
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
                    icon: Icons.person_outline,
                    label: "COLLECTOR",
                    value: _collectorName.isEmpty ? "Collector" : _collectorName,
                    valueColor: _textPrimary,
                  ),
                  const SizedBox(height: 12),
                  _infoTile(
                    icon: Icons.place_outlined,
                    label: "PICKUP LOCATION",
                    value: address.isEmpty ? "Pinned / GPS pickup location" : address,
                    valueColor: _textPrimary,
                  ),
                  const SizedBox(height: 12),
                  _infoTile(
                    icon: Icons.flag_outlined,
                    label: "PICKUP SOURCE",
                    value: _pickupSource == "pin"
                        ? "Pinned location"
                        : (_pickupSource == "gps" ? "Current location" : "Not specified"),
                    valueColor: _textPrimary,
                  ),

                  if (_landmark.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _infoTile(
                      icon: Icons.landscape_outlined,
                      label: "LANDMARK",
                      value: _landmark,
                      valueColor: _textPrimary,
                    ),
                  ],

                  if (_phoneNumber.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _infoTile(
                      icon: Icons.phone_outlined,
                      label: "PHONE",
                      value: _phoneNumber,
                      valueColor: _textPrimary,
                    ),
                  ],

                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(
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
                      const SizedBox(width: 12),
                      Expanded(
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
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
    final initialTarget =
        _pickupLatLng ?? const LatLng(14.18695, 121.11299);

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
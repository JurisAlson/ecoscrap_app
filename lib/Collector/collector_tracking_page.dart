import 'dart:async';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:ui' as ui;

extension TrackingOpacityFix on Color {
  Color o(double opacity) =>
      withValues(alpha: ((opacity * 255).clamp(0, 255)).toDouble());
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

  bool _markingArrived = false;
  bool _collectorArrivedToMores = false;
  bool _sellTransactionAudited = false;

  bool get _isFixedDestinationMode => widget.fixedDestination != null;
  bool get _hasValidRequestId =>
      widget.requestId != null && widget.requestId!.trim().isNotEmpty;

  String get _displayCollectorName =>
      _collectorName.isEmpty ? "Collector" : _collectorName;

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
  String get _sourceLabel =>
    widget.trackingType == "sell" ? "TRIP TYPE" : "PICKUP SOURCE";

  String get _liveStatusText {
    if (_collectorLatLng != null) {
      return _isFixedDestinationMode
          ? "Live route to ${widget.destinationTitle}"
          : "$_displayCollectorName is sharing live location";
    }

    return _isFixedDestinationMode
        ? "Waiting for your current location"
        : "Waiting for collector location update";
  }
  String _routeDistanceText = "";
  String _routeDurationText = "";
  

  String get _topBarTitle =>
      _isFixedDestinationMode ? "Route to ${widget.destinationTitle}" : "Track Collector";

  String get _pickupMarkerTitle =>
      _isFixedDestinationMode ? widget.destinationTitle : 'PICKUP';

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
  LatLng? _collectorLatLng;

  String _collectorName = "Collector";
  String _status = "";
  String _pickupSource = "";
  String _street = "";
  String _subdivision = "";
  String _landmark = "";
  String _phoneNumber = "";

  Position? _myPosition;
  LatLng? _myLatLng;

  List<LatLng> _collectorRoutePoints = [];

  bool _initialFitDone = false;
  bool _loading = true;

  double _collectorHeading = 0;
  BitmapDescriptor? _collectorIcon;
  BitmapDescriptor? _householdMarkerIcon; 

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sellRequestSub;
  void _listenToSellRequest() {
    if (widget.sellRequestId == null || widget.sellRequestId!.trim().isEmpty) {
      return;
    }

    _sellRequestSub?.cancel();

    _sellRequestSub = FirebaseFirestore.instance
        .collection('Users')
        .doc(_moresUid)
        .collection('sell_requests')
        .doc(widget.sellRequestId!)
        .snapshots()
        .listen((doc) async {
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

      if (audited) {
        await _restoreCollectorAvailability();
      }
    });
  }
  @override
  void initState() {
    super.initState();
    _initPage();

    if (widget.trackingType == "sell") {
      _listenToSellRequest();
    }
  }
Future<void> _restoreCollectorAvailability() async {
  final collectorId = FirebaseAuth.instance.currentUser?.uid;
  if (collectorId == null) return;

  await FirebaseFirestore.instance
      .collection('Users')
      .doc(collectorId)
      .set({
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
      _collectorName = "You";
      _status = "ongoing";
      _pickupSource = "fixed_destination";
      _street = widget.destinationAddress;
      _subdivision = "";
      _landmark = "";
      _phoneNumber = "";
      _loading = false;
    });

    if (_collectorLatLng != null) {
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
      await FirebaseFirestore.instance
          .collection('Users')
          .doc(_moresUid)
          .collection('sell_requests')
          .doc(widget.sellRequestId!)
          .update({
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
await FirebaseFirestore.instance
    .collection('Users')
    .doc(_moresUid)
    .collection('sell_requests')
    .doc(widget.sellRequestId!)
    .update({
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
  Future<void> _initPage() async {
    await _loadCollectorIcon();
    await _initMyLocation();

    if (_isFixedDestinationMode) {
      await _setupFixedDestinationMode();
    } else {
      _listenToRequest();
    }
  }
  Future<BitmapDescriptor> _iconToMarker({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required Color borderColor,
    double size = 112,
    double iconSize = 54,
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
    );

    painter.paint(canvas, Size(size, size));

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  @override
  void dispose() {
    _requestSub?.cancel();
    _sellRequestSub?.cancel();
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

  Future<void> _loadCollectorIcon() async {
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

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint("❌ Failed to build marker icons: $e");
    }
  }

  void _listenToRequest() {
    _requestSub?.cancel();

    if (!_hasValidRequestId) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    _requestSub = FirebaseFirestore.instance
        .collection('requests')
        .doc(widget.requestId!)
        .snapshots()
        .listen((doc) async {
      if (!doc.exists) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      final data = doc.data() ?? {};

      final pickupGp = data['pickupLocation'];
      final collectorGp =
          data['collectorLiveLocation'] ?? data['collectorLocation'];

      final headingRaw = data['collectorHeading'];
      double heading = 0;
      if (headingRaw is num) {
        heading = headingRaw.toDouble();
      }

      debugPrint('collectorGp: $collectorGp');
      debugPrint('headingRaw: $headingRaw');

      LatLng? pickup;
      LatLng? collector;

      if (pickupGp is GeoPoint) {
        pickup = LatLng(pickupGp.latitude, pickupGp.longitude);
      }
      if (collectorGp is GeoPoint) {
        collector = LatLng(collectorGp.latitude, collectorGp.longitude);
      }

      final previousCollectorWasNull = _collectorLatLng == null;

      if (!mounted) return;
      setState(() {
        _pickupLatLng = pickup;
        _collectorLatLng = collector;
        _collectorName = (data['collectorName'] ?? 'Collector').toString();
        _status = (data['status'] ?? '').toString().trim().toLowerCase();
        _pickupSource = (data['pickupSource'] ?? '').toString();
        _street = (data['street'] ?? '').toString();
        _subdivision = (data['subdivision'] ?? '').toString();
        _landmark = (data['landmark'] ?? '').toString();
        _phoneNumber = (data['phoneNumber'] ?? '').toString();
        _collectorHeading = heading;
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

      debugPrint('request data: $data');
      debugPrint('collectorLiveLocation: ${data['collectorLiveLocation']}');
      debugPrint('collectorLocation: ${data['collectorLocation']}');
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

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
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
        _myPosition = pos;
        _myLatLng = LatLng(pos.latitude, pos.longitude);
      });
    } catch (e) {
      debugPrint("household current location error: $e");
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
          infoWindow: InfoWindow(title: _pickupMarkerTitle),
          icon: _householdMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
          zIndex: 1,
        ),
      );
    }

    if (_collectorLatLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('collector'),
          position: _collectorLatLng!,
          infoWindow: InfoWindow(title: _displayCollectorName),
          icon: _collectorIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          zIndex: 3,
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

  Widget _statusPanel() {
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
                    icon: Icons.person_outline,
                    label: "COLLECTOR",
                    value: _displayCollectorName,
                    valueColor: _textPrimary,
                  ),
                  const SizedBox(height: 12),
                  _infoTile(
                    icon: Icons.place_outlined,
                    label: _locationSectionLabel,
                    value: _locationSectionValue,
                    valueColor: _textPrimary,
                  ),
                  const SizedBox(height: 12),
                  _infoTile(
                    icon: Icons.flag_outlined,
                    label: _sourceLabel,
                    value: widget.trackingType == "sell"
                        ? "Collector to junkshop"
                        : (_pickupSource == "pin"
                            ? "Pinned location"
                            : (_pickupSource == "gps"
                                ? "Current location"
                                : "Not specified")),
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
                        child: _infoTile(
                          icon: Icons.route_outlined,
                          label: "DISTANCE",
                          value: _routeDistanceText.isEmpty ? "Calculating..." : _routeDistanceText,
                          valueColor: _textPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _infoTile(
                          icon: Icons.schedule_outlined,
                          label: "ETA",
                          value: _routeDurationText.isEmpty ? "Calculating..." : _routeDurationText,
                          valueColor: _textPrimary,
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

                  if (widget.trackingType == "sell") ...[
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

  _TrackingMarkerPainter({
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
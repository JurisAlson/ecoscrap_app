import 'dart:ui';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'collector_transaction_page.dart';
import 'dart:async';

// ✅ chat imports
import '../chat/services/chat_services.dart';
import '../chat/screens/chat_page.dart';

extension OpacityFix on Color {
  Color o(double opacity) =>
      withValues(alpha: ((opacity * 255).clamp(0, 255)).toDouble());
}


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
  String _bagLabel = "";
  int? _bagKg;
  bool _topExpanded = false;
  bool _hasCollectorReceipt = false;  
  StreamSubscription<DocumentSnapshot>? _reqSub;
  bool _junkshopChatEnsured = false; // (optional) prevent repeated ensure calls
  

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

  LatLng get _origin =>
      _pos == null ? _pickup : LatLng(_pos!.latitude, _pos!.longitude);

  @override
  void initState() {
    super.initState();
    _loadRequestInfo();
    _initLocation();
  }
  @override
  void dispose() {
    _reqSub?.cancel();
    super.dispose();
  }

  Future<void> _loadRequestInfo() async {
    try {
      await _reqSub?.cancel(); // safety if called again

      _reqSub = FirebaseFirestore.instance
          .collection('requests')
          .doc(widget.requestId)
          .snapshots()
          .listen((doc) async {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final gp = data['pickupLocation'];

        if (!mounted) return;

        setState(() {
          _householdName = (data['householdName'] ?? 'Household').toString();
          _pickupAddress = (data['pickupAddress'] ?? '').toString();
          _status = (data['status'] ?? '').toString();
          _pickupGp = (gp is GeoPoint) ? gp : null;

          _bagLabel = (data['bagLabel'] ?? '').toString();
          _bagKg = (data['bagKg'] is int)
              ? data['bagKg'] as int
              : int.tryParse((data['bagKg'] ?? '').toString());

          _householdId = (data['householdId'] ?? '').toString();
          _collectorId = (data['collectorId'] ?? '').toString();
          _hasCollectorReceipt = (data['hasCollectorReceipt'] == true);
        });

        // ✅ Build route once we have both pickup + my location
        if (_pickupGp != null && _pos != null) {
          await _buildRoute();
          _map?.animateCamera(CameraUpdate.newLatLngZoom(_origin, 15));
        }

        // ✅ Ensure collector↔junkshop chat only once and only when allowed
        final s = _status.toLowerCase();
        if (!_junkshopChatEnsured &&
            (s == "accepted" || s == "arrived" || s == "scheduled")) {
          final me = FirebaseAuth.instance.currentUser?.uid ?? "";
          final collectorUid = _collectorId.trim().isNotEmpty ? _collectorId.trim() : me;

          if (collectorUid.isNotEmpty) {
            _junkshopChatEnsured = true;
            try {
              const junkshopUid = "07Wi7N8fALh2yqNdt1CQgIYVGE43";
              await _chat.ensureJunkshopChatForRequest(
                requestId: widget.requestId,
                junkshopUid: junkshopUid,
                collectorUid: collectorUid,
              );
            } catch (e) {
              debugPrint("❌ ensureJunkshopChatForRequest failed: $e");
            }
          }
        }
      });
    } catch (e) {
      debugPrint("❌ _loadRequestInfo error: $e");
    }
  }
  Future<void> _initLocation() async {
    final ok = await _ensureLocationPermission();
    if (!ok) return;

    final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best);
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
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return false;
    }
    return true;
  }

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

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

  /// ✅ Pickup chat available only when accepted/arrived
  /// ✅ Collector opens chat with the household as "otherUserId"
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
    var collectorUid = _collectorId.trim();

    if (me.isEmpty || householdUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat IDs not loaded yet. Please try again.")),
      );
      return;
    }

    // ✅ If request has no collectorId yet, assign it to me (collector)
    if (collectorUid.isEmpty) {
      collectorUid = me;
      try {
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(widget.requestId)
            .update({
          'collectorId': me,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (mounted) setState(() => _collectorId = me);
      } catch (e) {
        debugPrint("❌ Failed to write collectorId: $e");
      }
    }

    if (collectorUid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Collector not assigned yet.")),
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

          // ✅ Collector sees the household name
          title: _householdName.isEmpty ? "Household" : _householdName,

          // ✅ Important: other user is the household
          otherUserId: householdUid,
        ),
      ),
    );
  }

  Future<void> _openCollectorReceipt() async {
    final s = _status.toLowerCase();
    if (s != "arrived") {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Create receipt is available once you are ARRIVED.")),
      );
      return;
    }

    // Optional: block if already has receipt
    try {
      final reqDoc = await FirebaseFirestore.instance
          .collection('requests')
          .doc(widget.requestId)
          .get();

      final data = reqDoc.data() ?? {};
      final hasReceipt = data['hasCollectorReceipt'] == true;

      if (hasReceipt) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Receipt already created for this pickup.")),
        );
        return;
      }
    } catch (_) {
      // ignore and still allow
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CollectorTransactionPage(
        requestId: widget.requestId, // ✅ pass arrived requestId
        embedded: false,             // ✅ full page with AppBar
        ),
      ),
    );
  }

  Future<void> _markArrivedOrComplete() async {
    final s = _status.toLowerCase();

    // COMPLETE
    if (s == 'arrived') {
      try {
        await FirebaseFirestore.instance
            .collection('requests')
            .doc(widget.requestId)
            .update({
          'status': 'completed',
          'active': false,
          'completedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'junkshopId': "07Wi7N8fALh2yqNdt1CQgIYVGE43",
          'junkshopName': "Mores Scrap",
        });

        // ✅ delete both chats tied to request
        final requestId = widget.requestId;
        await _chat.cleanupPickupChats(requestId);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Marked as completed.")),
        );
        Navigator.pop(context);
      } on FirebaseException catch (e) {
        debugPrint("❌ Complete failed: ${e.code} | ${e.message}");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Complete failed: ${e.code}")),
        );
      } catch (e) {
        debugPrint("❌ Complete failed: $e");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Complete failed: $e")),
        );
      }
      return;
    }

    // ARRIVED
    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(widget.requestId)
          .update({
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
    } on FirebaseException catch (e) {
      debugPrint("❌ Arrived failed: ${e.code} | ${e.message}");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Arrived failed: ${e.code}")),
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
      body: Stack(
        children: [
          // MAP
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: _pickup, zoom: 15),
              onMapCreated: (c) => _map = c,
              myLocationEnabled: _pos != null,
              markers: markers,
              polylines: polylines,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // ✅ TOP BAR (Uniform with GeoMapping)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      _circularButton(
                        Icons.arrow_back,
                        onTap: () {
                          if (Navigator.of(context).canPop()) Navigator.pop(context);
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _topExpanded = !_topExpanded),
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: _topExpanded ? 160 : 56,
                              ),
                              child: _glass(
                                radius: 16,
                                blur: 12,
                                opacity: 0.55,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.local_shipping, size: 18, color: _accent),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _householdName.isEmpty ? "Pickup Request" : _householdName,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(
                                          _topExpanded ? Icons.expand_less : Icons.expand_more,
                                          color: Colors.white.withOpacity(0.85),
                                          size: 20,
                                        ),
                                      ],
                                    ),

                                    if (_topExpanded) ...[
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          physics: const BouncingScrollPhysics(),
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              _pillChip(
                                                icon: Icons.inventory_2_outlined,
                                                text: _bagLabel.isEmpty
                                                    ? "Bag: —"
                                                    : "Bag: $_bagLabel${_bagKg == null ? "" : " (${_bagKg}kg)"}",
                                              ),
                                              _pillChip(
                                                icon: Icons.info_outline,
                                                text: _status.isEmpty
                                                    ? "Status: —"
                                                    : "Status: ${_status.toUpperCase()}",
                                              ),
                                              _pillChip(
                                                icon: Icons.place_outlined,
                                                text: _pickupAddress.isEmpty
                                                    ? "Address: —"
                                                    : _pickupAddress,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ✅ BOTTOM DRAGGABLE DRAWER
          DraggableScrollableSheet(
            initialChildSize: 0.26,
            minChildSize: 0.18,
            maxChildSize: 0.72,
            builder: (context, scrollController) {
              return ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                      border: Border(
                        top: BorderSide(color: Colors.white.withOpacity(0.10)),
                      ),
                    ),
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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

                        // Route stats (no coordinates shown)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111928),
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

                        // Actions (nice tiles)
                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _actionWide(
                                    icon: Icons.chat_bubble_outline,
                                    title: "CHAT",
                                    subtitle: "Message household",
                                    bg: Colors.white.withOpacity(0.10),
                                    fg: Colors.white,
                                    border: Colors.white.withOpacity(0.14),
                                    onTap: _openPickupChat,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _actionWide(
                                    icon: _status.toLowerCase() == 'arrived'
                                        ? Icons.check_circle
                                        : Icons.location_on_outlined,
                                    title: _status.toLowerCase() == 'arrived' ? "COMPLETE" : "ARRIVED",
                                    subtitle: _status.toLowerCase() == 'arrived'
                                        ? "Finish pickup"
                                        : "Mark arrival",
                                    bg: _accent,
                                    fg: _bg,
                                    onTap: _markArrivedOrComplete,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // ✅ Receipt button goes UNDER the row
                            if (_status.toLowerCase() == "arrived")
                            _actionWide(
                              icon: (_hasCollectorReceipt == true) ? Icons.receipt : Icons.receipt_long,
                              title: (_hasCollectorReceipt == true) ? "RECEIPT SAVED" : "RECEIPT",
                              subtitle: (_hasCollectorReceipt == true) ? "Already created" : "Create buying receipt",
                              bg: Colors.white.withOpacity(0.10),
                              fg: Colors.white,
                              border: Colors.white.withOpacity(0.14),
                              onTap: (_hasCollectorReceipt == true) ? null : _openCollectorReceipt,
                            ),
                          ],
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

  Widget _glass({
    required Widget child,
    double blur = 12,
    double opacity = 0.55,
    double radius = 16,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(opacity),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: child,
        ),
      ),
    );
  }

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
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }

  Widget _pillChip({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withOpacity(0.90)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionWide({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color bg,
    required Color fg,
    Color? border,
    VoidCallback? onTap, // ✅ nullable
  }) {
    final disabled = onTap == null;

    return Opacity(
      opacity: disabled ? 0.55 : 1.0, // ✅ dim when disabled
      child: InkWell(
        onTap: onTap, // ✅ null disables tap + ripple
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: (border ?? Colors.white.withOpacity(0.10))
                  .withOpacity(disabled ? 0.55 : 1.0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(disabled ? 0.10 : 0.18),
                blurRadius: 14,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(
                    disabled ? 0.10 : (bg == Colors.white || bg == _accent ? 0.06 : 0.18),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: fg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg.withOpacity(0.80),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
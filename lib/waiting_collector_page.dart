import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';


class WaitingCollectorPage extends StatefulWidget {
  final String requestId;
  final LatLng pickupLatLng;
  final LatLng destinationLatLng;

  const WaitingCollectorPage({
    super.key,
    required this.requestId,
    required this.pickupLatLng,
    required this.destinationLatLng,
  });

  @override
  State<WaitingCollectorPage> createState() => _WaitingCollectorPageState();
}

class _WaitingCollectorPageState extends State<WaitingCollectorPage>
    with TickerProviderStateMixin {
  static const Color _bg = Color(0xFF0B1220);
  static const Color _sheet = Color(0xFF121C2E);
  static const Color _surface = Color(0xFF162235);
  static const Color _border = Color(0xFF26364F);
  static const Color _accent = Color(0xFF10B981);
  static const Color _textPrimary = Color(0xFFE2E8F0);
  static const Color _textSecondary = Color(0xFF94A3B8);

  GoogleMapController? _mapController;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _requestSub;
  bool _hasNavigated = false;

  late final AnimationController _pulseController;

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

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _listenToRequest();
  }

  void _goToOrderTab() {
    if (!mounted || _hasNavigated) return;

    _hasNavigated = true;
    _requestSub?.cancel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop('accepted');
    });
  }

  void _closeWaitingPage() {
    if (!mounted || _hasNavigated) return;

    _hasNavigated = true;
    _requestSub?.cancel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop();
    });
  }

  void _listenToRequest() {
    _requestSub = FirebaseFirestore.instance
        .collection('requests')
        .doc(widget.requestId)
        .snapshots()
        .listen(
      (doc) {
        if (!mounted || _hasNavigated) return;
        if (!doc.exists) return;

        final data = doc.data() ?? {};
        final status = (data['status'] ?? '').toString().trim().toLowerCase();

        if (status == 'accepted' ||
            status == 'confirmed' ||
            status == 'ongoing' ||
            status == 'arrived') {
          _goToOrderTab();
          return;
        }

        if (status == 'cancelled' ||
            status == 'canceled' ||
            status == 'rejected' ||
            status == 'declined') {
          _closeWaitingPage();
        }
      },
      onError: (error) {
        debugPrint('WaitingCollectorPage stream error: $error');
      },
    );
  }

  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapController = controller;
    await controller.setMapStyle(_darkMapStyle);
  }

  Set<Marker> _buildMarkers() {
    return {
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destinationLatLng,
        infoWindow: const InfoWindow(title: 'Junkshop'),
      ),
    };
  }

  @override
  void dispose() {
    _requestSub?.cancel();
    _mapController?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Widget _buildCenterPulse() {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) {
          final t = _pulseController.value;

          final outerSize = 120 + (70 * t);
          final midSize = 80 + (45 * t);

          final outerOpacity = (1 - t) * 0.20;
          final midOpacity = (1 - t) * 0.28;

          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: outerSize,
                height: outerSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withOpacity(outerOpacity),
                ),
              ),
              Container(
                width: midSize,
                height: midSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withOpacity(midOpacity),
                ),
              ),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent,
                  border: Border.all(
                    color: Colors.white,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.45),
                      blurRadius: 16,
                      spreadRadius: 3,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasNavigated,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _closeWaitingPage();
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: widget.pickupLatLng,
                zoom: 16,
              ),
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              compassEnabled: false,
              markers: _buildMarkers(),
              polylines: const {},
              mapToolbarEnabled: false,
              buildingsEnabled: false,
              indoorViewEnabled: false,
              trafficEnabled: false,
              tiltGesturesEnabled: false,
              rotateGesturesEnabled: true,
            ),

            Container(
              color: Colors.black.withOpacity(0.10),
            ),

            Center(
              child: _buildCenterPulse(),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: _sheet,
                    borderRadius: BorderRadius.circular(100),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(100),
                      onTap: _closeWaitingPage,
                      child: const SizedBox(
                        width: 46,
                        height: 46,
                        child: Icon(
                          Icons.arrow_back,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            Align(
              alignment: Alignment.bottomCenter,
              child: DraggableScrollableSheet(
                initialChildSize: 0.25,
                minChildSize: 0.18,
                maxChildSize: 0.6,
                builder: (context, scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: _sheet,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(26),
                      ),
                    ),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: _border,
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          const Row(
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(_accent),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "Waiting for collector",
                                  style: TextStyle(
                                    color: _textPrimary,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 8),

                          const Text(
                            "Stay available while a collector reviews and accepts your pickup request.",
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),

                          const SizedBox(height: 14),

                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _border),
                            ),
                            child: const Text(
                              "Your pickup location is centered on the map. This page will automatically go to your Order tab once the collector accepts.",
                              style: TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w700,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
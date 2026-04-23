import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'collector_transaction_page.dart';
import '../chat/screens/chat_page.dart';
import '../chat/services/chat_services.dart';

extension OpacityFix on Color {
  Color o(double opacity) => withValues(alpha: opacity.clamp(0.0, 1.0));
}

class PickupStop {
  final String requestId;
  final String householdId;
  final String collectorId;
  final String householdName;
  final String pickupAddress;
  final GeoPoint pickupLocation;
  final String status;
  final String bagLabel;
  final int? bagKg;
  final String phoneNumber;
  final bool hasCollectorReceipt;
  final Timestamp? acceptedAt;

  PickupStop({
    required this.requestId,
    required this.householdId,
    required this.collectorId,
    required this.householdName,
    required this.pickupAddress,
    required this.pickupLocation,
    required this.status,
    required this.bagLabel,
    required this.bagKg,
    required this.phoneNumber,
    required this.hasCollectorReceipt,
    required this.acceptedAt,
  });

  LatLng get latLng => LatLng(pickupLocation.latitude, pickupLocation.longitude);

  PickupStop copyWith({
    String? requestId,
    String? householdId,
    String? collectorId,
    String? householdName,
    String? pickupAddress,
    GeoPoint? pickupLocation,
    String? status,
    String? bagLabel,
    int? bagKg,
    String? phoneNumber,
    bool? hasCollectorReceipt,
    Timestamp? acceptedAt,
  }) {
    return PickupStop(
      requestId: requestId ?? this.requestId,
      householdId: householdId ?? this.householdId,
      collectorId: collectorId ?? this.collectorId,
      householdName: householdName ?? this.householdName,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      status: status ?? this.status,
      bagLabel: bagLabel ?? this.bagLabel,
      bagKg: bagKg ?? this.bagKg,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      hasCollectorReceipt: hasCollectorReceipt ?? this.hasCollectorReceipt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
    );
  }

  static PickupStop? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;

    final gp = data['pickupLocation'];
    if (gp is! GeoPoint) return null;

    final rawBagKg = data['bagKg'] ?? data['bagEstimatedKg'];
    int? parsedBagKg;
    if (rawBagKg is int) {
      parsedBagKg = rawBagKg;
    } else if (rawBagKg is num) {
      parsedBagKg = rawBagKg.toInt();
    } else {
      parsedBagKg = int.tryParse((rawBagKg ?? '').toString());
    }

    return PickupStop(
      requestId: doc.id,
      householdId: (data['householdId'] ?? '').toString(),
      collectorId: (data['collectorId'] ?? '').toString(),
      householdName: (data['householdName'] ?? 'Household').toString(),
      pickupAddress:
          (data['fullAddress'] ?? data['pickupAddress'] ?? '').toString(),
      pickupLocation: gp,
      status: (data['status'] ?? '').toString(),
      bagLabel: (data['bagLabel'] ?? '').toString(),
      bagKg: parsedBagKg,
      phoneNumber: (data['phoneNumber'] ?? '').toString(),
      hasCollectorReceipt: data['hasCollectorReceipt'] == true,
      acceptedAt: data['acceptedAt'] is Timestamp
          ? data['acceptedAt'] as Timestamp
          : null,
    );
  }
}

class RouteSegment {
  final List<LatLng> points;
  final String distanceText;
  final String durationText;
  final int durationSec;

  RouteSegment({
    required this.points,
    required this.distanceText,
    required this.durationText,
    required this.durationSec,
  });
}

class CollectorPickupMapPage extends StatefulWidget {
  final List<String> requestIds;

  const CollectorPickupMapPage({
    super.key,
    required this.requestIds,
  });

  @override
  State<CollectorPickupMapPage> createState() => _CollectorPickupMapPageState();
}

class _CollectorPickupMapPageState extends State<CollectorPickupMapPage> {
  static const Color _bg = Color(0xFF0F172A);
  static const Color _card = Color(0xFF111928);
  static const Color _accent = Color(0xFF1FA9A7);
  static const String _junkshopUid = "07Wi7N8fALh2yqNdt1CQgIYVGE43";
  static const String _junkshopName = "Mores Scrap";

  static const String _darkMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{ "color": "#0b1220" }]
  },
  {
    "elementType": "labels.icon",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#8b9bb4" }]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{ "color": "#0b1220" }]
  },
  {
    "featureType": "administrative",
    "elementType": "geometry",
    "stylers": [{ "color": "#1e293b" }]
  },
  {
    "featureType": "administrative.country",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#cbd5e1" }]
  },
  {
    "featureType": "administrative.land_parcel",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#cbd5e1" }]
  },
  {
    "featureType": "poi",
    "elementType": "geometry",
    "stylers": [{ "color": "#111827" }]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#94a3b8" }]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [{ "color": "#0f1f1d" }]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#6ee7b7" }]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{ "color": "#1f2937" }]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [{ "color": "#0f172a" }]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#cbd5e1" }]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{ "color": "#243244" }]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [{ "color": "#111827" }]
  },
  {
    "featureType": "road.highway",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#f8fafc" }]
  },
  {
    "featureType": "transit",
    "elementType": "geometry",
    "stylers": [{ "color": "#111827" }]
  },
  {
    "featureType": "transit.station",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#cbd5e1" }]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{ "color": "#07111f" }]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [{ "color": "#7dd3fc" }]
  }
]
''';
 
  static const List<Map<String, String>> _reportReasons = [
    {"code": "harassment", "label": "Harassment"},
    {"code": "rude_behavior", "label": "Rude behavior"},
    {"code": "wrong_details", "label": "Wrong pickup details"},
    {"code": "resident_unavailable", "label": "Resident unavailable"},
    {"code": "false_complaint", "label": "False complaint"},
    {"code": "other", "label": "Other"},
  ];

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final ChatService _chat = ChatService();
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  GoogleMapController? _map;
  Position? _pos;

  BitmapDescriptor? _collectorMarkerIcon;
  BitmapDescriptor? _householdMarkerIcon;
  BitmapDescriptor? _moresMarkerIcon;

  bool _topExpanded = false;
  bool _loadingStops = true;
  bool _loadingRoute = false;
  bool _junkshopChatEnsured = false;
  bool _isSendingLiveLocation = false;

  List<PickupStop> _stops = [];
  int _currentStopIndex = 0;

  List<LatLng> _route = [];
  String _distanceText = "";
  String _durationText = "";

  StreamSubscription<Position>? _liveLocationSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _requestsSub;

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  CollectionReference<Map<String, dynamic>> get _requestsRef =>
      _db.collection('requests');

  DocumentReference<Map<String, dynamic>> _requestRef(String requestId) =>
      _requestsRef.doc(requestId);

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('Users').doc(uid);

  @override
  void initState() {
    super.initState();
    _setupPage();
  }

  Future<void> _setupPage() async {
    await _loadMarkerIcons();
    await _initPage();
  }

  PickupStop? get _currentStop {
    if (_stops.isEmpty) return null;
    if (_currentStopIndex < 0 || _currentStopIndex >= _stops.length) {
      return null;
    }
    return _stops[_currentStopIndex];
  }

  LatLng? get _originLatLng {
    if (_pos == null) return null;
    return LatLng(_pos!.latitude, _pos!.longitude);
  }

  Future<BitmapDescriptor> _iconToMarker({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required Color borderColor,
    double size = 112,
    double iconSize = 54,
  }) async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    final painter = _MarkerPainter(
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
    final bytes = await image.toByteData(format: ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Future<void> _loadMarkerIcons() async {
    try {
      _collectorMarkerIcon = await _iconToMarker(
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

      _moresMarkerIcon = await _iconToMarker(
        icon: Icons.storefront_rounded,
        iconColor: Colors.white,
        backgroundColor: const Color(0xFF16A34A),
        borderColor: Colors.transparent,
        size: 220,
        iconSize: 48,
      );

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint("❌ Failed to build marker icons: $e");
    }
  }

  Future<void> _markChatRead(String chatId) async {
    final me = _currentUser?.uid ?? "";
    if (me.isEmpty) return;

    try {
      await _db.collection('chats').doc(chatId).set({
        'lastReadBy': {me: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("❌ Failed to mark chat read: $e");
    }
  }

  Future<void> _startLiveLocationSharing() async {
    if (_stops.isEmpty) return;
    if (_isSendingLiveLocation) return;

    final activeStops = _stops.where((stop) {
      final status = stop.status.toLowerCase().trim();
      return status == 'accepted' ||
          status == 'arrived' ||
          status == 'ongoing';
    }).toList();

    if (activeStops.isEmpty) return;

    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) return;

    _isSendingLiveLocation = true;

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    if (mounted) {
      setState(() {
        _pos = position;
      });
    }

    await _updateCollectorUserLiveLocation(position);

    final batch = _db.batch();
    for (final stop in activeStops) {
      batch.set(
        _requestRef(stop.requestId),
        {
          'collectorLiveLocation': GeoPoint(
            position.latitude,
            position.longitude,
          ),
          'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
          'sharingLiveLocation': true,
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();

    await _liveLocationSub?.cancel();
    _liveLocationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((position) async {
      try {
        if (mounted) {
          setState(() {
            _pos = position;
          });
        }

        await _updateCollectorUserLiveLocation(position);

        final currentActiveStops = _stops.where((stop) {
          final status = stop.status.toLowerCase().trim();
          return status == 'accepted' ||
              status == 'arrived' ||
              status == 'ongoing';
        }).toList();

        if (currentActiveStops.isEmpty) return;

        final batch = _db.batch();
        for (final stop in currentActiveStops) {
          batch.set(
            _requestRef(stop.requestId),
            {
              'collectorLiveLocation': GeoPoint(
                position.latitude,
                position.longitude,
              ),
              'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
              'sharingLiveLocation': true,
            },
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      } catch (e) {
        debugPrint('LIVE LOCATION UPDATE ERROR: $e');
      }
    });
  }

  Future<void> _stopLiveLocationSharing({bool clearFirestore = false}) async {
    await _liveLocationSub?.cancel();
    _liveLocationSub = null;
    _isSendingLiveLocation = false;

    try {
      await _clearCollectorUserLiveLocation();
    } catch (e) {
      debugPrint('❌ clear collector user live location failed: $e');
    }

    if (!clearFirestore) return;

    try {
      final activeStops = _stops.where((stop) {
        final status = stop.status.toLowerCase().trim();
        return status == 'accepted' ||
            status == 'arrived' ||
            status == 'ongoing';
      }).toList();

      if (activeStops.isEmpty) return;

      final batch = _db.batch();
      for (final stop in activeStops) {
        batch.set(
          _requestRef(stop.requestId),
          {
            'sharingLiveLocation': false,
            'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    } catch (e) {
      debugPrint('❌ failed to stop live location in requests: $e');
    }
  }

  Future<void> _reportCurrentResident() async {
    final stop = _currentStop;
    final user = _currentUser;

    if (stop == null || user == null) return;

    final result = await _showReportDialog();
    if (result == null) return;

    final String reasonCode = (result["reasonCode"] ?? "").toString().trim();
    final String reasonText = (result["reasonText"] ?? "").toString().trim();
    final XFile? pickedImage = result["image"] as XFile?;

    if (reasonCode.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a reason.")),
      );
      return;
    }

    try {
      final existing = await _db
          .collection('reports')
          .where('requestId', isEqualTo: stop.requestId)
          .where('reporterId', isEqualTo: user.uid)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You already submitted a report for this pickup."),
          ),
        );
        return;
      }

      final reportRef = _db.collection('reports').doc();

      await reportRef.set({
        "reporterId": user.uid,
        "reporterRole": "collector",
        "reportedUserId": stop.householdId,
        "reportedRole": "resident",
        "requestId": stop.requestId,
        "reasonCode": reasonCode,
        "reasonText": reasonText,
        "evidenceImageUrls": <String>[],
        "status": "pending",
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });

      if (pickedImage != null) {
        final file = File(pickedImage.path);

        final storageRef = FirebaseStorage.instance
            .ref()
            .child(
              'report_images/${reportRef.id}/${DateTime.now().millisecondsSinceEpoch}.jpg',
            );

        final metadata = SettableMetadata(
          contentType: 'image/jpeg',
        );

        await storageRef.putFile(file, metadata);
        final downloadUrl = await storageRef.getDownloadURL();

        await reportRef.update({
          "evidenceImageUrls": [downloadUrl],
          "updatedAt": FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Report submitted.")),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to submit report: ${e.message ?? e.code}"),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to submit report: $e")),
      );
    }
  }

  Future<Map<String, dynamic>?> _showReportDialog() async {
    String selectedCode = "harassment";
    final detailsController = TextEditingController();
    XFile? selectedImage;

    final reasons = [
      {"code": "harassment", "label": "Harassment"},
      {"code": "wrong_details", "label": "Wrong details"},
      {"code": "no_show", "label": "No show"},
      {"code": "rude_behavior", "label": "Rude behavior"},
      {"code": "other", "label": "Other"},
    ];

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              title: const Text(
                "Report Resident",
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedCode,
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: reasons
                          .map(
                            (r) => DropdownMenuItem<String>(
                              value: r["code"],
                              child: Text(r["label"]!),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => selectedCode = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: detailsController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: "Add details (optional)",
                        hintStyle: TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final image = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 75,
                        );
                        if (image != null) {
                          setState(() => selectedImage = image);
                        }
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        selectedImage == null
                            ? "Upload Image (Optional)"
                            : "Image Selected",
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context, {
                      "reasonCode": selectedCode,
                      "reasonText": detailsController.text.trim(),
                      "image": selectedImage,
                    });
                  },
                  child: const Text(
                    "Submit",
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _initPage() async {
    await _initLocation();
    await _listenToStops();
  }

  Future<void> _updateCollectorUserLiveLocation(Position position) async {
    final user = _currentUser;
    if (user == null) return;

    await _userRef(user.uid).set({
      'collectorLiveLocation': GeoPoint(position.latitude, position.longitude),
      'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
      'isOnline': true,
    }, SetOptions(merge: true));
  }

  Future<void> _clearCollectorUserLiveLocation() async {
    final user = _currentUser;
    if (user == null) return;

    await _userRef(user.uid).set({
      'collectorLiveUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _initLocation() async {
    final ok = await _ensureLocationPermission();
    if (!ok) return;

    try {
      final p = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      if (!mounted) return;
      setState(() => _pos = p);
    } catch (e) {
      debugPrint("❌ _initLocation error: $e");
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();

    if (!enabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please turn on location services.")),
        );
      }
      return false;
    }

    var perm = await Geolocator.checkPermission();

    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.denied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied.")),
        );
      }
      return false;
    }

    if (perm == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Location permission permanently denied. Open app settings.",
            ),
          ),
        );
      }
      await Geolocator.openAppSettings();
      return false;
    }

    return true;
  }

  Future<void> _listenToStops() async {
    await _requestsSub?.cancel();

    final uid = _currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      setState(() {
        _loadingStops = false;
        _stops = [];
      });
      return;
    }

    _requestsSub = _requestsRef
        .where('collectorId', isEqualTo: uid)
        .where('type', isEqualTo: 'pickup')
        .where('active', isEqualTo: true)
        .snapshots()
        .listen((snapshot) async {
      try {
        final loadedStops = <PickupStop>[];

        for (final doc in snapshot.docs) {
          final stop = PickupStop.fromDoc(doc);
          if (stop == null) continue;

          final status =
              (doc.data()['status'] ?? '').toString().toLowerCase().trim();

          if (status == 'completed' ||
              status == 'rejected' ||
              status == 'cancelled' ||
              status == 'declined') {
            continue;
          }

          loadedStops.add(stop);
        }

        if (_originLatLng != null && loadedStops.isNotEmpty) {
          loadedStops.sort((a, b) {
            final aAccepted = a.acceptedAt?.toDate();
            final bAccepted = b.acceptedAt?.toDate();
            if (aAccepted == null && bAccepted == null) return 0;
            if (aAccepted == null) return 1;
            if (bAccepted == null) return -1;
            return aAccepted.compareTo(bAccepted);
          });

          final ordered = _orderStopsNearest(
            start: _originLatLng!,
            stops: loadedStops,
          );

          if (!mounted) return;
          setState(() {
            _stops = ordered;
            _currentStopIndex = _stops.isEmpty
                ? 0
                : (_currentStopIndex >= _stops.length
                    ? _stops.length - 1
                    : _currentStopIndex);
            _loadingStops = false;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _stops = loadedStops;
            _currentStopIndex = _stops.isEmpty
                ? 0
                : (_currentStopIndex >= _stops.length
                    ? _stops.length - 1
                    : _currentStopIndex);
            _loadingStops = false;
          });
        }

        if (_stops.isEmpty) {
          await _stopLiveLocationSharing(clearFirestore: true);
          if (!mounted) return;
          setState(() {
            _route = [];
            _distanceText = "";
            _durationText = "";
          });
          return;
        }

        await _ensureJunkshopChatIfNeeded();
        await _buildMultiStopRoute();
        await _focusCameraOnCurrentStop();
        await _startLiveLocationSharing();
      } catch (e) {
        debugPrint("❌ _listenToStops error: $e");
        if (!mounted) return;
        setState(() {
          _loadingStops = false;
        });
      }
    }, onError: (e) {
      debugPrint("❌ requests listener error: $e");
      if (!mounted) return;
      setState(() {
        _loadingStops = false;
      });
    });
  }

  double _distanceSquared(LatLng a, LatLng b) {
    final dx = a.latitude - b.latitude;
    final dy = a.longitude - b.longitude;
    return dx * dx + dy * dy;
  }

  List<PickupStop> _orderStopsNearest({
    required LatLng start,
    required List<PickupStop> stops,
  }) {
    final remaining = List<PickupStop>.from(stops);
    final ordered = <PickupStop>[];
    var current = start;

    while (remaining.isNotEmpty) {
      remaining.sort((a, b) {
        final da = _distanceSquared(current, a.latLng);
        final db = _distanceSquared(current, b.latLng);
        return da.compareTo(db);
      });

      final next = remaining.removeAt(0);
      ordered.add(next);
      current = next.latLng;
    }

    return ordered;
  }

  Future<void> _ensureJunkshopChatIfNeeded() async {
    if (_junkshopChatEnsured) return;
    final stop = _currentStop;
    if (stop == null) return;

    final s = stop.status.toLowerCase();
    if (!(s == "accepted" || s == "arrived" || s == "scheduled")) return;

    final me = _currentUser?.uid ?? "";
    final collectorUid =
        stop.collectorId.trim().isNotEmpty ? stop.collectorId.trim() : me;
    if (collectorUid.isEmpty) return;

    try {
      _junkshopChatEnsured = true;
      await _chat.ensureJunkshopChatForRequest(
        requestId: stop.requestId,
        junkshopUid: _junkshopUid,
        collectorUid: collectorUid,
      );
    } catch (e) {
      debugPrint("❌ ensureJunkshopChatForRequest failed: $e");
    }
  }

  Future<RouteSegment?> _getRouteSegment(
    LatLng origin,
    LatLng destination,
  ) async {
    try {
      final callable = _functions.httpsCallable('getDirections');
      final result = await callable.call({
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'mode': 'driving',
      });

      final data = result.data;
      if (data is! Map) return null;

      final points = data['points'] as String?;
      if (points == null || points.isEmpty) return null;

      final dist = (data['distanceText'] ?? '').toString();
      final dur = (data['durationText'] ?? '').toString();
      final durVal = data['durationValueSec'];

      final decoded = _decodePolyline(points);

      return RouteSegment(
        points: decoded,
        distanceText: dist,
        durationText: dur,
        durationSec: durVal is int ? durVal : 0,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint("❌ getDirections failed: ${e.code} ${e.message}");
      return null;
    } catch (e) {
      debugPrint("❌ getDirections crashed: $e");
      return null;
    }
  }

  Future<void> _callCurrentStop() async {
    final stop = _currentStop;
    if (stop == null || stop.phoneNumber.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No mobile number available.")),
      );
      return;
    }

    final uri = Uri(scheme: 'tel', path: stop.phoneNumber.trim());

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open dialer.")),
      );
    }
  }

  Future<void> _buildMultiStopRoute() async {
    if (_originLatLng == null || _stops.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _loadingRoute = true;
    });

    final routePoints = <LatLng>[];
    int totalDurationSec = 0;
    final distanceParts = <String>[];

    LatLng current = _originLatLng!;

    for (int i = _currentStopIndex; i < _stops.length; i++) {
      final stop = _stops[i];
      final segment = await _getRouteSegment(current, stop.latLng);
      if (segment == null) {
        current = stop.latLng;
        continue;
      }

      if (routePoints.isEmpty) {
        routePoints.addAll(segment.points);
      } else if (segment.points.isNotEmpty) {
        routePoints.addAll(segment.points.skip(1));
      }

      totalDurationSec += segment.durationSec;
      if (segment.distanceText.isNotEmpty) {
        distanceParts.add(segment.distanceText);
      }

      current = stop.latLng;
    }

    if (!mounted) return;
    setState(() {
      _route = routePoints;
      _distanceText =
          distanceParts.isNotEmpty ? distanceParts.join(" + ") : "";
      _durationText =
          totalDurationSec > 0 ? _formatDuration(totalDurationSec) : "";
      _loadingRoute = false;
    });
  }

  String _formatDuration(int totalSeconds) {
    final totalMinutes = (totalSeconds / 60).round();
    if (totalMinutes < 60) return "$totalMinutes min";

    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (mins == 0) return "$hours hr";
    return "$hours hr $mins min";
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

  Future<void> _focusCameraOnCurrentStop() async {
    final stop = _currentStop;
    if (stop == null || _map == null) return;

    await _map!.animateCamera(
      CameraUpdate.newLatLngZoom(stop.latLng, 15),
    );
  }

  Future<void> _openJunkshopChat() async {
    try {
      final collectorUid = _currentUser?.uid;
      if (collectorUid == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to open chat.')),
        );
        return;
      }

      final stop = _currentStop;
      if (stop == null || stop.requestId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active stop found for chat.')),
        );
        return;
      }

      await _chat.ensureJunkshopChatForRequest(
        requestId: stop.requestId,
        junkshopUid: _junkshopUid,
        collectorUid: collectorUid,
      );

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            chatId: 'junkshop_pickup_${stop.requestId}',
            title: _junkshopName,
            otherUserId: _junkshopUid,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open junkshop chat: $e')),
      );
    }
  }

  Future<void> _openStopChat(PickupStop stop) async {
    final s = stop.status.toLowerCase();
    final canChat = s == "accepted" || s == "arrived" || s == "scheduled";

    if (!canChat) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Chat is available once pickup is accepted."),
        ),
      );
      return;
    }

    final me = _currentUser?.uid ?? "";
    final householdUid = stop.householdId.trim();
    var collectorUid = stop.collectorId.trim();

    if (me.isEmpty || householdUid.isEmpty) return;

    if (collectorUid.isEmpty) {
      collectorUid = me;
    }

    final chatId = await _chat.ensurePickupChat(
      requestId: stop.requestId,
      householdUid: householdUid,
      collectorUid: collectorUid,
    );

    await _markChatRead(chatId);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          chatId: chatId,
          title: stop.householdName.isEmpty ? "Household" : stop.householdName,
          otherUserId: householdUid,
        ),
      ),
    );
  }

  Future<void> _openCollectorReceipt() async {
    final stop = _currentStop;
    if (stop == null) return;

    final s = stop.status.toLowerCase();
    if (s != "arrived") {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Create receipt is available once you are ARRIVED.",
          ),
        ),
      );
      return;
    }

    try {
      final reqDoc = await _requestRef(stop.requestId).get();
      final data = reqDoc.data() ?? {};
      final hasReceipt = data['hasCollectorReceipt'] == true;

      if (hasReceipt) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Order already created for this pickup."),
          ),
        );
        return;
      }
    } catch (_) {}

    if (!mounted) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CollectorTransactionPage(
          requestId: stop.requestId,
          embedded: false,
        ),
      ),
    );

    if (saved == true) {
      await _stopLiveLocationSharing(clearFirestore: true);
      await _removeCompletedStopAndMoveNext(stop.requestId);
    }
  }

  Future<void> _removeCompletedStopAndMoveNext(String requestId) async {
    final removedIndex = _stops.indexWhere((x) => x.requestId == requestId);
    if (removedIndex == -1) return;

    if (!mounted) return;

    setState(() {
      _stops.removeAt(removedIndex);

      if (_stops.isEmpty) {
        _currentStopIndex = 0;
        _route = [];
        _distanceText = "";
        _durationText = "";
        return;
      }

      if (_currentStopIndex >= _stops.length) {
        _currentStopIndex = _stops.length - 1;
      } else if (removedIndex < _currentStopIndex) {
        _currentStopIndex -= 1;
      }
    });

    _junkshopChatEnsured = false;

    if (_stops.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("All pickup stops completed.")),
      );
      return;
    }

    await _ensureJunkshopChatIfNeeded();
    await _buildMultiStopRoute();
    await _focusCameraOnCurrentStop();
    await _startLiveLocationSharing();

    final nextStop = _currentStop;
    if (!mounted || nextStop == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Completed and removed. Next stop: ${nextStop.householdName}",
        ),
      ),
    );
  }

  Future<void> _markArrivedOrComplete() async {
    final stop = _currentStop;
    if (stop == null) return;

    final s = stop.status.toLowerCase();

    if (s == 'arrived') {
      await _openCollectorReceipt();
      return;
    }

    try {
      await _requestRef(stop.requestId).update({
        'status': 'arrived',
        'arrived': true,
        'arrivedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final idx = _stops.indexWhere((x) => x.requestId == stop.requestId);
      if (idx != -1 && mounted) {
        setState(() {
          _stops[idx] = _stops[idx].copyWith(status: 'arrived');
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Marked as arrived.")),
      );

      await _openCollectorReceipt();
    } on FirebaseException catch (e) {
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

  Future<void> _goToStop(int index) async {
    if (index < 0 || index >= _stops.length) return;

    await _stopLiveLocationSharing(clearFirestore: true);
    _junkshopChatEnsured = false;

    setState(() {
      _currentStopIndex = index;
    });

    await _ensureJunkshopChatIfNeeded();
    await _buildMultiStopRoute();
    await _focusCameraOnCurrentStop();
    await _startLiveLocationSharing();
  }

  Set<Marker> _buildMarkers() {
    return <Marker>{
      if (_stops.isNotEmpty)
        Marker(
          markerId: MarkerId("mores_scrap_${_moresMarkerIcon?.hashCode ?? 0}"),
          position: const LatLng(14.5995, 120.9842),
          anchor: const Offset(0.20, 0.52),
          infoWindow: const InfoWindow(title: "Mores Scrap"),
          icon: _moresMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
          zIndex: 10,
        ),
      if (_pos != null)
        Marker(
          markerId: const MarkerId("me"),
          position: LatLng(_pos!.latitude, _pos!.longitude),
          anchor: const Offset(0.5, 0.52),
          infoWindow: const InfoWindow(title: "You / Collector"),
          icon: _collectorMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure,
              ),
          zIndex: 3,
        ),
      ..._stops.asMap().entries.map((entry) {
        final index = entry.key;
        final stop = entry.value;
        final isCurrent = index == _currentStopIndex;

        return Marker(
          markerId: MarkerId(stop.requestId),
          position: stop.latLng,
          anchor: const Offset(0.5, 0.52),
          infoWindow: InfoWindow(
            title: "Stop ${index + 1}: ${stop.householdName}",
            snippet: stop.pickupAddress,
          ),
          icon: _householdMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRose,
              ),
          zIndex: isCurrent ? 2 : 1,
        );
      }),
    };
  }

  Set<Polyline> _buildPolylines() {
    if (_route.isEmpty) return <Polyline>{};

    return {
      Polyline(
        polylineId: const PolylineId("route"),
        points: _route,
        width: 6,
        color: _accent,
      ),
    };
  }

  Widget _buildEmptyLiveState() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          children: [
            Row(
              children: [
                _circularButton(
                  Icons.arrow_back,
                  onTap: () {
                    if (Navigator.of(context).canPop()) Navigator.pop(context);
                  },
                ),
              ],
            ),
            const Spacer(),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.52),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.18),
                        blurRadius: 18, 
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(0.14),
                          shape: BoxShape.circle,
                          border: Border.all(color: _accent.withOpacity(0.35)),
                        ),
                        child: const Icon(
                          Icons.local_shipping_outlined,
                          color: _accent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        "No active pickups",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "New pickup requests will appear here automatically.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.68),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.sync,
                              size: 15,
                              color: Colors.white.withOpacity(0.82),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              "Waiting for assignments",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant CollectorPickupMapPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldIds = oldWidget.requestIds.toSet();
    final newIds = widget.requestIds.toSet();

    if (oldIds.length != newIds.length || !oldIds.containsAll(newIds)) {
      _loadingStops = true;
      _listenToStops();
    }
  }

  @override
  void dispose() {
    _requestsSub?.cancel();
    _liveLocationSub?.cancel();
    _map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentStop = _currentStop;
    final markers = _buildMarkers();
    final polylines = _buildPolylines();

    if (!_loadingStops && _stops.isEmpty) {
      return Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            Positioned.fill(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _pos != null
                      ? LatLng(_pos!.latitude, _pos!.longitude)
                      : const LatLng(14.5995, 120.9842),
                  zoom: 13,
                ),
                onMapCreated: (c) async {
                  _map = c;
                  await _map?.setMapStyle(_darkMapStyle);
                },
                myLocationEnabled: false,
                markers: markers,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                myLocationButtonEnabled: false,
              ),
            ),
            _buildEmptyLiveState(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: currentStop?.latLng ?? const LatLng(14.5995, 120.9842),
                zoom: 15,
              ),
              onMapCreated: (c) async {
                _map = c;
                await _map?.setMapStyle(_darkMapStyle);
              },
              myLocationEnabled: false,
              markers: markers,
              polylines: polylines,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
            ),
          ),
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
                          if (Navigator.of(context).canPop()) {
                            Navigator.pop(context);
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _topExpanded = !_topExpanded),
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: _topExpanded ? 190 : 56,
                              ),
                              child: _glass(
                                radius: 16,
                                blur: 12,
                                opacity: 0.55,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.local_shipping,
                                          size: 18,
                                          color: _accent,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            currentStop == null
                                                ? "Pickup Route"
                                                : "Stop ${_currentStopIndex + 1}/${_stops.length} • ${currentStop.householdName}",
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
                                          _topExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          color: Colors.white.withOpacity(0.85),
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                    if (_topExpanded && currentStop != null) ...[
                                      const SizedBox(height: 8),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          physics:
                                              const BouncingScrollPhysics(),
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              _pillChip(
                                                icon:
                                                    Icons.inventory_2_outlined,
                                                text: currentStop.bagLabel.isEmpty
                                                    ? "Bag: —"
                                                    : "Bag: ${currentStop.bagLabel}${currentStop.bagKg == null ? "" : " (${currentStop.bagKg}kg)"}",
                                              ),
                                              _pillChip(
                                                icon: Icons.info_outline,
                                                text: currentStop
                                                        .status.isEmpty
                                                    ? "Status: —"
                                                    : "Status: ${currentStop.status.toUpperCase()}",
                                              ),
                                              _pillChip(
                                                icon: Icons.place_outlined,
                                                text: currentStop
                                                        .pickupAddress.isEmpty
                                                    ? "Address: —"
                                                    : currentStop.pickupAddress,
                                              ),
                                              if (currentStop
                                                  .phoneNumber.isNotEmpty)
                                                _pillChip(
                                                  icon: Icons.phone_outlined,
                                                  text:
                                                      "Mobile: ${currentStop.phoneNumber}",
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
          DraggableScrollableSheet(
            initialChildSize: 0.30,
            minChildSize: 0.18,
            maxChildSize: 0.78,
            builder: (context, scrollController) {
              return ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(22)),
                      border: Border.all(color: Colors.transparent),
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
                        if (_loadingStops)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _miniStat(
                                  Icons.access_time,
                                  _loadingRoute
                                      ? "Loading..."
                                      : (_durationText.isEmpty
                                          ? "—"
                                          : _durationText),
                                ),
                                _miniStat(
                                  Icons.navigation_outlined,
                                  _loadingRoute
                                      ? "..."
                                      : (_distanceText.isEmpty
                                          ? "—"
                                          : _distanceText),
                                ),
                                _miniStat(
                                  Icons.route,
                                  "${_stops.length} stop${_stops.length == 1 ? '' : 's'}",
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Stops (${_stops.length})",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                for (int i = 0; i < _stops.length; i++) ...[
                                  _stopTile(i, _stops[i]),
                                  if (i != _stops.length - 1)
                                    const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _actionWide(
                                  icon: Icons.chat_bubble_outline,
                                  title: "CHAT",
                                  subtitle: "Message junkshop",
                                  bg: Colors.white.withOpacity(0.10),
                                  fg: Colors.white,
                                  border: Colors.white.withOpacity(0.14),
                                  onTap: _openJunkshopChat,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _actionWide(
                                  icon: currentStop?.status.toLowerCase() ==
                                          'arrived'
                                      ? Icons.receipt_long
                                      : Icons.location_on_outlined,
                                  title: currentStop?.status.toLowerCase() ==
                                          'arrived'
                                      ? "Save & Complete"
                                      : "ARRIVED",
                                  subtitle: currentStop?.status.toLowerCase() ==
                                          'arrived'
                                      ? "COMPLETE & SAVE"
                                      : "Mark current stop",
                                  bg: _accent,
                                  fg: _bg,
                                  onTap: _markArrivedOrComplete,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (currentStop?.phoneNumber.trim().isNotEmpty == true)
                            _actionWide(
                              icon: Icons.call_outlined,
                              title: "CALL",
                              subtitle: "Contact",
                              bg: _card,
                              fg: Colors.white,
                              border: Colors.white.withOpacity(0.08),
                              onTap: _callCurrentStop,
                            ),
                          const SizedBox(height: 10),
                          _actionWide(
                            icon: Icons.report_gmailerrorred_outlined,
                            title: "REPORT",
                            subtitle: "Report resident",
                            bg: Colors.redAccent.withOpacity(0.12),
                            fg: Colors.white,
                            border: Colors.redAccent.withOpacity(0.35),
                            onTap: _reportCurrentResident,
                          ),
                        ],
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

  Widget _stopTile(int index, PickupStop stop) {
    final isCurrent = index == _currentStopIndex;

    return InkWell(
      onTap: () => _goToStop(index),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isCurrent
              ? _accent.withOpacity(0.14)
              : const Color(0xFF0F1A2E).withOpacity(0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent
                ? _accent.withOpacity(0.70)
                : Colors.white.withOpacity(0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.16),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isCurrent ? _accent : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                "${index + 1}",
                style: TextStyle(
                  color: isCurrent ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.householdName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stop.pickupAddress.isEmpty
                        ? "No address available"
                        : stop.pickupAddress,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.68),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _tinyBadge(Icons.home_outlined, "Household"),
                      _tinyBadge(Icons.info_outline, stop.status.toUpperCase()),
                      if (stop.phoneNumber.isNotEmpty)
                        _tinyBadge(Icons.call_outlined, stop.phoneNumber),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildStopChatButton(stop),
          ],
        ),
      ),
    );
  }

  Widget _buildStopChatButton(PickupStop stop) {
    final me = _currentUser?.uid ?? "";
    final chatId = "pickup_${stop.requestId}";

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('chats').doc(chatId).snapshots(),
      builder: (context, snap) {
        bool hasUnread = false;

        final chat = snap.data?.data();
        if (chat != null && me.isNotEmpty) {
          final lastMessageAt = chat['lastMessageAt'];
          final lastMessageSenderId =
              (chat['lastMessageSenderId'] ?? '').toString();

          final lastReadBy = chat['lastReadBy'];
          Timestamp? myLastRead;

          if (lastReadBy is Map && lastReadBy[me] is Timestamp) {
            myLastRead = lastReadBy[me] as Timestamp;
          }

          if (lastMessageAt is Timestamp && lastMessageSenderId != me) {
            hasUnread = myLastRead == null ||
                lastMessageAt.toDate().isAfter(myLastRead.toDate());
          }
        }

        return InkWell(
          onTap: () => _openStopChat(stop),
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              if (hasUnread)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _glass({
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    double radius = 18,
    double blur = 12,
    double opacity = 0.45,
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
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _circularButton(
    IconData icon, {
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.46),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _pillChip({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withOpacity(0.88)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tinyBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white.withOpacity(0.8)),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white.withOpacity(0.78)),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _actionWide({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color bg,
    required Color fg,
    Color? border,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border ?? Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: fg.withOpacity(0.82),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkerPainter {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final double size;
  final double iconSize;

  _MarkerPainter({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.size,
    required this.iconSize,
  });

  void paint(Canvas canvas, Size s) {
    final center = Offset(s.width / 2, s.height / 2);
    final radius = s.width / 2.9;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.24)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center.translate(0, 4), radius, shadowPaint);

    final fillPaint = Paint()..color = backgroundColor;
    canvas.drawCircle(center, radius, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, borderPaint);

    final iconPainter = TextPainter(textDirection: TextDirection.ltr);
    iconPainter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: iconSize,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: iconColor,
      ),
    );
    iconPainter.layout();

    final iconOffset = Offset(
      center.dx - iconPainter.width / 2,
      center.dy - iconPainter.height / 2,
    );
    iconPainter.paint(canvas, iconOffset);
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'waiting_collector_page.dart';
import 'household/household_dashboard.dart';

class PickupRequestPage extends StatefulWidget {
  final LatLng pickupLatLng;
  final String pickupSource;
  final double distanceKm;
  final int etaMinutes;
  final String moresName;
  final LatLng moresLatLng;
  final List<Map<String, String>> availableCollectors;

  const PickupRequestPage({
    super.key,
    required this.pickupLatLng,
    required this.pickupSource,
    required this.distanceKm,
    required this.etaMinutes,
    required this.moresName,
    required this.moresLatLng,
    required this.availableCollectors,
  });

  @override
  State<PickupRequestPage> createState() => _PickupRequestPageState();
}

class _PickupRequestPageState extends State<PickupRequestPage> {
  static const Color _bg = Color(0xFF0B1220);
  static const Color _sheet = Color(0xFF121C2E);
  static const Color _surface = Color(0xFF162235);
  static const Color _surfaceAlt = Color(0xFF1B2A40);
  static const Color _border = Color(0xFF26364F);
  static const Color _accent = Color(0xFF10B981);
  static const Color _danger = Color(0xFFEF4444);
  static const Color _dropdown = Color(0xFF162235);

  static const Color _textPrimary = Color(0xFFE2E8F0);
  static const Color _textSecondary = Color(0xFF94A3B8);
  static const Color _textMuted = Color(0xFF64748B);

  String? _selectedCollectorId;
  String? _selectedCollectorName;

  String _pickupType = "now"; // now | window
  DateTime _scheduleDate = DateTime.now();
  DateTime? _windowStart;
  DateTime? _windowEnd;

  String? _selectedBagKey;

  String? _selectedSubdivision;
  String? _driverError;
  String? _windowError;
  String? _bagError;
  String? _streetError;
  String? _subdivisionError;
  String? _landmarkError;
  String? _phoneError;

  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  static const List<String> _subdivisionOptions = [
    'San Francisco Heights (Suntrust)',
    'PHirst Park Homes Calamba',
    'Lynville Residences Palo Alto',
    'Palo Alto Executive Village',
    'Southwynd Residences',
    'Pacific Hill Subdivision',
    'Hacienda Hill',
    'Palo Alto Highland 1',
    'Palo Alto Highland 2',
  ];
  static const List<Map<String, dynamic>> _bagOptions = [
    {
      "key": "small",
      "label": "Small Bag",
      "minKg": 0,
      "maxKg": 2,
      "estimatedKg": 2,
    },
    {
      "key": "medium",
      "label": "Medium Bag",
      "minKg": 2,
      "maxKg": 5,
      "estimatedKg": 5,
    },
    {
      "key": "large",
      "label": "Large Bag",
      "minKg": 5,
      "maxKg": 10,
      "estimatedKg": 10,
    },
  ];

  static const List<Map<String, dynamic>> _windowOptions = [
    {"label": "8–10 AM", "startHour": 8, "endHour": 10},
    {"label": "10–12 NN", "startHour": 10, "endHour": 12},
    {"label": "1–3 PM", "startHour": 13, "endHour": 15},
    {"label": "3–5 PM", "startHour": 15, "endHour": 17},
    {"label": "5–8 PM", "startHour": 17, "endHour": 20},
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedPhoneNumber();
  }

  @override
  void dispose() {
    _streetController.dispose();
    _landmarkController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String get _scheduleSummary {
    if (_pickupType == "now") return "Pickup: Now";
    if (_windowStart == null || _windowEnd == null) {
      return "Pickup: Choose a time window";
    }

    final d = _scheduleDate;
    final dateStr =
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    final start = _formatHm(_windowStart!);
    final end = _formatHm(_windowEnd!);
    return "Pickup: $dateStr • $start–$end";
  }

  void _snack(String msg, {Color? bg}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: bg ?? _surface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatHm(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = h >= 12 ? "PM" : "AM";
    final hh = ((h + 11) % 12) + 1;
    return "$hh:$m $suffix";
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _isValidPHPhone(String phone) {
    final normalized = phone.replaceAll(RegExp(r'[\s\-]'), '');
    final phRegex = RegExp(r'^(09\d{9}|\+639\d{9}|639\d{9})$');
    return phRegex.hasMatch(normalized);
  }

  String _normalizePHPhone(String phone) {
    final normalized = phone.replaceAll(RegExp(r'[\s\-]'), '');

    if (normalized.startsWith('+63')) return normalized;
    if (normalized.startsWith('63')) return '+$normalized';
    if (normalized.startsWith('09')) {
      return '+63${normalized.substring(1)}';
    }
    return normalized;
  }

  Future<void> _pickScheduleDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduleDate.isBefore(now) ? now : _scheduleDate,
      firstDate: _dateOnly(now),
      lastDate: _dateOnly(now.add(const Duration(days: 30))),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _accent,
              surface: _sheet,
              onPrimary: _bg,
              onSurface: _textPrimary,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: _sheet,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      _scheduleDate = picked;

      if (_windowStart != null && _windowEnd != null) {
        final startHour = _windowStart!.hour;
        final endHour = _windowEnd!.hour;
        _windowStart =
            DateTime(picked.year, picked.month, picked.day, startHour, 0);
        _windowEnd =
            DateTime(picked.year, picked.month, picked.day, endHour, 0);
      }
    });
  }

  void _selectNow() {
    setState(() {
      _pickupType = "now";
      _windowStart = null;
      _windowEnd = null;
      _scheduleDate = DateTime.now();
      _windowError = null;
    });
  }

  Future<void> _loadSavedPhoneNumber() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc =
          await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();

      final data = doc.data();
      if (data == null) return;

      final savedPhone = (data['phoneNumber'] ?? '').toString().trim();
      if (savedPhone.isNotEmpty) {
        _phoneController.text = savedPhone;
      }
    } catch (e) {
      debugPrint("Failed to load saved phone number: $e");
    }
  }

  Future<void> _savePhoneNumber(String phone) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
        'phoneNumber': phone,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Failed to save phone number: $e");
    }
  }

  Future<String> _getUserName(String uid, {String fallback = "Unknown"}) async {
    try {
      final doc =
          await FirebaseFirestore.instance.collection('Users').doc(uid).get();
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

  bool _validateForm() {
    final street = _streetController.text.trim();
    final subdivision = _selectedSubdivision ?? '';
    final landmark = _landmarkController.text.trim();
    final phone = _phoneController.text.trim();

    setState(() {
      _driverError =
          _selectedCollectorId == null ? "Please choose a driver." : null;
      _bagError = _selectedBagKey == null
          ? "Please select a bag size (required)."
          : null;
      _windowError = (_pickupType == "window" &&
              (_windowStart == null || _windowEnd == null))
          ? "Please select a time window."
          : null;
      _streetError = street.isEmpty ? "Please enter your street." : null;
      _subdivisionError =
    _selectedSubdivision == null ? "Please select your subdivision." : null;
      _landmarkError = landmark.isEmpty ? "Please enter a landmark." : null;

      if (phone.isEmpty) {
        _phoneError = "Please enter your phone number.";
      } else if (!_isValidPHPhone(phone)) {
        _phoneError = "Please enter a valid PH number (09XXXXXXXXX).";
      } else {
        _phoneError = null;
      }
    });

    return _selectedCollectorId != null &&
        _selectedBagKey != null &&
        (_pickupType == "now" ||
            (_windowStart != null && _windowEnd != null)) &&
        street.isNotEmpty &&
        subdivision.isNotEmpty &&
        landmark.isNotEmpty &&
        phone.isNotEmpty &&
        _isValidPHPhone(phone);
  }

  Future<void> requestPickupWithConfirm({
    required String bagKey,
    required String bagLabel,
    required int bagMinKg,
    required int bagMaxKg,
    required int bagEstimatedKg,
  }) async {
    final bool isWindow = _pickupType == "window";

    if (!_validateForm()) {
      _snack("Please complete all required fields.", bg: _danger);
      return;
    }

    if (isWindow && (_windowStart == null || _windowEnd == null)) {
      _snack("Please select a time window.", bg: _danger);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_selectedCollectorId == null) {
      _snack("Please choose an available collector first.", bg: _danger);
      return;
    }

    final street = _streetController.text.trim();
    final subdivision = _selectedSubdivision!;
    final landmark = _landmarkController.text.trim();
    final phoneNumber = _normalizePHPhone(_phoneController.text.trim());

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
          bg: _danger,
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
        backgroundColor: _sheet,
        title: const Text(
          "Confirm Pickup Request",
          style: TextStyle(color: _textPrimary),
        ),
        content: Text(
          "Send pickup request to $collectorName?\n\n"
          "Driver: $collectorName\n"
          "Pickup Location: ${widget.pickupSource == "pin" ? "Pinned location" : "Current GPS"}\n"
          "Address: $street, $subdivision\n"
          "Landmark: $landmark\n"
          "Phone: $phoneNumber\n"
          "$_scheduleSummary\n"
          "Bag: $bagLabel ($bagMinKg-$bagMaxKg kg estimated)\n"
          "Distance/ETA: ${widget.distanceKm.toStringAsFixed(1)} km • ${widget.etaMinutes} min\n",
          style: const TextStyle(
            color: _textSecondary,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: _textSecondary),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: _bg,
            ),
            child: const Text("Confirm"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final docRef = await FirebaseFirestore.instance.collection('requests').add({
        'type': 'pickup',
        'active': true,
        'householdId': user.uid,
        'householdName': householdName,
        'collectorId': _selectedCollectorId,
        'collectorName': collectorName,
        'pickupType': _pickupType,
        'windowStart':
            _windowStart == null ? null : Timestamp.fromDate(_windowStart!),
        'windowEnd':
            _windowEnd == null ? null : Timestamp.fromDate(_windowEnd!),
        'scheduledAt':
            _windowStart == null ? null : Timestamp.fromDate(_windowStart!),
        'status': (_pickupType == "now") ? 'pending' : 'scheduled',
        'pickupLocation': GeoPoint(
          widget.pickupLatLng.latitude,
          widget.pickupLatLng.longitude,
        ),
        'pickupAddress':
            "${widget.pickupLatLng.latitude.toStringAsFixed(5)}, ${widget.pickupLatLng.longitude.toStringAsFixed(5)}",
        'pickupSource': widget.pickupSource,
        'destinationId': 'mores',
        'destinationName': widget.moresName,
        'destinationLocation': GeoPoint(
          widget.moresLatLng.latitude,
          widget.moresLatLng.longitude,
        ),
        'street': street,
        'subdivision': subdivision,
        'landmark': landmark,
        'phoneNumber': phoneNumber,
        'fullAddress': "$street, $subdivision",
        'bagKey': bagKey,
        'bagLabel': bagLabel,
        'bagMinKg': bagMinKg,
        'bagMaxKg': bagMaxKg,
        'bagEstimatedKg': bagEstimatedKg,
        'bagKg': bagEstimatedKg,
        'distanceKm': double.parse(widget.distanceKm.toStringAsFixed(2)),
        'etaMinutes': widget.etaMinutes,
        'arrived': false,
        'arrivedAt': null,
        'cancelledAt': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _savePhoneNumber(phoneNumber);

      if (!mounted) return;

      final waitResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingCollectorPage(
            requestId: docRef.id,
            pickupLatLng: widget.pickupLatLng,
            destinationLatLng: widget.moresLatLng,
          ),
        ),
      );

      if (!mounted) return;

      if (waitResult == 'accepted') {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => const DashboardPage(initialTabIndex: 2),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) _snack("Pickup failed: $e", bg: _danger);
    }
  }

  Widget _inputField({
  required TextEditingController controller,
  required String hint,
  TextInputType keyboardType = TextInputType.text,
  int maxLines = 1,
  String? errorText,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: errorText != null ? _danger : _border,
            ),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: const TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w700,
            ),
            cursorColor: _accent,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: _textMuted),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
            onChanged: (_) {
              setState(() {
                if (controller == _streetController) _streetError = null;
                if (controller == _landmarkController) _landmarkError = null;
                if (controller == _phoneController) _phoneError = null;
              });
            },
          ),
        ),
      ),
      if (errorText != null) ...[
        const SizedBox(height: 6),
        Text(
          errorText,
          style: const TextStyle(
            color: _danger,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ],
  );
}

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        color: _textMuted,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bagMeta = _bagOptions.firstWhere(
      (b) => b["key"] == _selectedBagKey,
      orElse: () => {
        "label": "-",
        "minKg": 0,
        "maxKg": 0,
        "estimatedKg": 0,
        "key": ""
      },
    );

    final bagLabel = bagMeta["label"] as String;
    final bagMinKg = bagMeta["minKg"] as int;
    final bagMaxKg = bagMeta["maxKg"] as int;
    final bagEstimatedKg = bagMeta["estimatedKg"] as int;

    final hasCollectors = widget.availableCollectors.isNotEmpty;
    final bagPicked = _selectedBagKey != null;
    final collectorPicked = _selectedCollectorId != null;
    final isWindow = _pickupType == "window";
    final windowOk = !isWindow || (_windowStart != null && _windowEnd != null);

    final addressOk = _streetController.text.trim().isNotEmpty &&
        _selectedSubdivision != null &&
        _landmarkController.text.trim().isNotEmpty &&
        _phoneController.text.trim().isNotEmpty &&
        _isValidPHPhone(_phoneController.text.trim());

    final canSubmit = bagPicked && collectorPicked && windowOk && addressOk;

    return Theme(
      data: Theme.of(context).copyWith(
        canvasColor: _dropdown,
        chipTheme: ChipThemeData(
          backgroundColor: _surface,
          disabledColor: _surface,
          selectedColor: _accent,
          secondarySelectedColor: _accent,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          labelStyle: const TextStyle(
            color: _textPrimary,
            fontWeight: FontWeight.w700,
          ),
          secondaryLabelStyle: const TextStyle(
            color: _bg,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _border),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _sheet,
          elevation: 0,
          title: const Text(
            "Request Pickup",
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          iconTheme: const IconThemeData(color: _textPrimary),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              

              const SizedBox(height: 18),
              _sectionTitle("CHOOSE A DRIVER"),
              if (_driverError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _driverError!,
                  style: const TextStyle(color: _danger),
                ),
              ],
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _driverError != null ? _danger : _border,
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCollectorId,
                    dropdownColor: _dropdown,
                    isExpanded: true,
                    iconEnabledColor: _textSecondary,
                    hint: Text(
                      hasCollectors ? "Choose a driver" : "No collectors online",
                      style: const TextStyle(color: _textMuted),
                    ),
                    style: const TextStyle(color: _textPrimary),
                    items: widget.availableCollectors.map((c) {
                      final uid = c['uid']!;
                      final name = c['name']!;
                      return DropdownMenuItem<String>(
                        value: uid,
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: hasCollectors
                        ? (uid) {
                            if (uid == null) return;
                            final found = widget.availableCollectors
                                .firstWhere((c) => c['uid'] == uid);
                            setState(() {
                              _selectedCollectorId = uid;
                              _selectedCollectorName = found['name'];
                              _driverError = null;
                            });
                          }
                        : null,
                  ),
                ),
              ),

              const SizedBox(height: 18),
              _sectionTitle("PICKUP SCHEDULE"),
              const SizedBox(height: 8),

              Text(
                _scheduleSummary,
                style: const TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),

              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ChoiceChip(
                    label: const Text("Now"),
                    selected: _pickupType == "now",
                    selectedColor: _accent,
                    backgroundColor: _surface,
                    labelStyle: TextStyle(
                      color: _pickupType == "now" ? _bg : _textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: _border),
                    ),
                    onSelected: (_) => _selectNow(),
                  ),
                  ChoiceChip(
                    label: const Text("Schedule"),
                    selected: _pickupType == "window",
                    selectedColor: _accent,
                    backgroundColor: _surface,
                    labelStyle: TextStyle(
                      color: _pickupType == "window" ? _bg : _textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: _border),
                    ),
                    onSelected: (_) {
                      setState(() {
                        _windowError = null;
                        _pickupType = "window";
                      });
                    },
                  ),
                ],
              ),

              if (_pickupType == "window") ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    await _pickScheduleDate();
                    setState(() => _windowError = null);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _windowError != null ? _danger : _border,
                      ),
                    ),
                    child: Text(
                      "${_scheduleDate.year}-${_scheduleDate.month.toString().padLeft(2, '0')}-${_scheduleDate.day.toString().padLeft(2, '0')}",
                      style: const TextStyle(
                        color: _textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
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
                      selectedColor: _accent,
                      backgroundColor: _surface,
                      labelStyle: TextStyle(
                        color: selected ? _bg : _textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: _border),
                      ),
                      onSelected: (_) {
                        final d = _scheduleDate;
                        final start =
                            DateTime(d.year, d.month, d.day, startHour, 0);
                        final end =
                            DateTime(d.year, d.month, d.day, endHour, 0);
                        final now = DateTime.now();

                        if (end.isBefore(now)) {
                          setState(() {
                            _windowError =
                                "That time window already ended. Choose a later window.";
                          });
                          return;
                        }

                        if (start.isBefore(now.add(const Duration(minutes: 10))) &&
                            _dateOnly(d) == _dateOnly(now)) {
                          setState(() {
                            _windowError =
                                "Please choose a window at least 10 minutes from now.";
                          });
                          return;
                        }

                        setState(() {
                          _windowError = null;
                          _pickupType = "window";
                          _windowStart = start;
                          _windowEnd = end;
                        });
                      },
                    );
                  }).toList(),
                ),
                if (_windowError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _windowError!,
                    style: const TextStyle(color: _danger),
                  ),
                ],
              ],

              const SizedBox(height: 18),
              _sectionTitle("ADDRESS DETAILS"),
              const SizedBox(height: 8),
              _inputField(
                controller: _streetController,
                hint: "Street",
                errorText: _streetError,
              ),
              const SizedBox(height: 10),
              Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _subdivisionError != null ? _danger : _border,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedSubdivision,
          dropdownColor: _dropdown,
          isExpanded: true,
          hint: const Text(
            "Select Subdivision",
            style: TextStyle(color: _textMuted),
          ),
          style: const TextStyle(color: _textPrimary),
          items: _subdivisionOptions.map((sub) {
            return DropdownMenuItem<String>(
              value: sub,
              child: Text(
                sub,
                style: const TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedSubdivision = value;
              _subdivisionError = null;
            });
          },
        ),
      ),
    ),
    if (_subdivisionError != null) ...[
      const SizedBox(height: 6),
      Text(
        _subdivisionError!,
        style: const TextStyle(
          color: _danger,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ],
),
              const SizedBox(height: 10),
              _inputField(
                controller: _landmarkController,
                hint: "Landmark (example: near blue gate / basketball court)",
                errorText: _landmarkError,
              ),
              const SizedBox(height: 10),
              _inputField(
                controller: _phoneController,
                hint: "Phone Number (09XXXXXXXXX)",
                keyboardType: TextInputType.phone,
                errorText: _phoneError,
              ),

              const SizedBox(height: 18),
              _sectionTitle("BAG SIZE (REQUIRED)"),
              if (_bagError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _bagError!,
                  style: const TextStyle(color: _danger),
                ),
              ],
              const SizedBox(height: 8),

              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _bagOptions.map((b) {
                  final key = b["key"] as String;
                  final label = b["label"] as String;
                  final minKg = b["minKg"] as int;
                  final maxKg = b["maxKg"] as int;
                  final selected = _selectedBagKey == key;

                  return ChoiceChip(
                    label: Text("$label • $minKg-$maxKg kg"),
                    selected: selected,
                    selectedColor: _accent,
                    backgroundColor: _surface,
                    labelStyle: TextStyle(
                      color: selected ? _bg : _textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: _border),
                    ),
                    onSelected: (_) {
                      setState(() {
                        _selectedBagKey = key;
                        _bagError = null;
                      });
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () async {
                    final selectedId = _selectedCollectorId;
                    final stillOnline = selectedId != null &&
                        widget.availableCollectors.any(
                          (c) => c['uid'] == selectedId,
                        );

                    if (!stillOnline) {
                      _snack(
                        "Selected driver is no longer available. Please choose another.",
                        bg: _danger,
                      );
                      return;
                    }

                    if (!canSubmit) {
                      _validateForm();
                      return;
                    }

                    await requestPickupWithConfirm(
                      bagKey: _selectedBagKey!,
                      bagLabel: bagLabel,
                      bagMinKg: bagMinKg,
                      bagMaxKg: bagMaxKg,
                      bagEstimatedKg: bagEstimatedKg,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: _bg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "CONFIRM PICKUP",
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
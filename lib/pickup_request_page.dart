import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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

  static const List<Map<String, dynamic>> _bagOptions = [
    {"key": "small", "label": "Small Bag", "kg": 2},
    {"key": "medium", "label": "Medium Bag", "kg": 5},
    {"key": "large", "label": "Large Bag", "kg": 10},
  ];

  static const List<Map<String, dynamic>> _windowOptions = [
    {"label": "8–10 AM", "startHour": 8, "endHour": 10},
    {"label": "10–12 NN", "startHour": 10, "endHour": 12},
    {"label": "1–3 PM", "startHour": 13, "endHour": 15},
    {"label": "3–5 PM", "startHour": 15, "endHour": 17},
    {"label": "5–8 PM", "startHour": 17, "endHour": 20},
  ];

  String get _pickupLocationLabel {
    return widget.pickupSource == "pin"
        ? "Pinned Location"
        : "Current Location (GPS)";
  }

  String get _scheduleSummary {
    if (_pickupType == "now") return "Pickup: Now (ASAP)";
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
    });
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

  Future<void> requestPickupWithConfirm({
    required String bagKey,
    required String bagLabel,
    required int bagKg,
  }) async {
    final bool isWindow = _pickupType == "window";
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
          "$_scheduleSummary\n"
          "Bag: $bagLabel (${bagKg}kg)\n"
          "Distance/ETA: ${widget.distanceKm.toStringAsFixed(1)} km • ${widget.etaMinutes} min\n",
          style: const TextStyle(
            color: _textSecondary,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
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
      await FirebaseFirestore.instance.collection('requests').add({
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
        'bagKey': bagKey,
        'bagLabel': bagLabel,
        'bagKg': bagKg,
        'distanceKm': double.parse(widget.distanceKm.toStringAsFixed(2)),
        'etaMinutes': widget.etaMinutes,
        'arrived': false,
        'arrivedAt': null,
        'cancelledAt': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _snack("Pickup request sent!", bg: _accent);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack("Pickup failed: $e", bg: _danger);
    }
  }

  Widget _miniInfoCard({
    required String title,
    required String value,
    required IconData icon,
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
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(14),
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
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    color: _textMuted,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? _textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String? windowError;
    String? driverError;
    String? bagError;

    final bagMeta = _bagOptions.firstWhere(
      (b) => b["key"] == _selectedBagKey,
      orElse: () => {"label": "-", "kg": 0, "key": ""},
    );

    final bagLabel = bagMeta["label"] as String;
    final bagKg = bagMeta["kg"] as int;

    return Scaffold(
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
      ),
      body: StatefulBuilder(
        builder: (context, setLocal) {
          void localSet(VoidCallback fn) {
            setState(fn);
            setLocal(fn);
          }

          final hasCollectors = widget.availableCollectors.isNotEmpty;
          final bagPicked = _selectedBagKey != null;
          final collectorPicked = _selectedCollectorId != null;
          final isWindow = _pickupType == "window";
          final windowOk =
              !isWindow || (_windowStart != null && _windowEnd != null);

          final canSubmit = bagPicked && collectorPicked && windowOk;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _miniInfoCard(
                  title: "Estimated Trip",
                  value:
                      "${widget.distanceKm.toStringAsFixed(1)} km • ${widget.etaMinutes} min",
                  icon: Icons.route_outlined,
                  valueColor: _accent,
                ),
                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "PICKUP LOCATION",
                        style: TextStyle(
                          fontSize: 10,
                          color: _textMuted,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _pickupLocationLabel,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                const Text(
                  "CHOOSE A DRIVER",
                  style: TextStyle(
                    fontSize: 10,
                    color: _textMuted,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                if (driverError != null) ...[
                  const SizedBox(height: 8),
                  Text(driverError!, style: const TextStyle(color: _danger)),
                ],
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCollectorId,
                      dropdownColor: _dropdown,
                      isExpanded: true,
                      hint: Text(
                        hasCollectors
                            ? "Choose a driver"
                            : "No collectors online",
                        style: const TextStyle(color: _textMuted),
                      ),
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
                              localSet(() {
                                _selectedCollectorId = uid;
                                _selectedCollectorName = found['name'];
                                driverError = null;
                              });
                            }
                          : null,
                    ),
                  ),
                ),

                const SizedBox(height: 18),
                const Text(
                  "PICKUP SCHEDULE",
                  style: TextStyle(
                    fontSize: 10,
                    color: _textMuted,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
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
                  children: [
                    ChoiceChip(
                      label: const Text("Now (ASAP)"),
                      selected: _pickupType == "now",
                      onSelected: (_) => localSet(() {
                        windowError = null;
                        _selectNow();
                      }),
                    ),
                    ChoiceChip(
                      label: const Text("Schedule (Window)"),
                      selected: _pickupType == "window",
                      onSelected: (_) => localSet(() {
                        windowError = null;
                        _pickupType = "window";
                      }),
                    ),
                  ],
                ),

                if (_pickupType == "window") ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      await _pickScheduleDate();
                      setLocal(() => windowError = null);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _surfaceAlt,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _border),
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
                        onSelected: (_) {
                          final d = _scheduleDate;
                          final start =
                              DateTime(d.year, d.month, d.day, startHour, 0);
                          final end =
                              DateTime(d.year, d.month, d.day, endHour, 0);
                          final now = DateTime.now();

                          if (end.isBefore(now)) {
                            setLocal(() => windowError =
                                "That time window already ended. Choose a later window.");
                            return;
                          }

                          if (start.isBefore(
                                    now.add(const Duration(minutes: 10)),
                                  ) &&
                              _dateOnly(d) == _dateOnly(now)) {
                            setLocal(() => windowError =
                                "Please choose a window at least 10 minutes from now.");
                            return;
                          }

                          localSet(() {
                            windowError = null;
                            _pickupType = "window";
                            _windowStart = start;
                            _windowEnd = end;
                          });
                        },
                      );
                    }).toList(),
                  ),

                  if (windowError != null) ...[
                    const SizedBox(height: 8),
                    Text(windowError!, style: const TextStyle(color: _danger)),
                  ],
                ],

                const SizedBox(height: 18),
                const Text(
                  "BAG SIZE (REQUIRED)",
                  style: TextStyle(
                    fontSize: 10,
                    color: _textMuted,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                if (bagError != null) ...[
                  const SizedBox(height: 8),
                  Text(bagError!, style: const TextStyle(color: _danger)),
                ],
                const SizedBox(height: 8),

                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _bagOptions.map((b) {
                    final key = b["key"] as String;
                    final label = b["label"] as String;
                    final kg = b["kg"] as int;
                    final selected = _selectedBagKey == key;

                    return ChoiceChip(
                      label: Text("$label • ${kg}kg"),
                      selected: selected,
                      onSelected: (_) => localSet(() {
                        _selectedBagKey = key;
                        bagError = null;
                      }),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: canSubmit
                        ? () async {
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

                            await requestPickupWithConfirm(
                              bagKey: _selectedBagKey!,
                              bagLabel: bagLabel,
                              bagKg: bagKg,
                            );
                          }
                        : () {
                            setLocal(() {
                              if (!collectorPicked) {
                                driverError = "Please choose a driver.";
                              }
                              if (!bagPicked) {
                                bagError =
                                    "Please select a bag size (required).";
                              }
                              if (_pickupType == "window" &&
                                  (_windowStart == null || _windowEnd == null)) {
                                windowError = "Please select a time window.";
                              }
                            });
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: _bg,
                    ),
                    child: const Text(
                      "CONFIRM PICKUP",
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
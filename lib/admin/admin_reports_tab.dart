import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminReportsTab extends StatefulWidget {
  const AdminReportsTab({super.key});

  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<AdminReportsTab> {
  static const Color _bg = Color(0xFF0F172A);
  static const Color _card = Color(0xFF111928);
  static const Color _cardSoft = Color(0xFF162033);
  static const Color _accent = Color(0xFF1FA9A7);

  String _statusFilter = 'all';
  bool _busy = false;

  static const List<String> _filters = [
    'all',
    'pending',
    'reviewed',
    'resolved',
    'dismissed',
  ];

  Query<Map<String, dynamic>> _buildQuery() {
    final ref = FirebaseFirestore.instance.collection('reports');

    if (_statusFilter == 'all') {
      return ref.orderBy('createdAt', descending: true);
    }

    return ref
        .where('status', isEqualTo: _statusFilter)
        .orderBy('createdAt', descending: true);
  }

  String _reasonLabel(String code) {
    switch (code) {
      case 'harassment':
        return 'Harassment';
      case 'rude_behavior':
        return 'Rude behavior';
      case 'wrong_details':
        return 'Wrong pickup details';
      case 'resident_unavailable':
        return 'Resident unavailable';
      case 'false_complaint':
        return 'False complaint';
      case 'other':
        return 'Other';
      default:
        return code.isEmpty ? 'Unknown' : code;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orangeAccent;
      case 'reviewed':
        return Colors.lightBlueAccent;
      case 'resolved':
        return Colors.greenAccent;
      case 'dismissed':
        return Colors.redAccent;
      default:
        return Colors.white54;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_top_rounded;
      case 'reviewed':
        return Icons.preview_rounded;
      case 'resolved':
        return Icons.check_circle_rounded;
      case 'dismissed':
        return Icons.cancel_rounded;
      default:
        return Icons.flag_outlined;
    }
  }

  Future<void> _updateReportStatus({
    required String reportId,
    required String status,
  }) async {
    setState(() => _busy = true);

    try {
      await FirebaseFirestore.instance.collection('reports').doc(reportId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedBy': 'admin',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _cardSoft,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Report marked as $status.',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _cardSoft,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Failed to update report: $e',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            color: _card,
            padding: const EdgeInsets.all(8),
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Unable to load image.',
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTs(Timestamp? ts) {
    if (ts == null) return '—';
    final dt = ts.toDate();
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} • $hour:$minute $suffix';
  }

  Widget _glassPanel({
    required Widget child,
    EdgeInsets? padding,
    bool highlighted = false,
  }) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: highlighted
              ? [
                  _cardSoft,
                  _card,
                ]
              : [
                  _card,
                  const Color(0xFF0D1526),
                ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: highlighted
              ? _accent.withOpacity(0.20)
              : Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withOpacity(0.60),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.9,
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), color: color, size: 13),
          const SizedBox(width: 6),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleChip(String role) {
    final normalized = role.trim().toLowerCase();
    final color = normalized == 'collector'
        ? Colors.cyanAccent
        : normalized == 'resident'
            ? Colors.greenAccent
            : Colors.white54;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _filterChip(String status) {
    final selected = _statusFilter == status;
    final color = status == 'all' ? _accent : _statusColor(status);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      child: ChoiceChip(
        label: Text(status.toUpperCase()),
        selected: selected,
        onSelected: (_) => setState(() => _statusFilter = status),
        backgroundColor: _cardSoft,
        selectedColor: color.withOpacity(0.18),
        labelStyle: TextStyle(
          color: selected ? color : Colors.white.withOpacity(0.78),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
        side: BorderSide(
          color: selected
              ? color.withOpacity(0.55)
              : Colors.white.withOpacity(0.08),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
    required IconData icon,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: onTap == null ? color.withOpacity(0.35) : color,
        foregroundColor: Colors.black,
        disabledForegroundColor: Colors.black54,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.62),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: emphasize ? 13 : 12.5,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaBlock({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.62),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Future<Map<String, String>> _loadExtraDetails({
    required String reporterId,
    required String reportedUserId,
    required String requestId,
  }) async {
    DocumentSnapshot<Map<String, dynamic>>? reporterDoc;
    DocumentSnapshot<Map<String, dynamic>>? reportedDoc;
    DocumentSnapshot<Map<String, dynamic>>? requestDoc;

    if (reporterId.isNotEmpty) {
      reporterDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(reporterId)
          .get();
    }

    if (reportedUserId.isNotEmpty) {
      reportedDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(reportedUserId)
          .get();
    }

    if (requestId.isNotEmpty) {
      requestDoc = await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .get();
    }

    final reporterData = reporterDoc?.data();
    final reportedData = reportedDoc?.data();
    final requestData = requestDoc?.data();

    return {
      'reporterName': (reporterData?['fullName'] ??
              reporterData?['name'] ??
              reporterData?['username'] ??
              reporterId)
          .toString(),
      'reportedName': (reportedData?['fullName'] ??
              reportedData?['name'] ??
              reportedData?['username'] ??
              reportedUserId)
          .toString(),
      'address': (requestData?['fullAddress'] ??
              requestData?['pickupAddress'] ??
              '—')
          .toString(),
      'phone': (requestData?['phoneNumber'] ?? '—').toString(),
    };
  }

  Widget _buildHeaderCard() {
    return _glassPanel(
      highlighted: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 🔙 BACK BUTTON
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),

          const SizedBox(width: 12),

          // ICON
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(color: _accent.withOpacity(0.30)),
            ),
            child: const Icon(
              Icons.flag_rounded,
              color: _accent,
              size: 20,
            ),
          ),

          const SizedBox(width: 12),

          // TITLE
          const Expanded(
            child: Text(
              'Reports',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    final reasonCode = (data['reasonCode'] ?? '').toString();
    final reasonText = (data['reasonText'] ?? '').toString();
    final status = (data['status'] ?? 'pending').toString().toLowerCase();
    final reporterRole = (data['reporterRole'] ?? '').toString();
    final reportedRole = (data['reportedRole'] ?? '').toString();
    final reporterId = (data['reporterId'] ?? '').toString();
    final reportedUserId = (data['reportedUserId'] ?? '').toString();
    final requestId = (data['requestId'] ?? '').toString();
    final createdAt = data['createdAt'] is Timestamp
        ? data['createdAt'] as Timestamp
        : null;

    final images = (data['evidenceImageUrls'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();

    return FutureBuilder<Map<String, String>>(
      future: _loadExtraDetails(
        reporterId: reporterId,
        reportedUserId: reportedUserId,
        requestId: requestId,
      ),
      builder: (context, extraSnap) {
        final extra = extraSnap.data ?? {};
        final reporterName = extra['reporterName'] ?? reporterId;
        final reportedName = extra['reportedName'] ?? reportedUserId;
        final address = extra['address'] ?? '—';
        final phone = extra['phone'] ?? '—';

        return _glassPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _accent.withOpacity(0.20),
                      ),
                    ),
                    child: const Icon(
                      Icons.report_problem_outlined,
                      color: _accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${reporterRole.toUpperCase()} reported ${reportedRole.toUpperCase()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _reasonLabel(reasonCode),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.68),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _statusChip(status),
                ],
              ),

              const SizedBox(height: 14),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _roleChip(reporterRole),
                  _roleChip(reportedRole),
                ],
              ),

              const SizedBox(height: 16),

              _metaBlock(
                title: 'Report Details',
                children: [
                  _infoRow('Details', reasonText.isEmpty ? '—' : reasonText, emphasize: true),
                  _infoRow('Created', _formatTs(createdAt)),
                  _infoRow('Request ID', requestId.isEmpty ? '—' : requestId),
                ],
              ),

              const SizedBox(height: 12),

              _metaBlock(
                title: 'People & Pickup Info',
                children: [
                  _infoRow('Reporter', reporterName.isEmpty ? '—' : reporterName),
                  _infoRow('Reported User', reportedName.isEmpty ? '—' : reportedName),
                  _infoRow('Address', address),
                  _infoRow('Phone', phone),
                ],
              ),

              if (images.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.image_outlined,
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Evidence (${images.length})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: images.map((url) {
                    return InkWell(
                      onTap: () => _openImagePreview(url),
                      borderRadius: BorderRadius.circular(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 108,
                          height: 108,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.45),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: const Icon(
                                    Icons.open_in_full,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 16),

              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _actionButton(
                    label: 'Reviewed',
                    color: Colors.lightBlueAccent,
                    icon: Icons.visibility_outlined,
                    onTap: status == 'reviewed'
                        ? null
                        : () => _updateReportStatus(
                              reportId: doc.id,
                              status: 'reviewed',
                            ),
                  ),
                  _actionButton(
                    label: 'Resolved',
                    color: Colors.greenAccent,
                    icon: Icons.check_circle_outline,
                    onTap: status == 'resolved'
                        ? null
                        : () => _updateReportStatus(
                              reportId: doc.id,
                              status: 'resolved',
                            ),
                  ),
                  _actionButton(
                    label: 'Dismiss',
                    color: Colors.redAccent,
                    icon: Icons.close_rounded,
                    onTap: status == 'dismissed'
                        ? null
                        : () => _updateReportStatus(
                              reportId: doc.id,
                              status: 'dismissed',
                            ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _buildQuery();

    return Material(
      color: Colors.transparent,
      child: Container(
        color: _bg,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderCard(),
              const SizedBox(height: 16),

              _sectionLabel('Filter Reports'),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _filters.map(_filterChip).toList(),
              ),

              const SizedBox(height: 12),

              if (_busy)
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: const AlwaysStoppedAnimation(_accent),
                    minHeight: 4,
                  ),
                ),

              const SizedBox(height: 14),

              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: query.snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: _glassPanel(
                          child: Text(
                            'Error loading reports: ${snap.error}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      );
                    }

                    if (!snap.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: _accent),
                      );
                    }

                    final docs = snap.data!.docs;

                    if (docs.isEmpty) {
                      return Center(
                        child: _glassPanel(
                          highlighted: true,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: _accent.withOpacity(0.14),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _accent.withOpacity(0.30),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.inbox_outlined,
                                  color: _accent,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No reports found',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Reports submitted by collectors or households will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.68),
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (_, i) => _buildReportCard(docs[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
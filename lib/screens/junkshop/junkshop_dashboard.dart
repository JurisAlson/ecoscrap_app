import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../receipt_screen.dart' as receipt;
import '../analytics_home_tab.dart';
import '../inventory_screen.dart';
import '../transaction_screen.dart' as transaction;
import '../../chat/screens/chat_list_page.dart';

class JunkshopDashboardPage extends StatefulWidget {
  final String shopID;
  final String shopName;

  const JunkshopDashboardPage({
    super.key,
    required this.shopID,
    required this.shopName,
  });

  @override
  State<JunkshopDashboardPage> createState() => _JunkshopDashboardPageState();
}

class _JunkshopDashboardPageState extends State<JunkshopDashboardPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _activeTabIndex = 0;

  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  late final PageController _pageController = PageController(initialPage: 0);
  static const double _bottomNavHeight = 96;

  // ✅ Always use auth uid as the shopId (RBAC)
  String get _shopIdSafe =>
      FirebaseAuth.instance.currentUser?.uid ?? widget.shopID;

  // ✅ Get live shop doc from Users (no old Junkshop collection)
  Stream<DocumentSnapshot<Map<String, dynamic>>> get _shopDocStream =>
      FirebaseFirestore.instance.collection("Users").doc(_shopIdSafe).snapshots();

  void _goToTab(int index) {
    setState(() => _activeTabIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _shopDocStream,
      builder: (context, snap) {
        final shopData = snap.data?.data() ?? {};
        final shopId = _shopIdSafe;

        // Keep format: still display a name in UI, but we do NOT use it for logic.
        final shopName =
            (shopData["name"] ?? shopData["shopName"] ?? widget.shopName)
                .toString();

        final tabs = <Widget>[
          AnalyticsHomeTab(
            shopID: shopId,
            shopName: shopName,
            onOpenProfile: () => _scaffoldKey.currentState?.openDrawer(),
            notifBell: _buildJunkshopNotifBell(),
          ),
          InventoryScreen(shopID: shopId),
          const ChatListPage(
            type: "junkshop",
            title: "",
          ),
          transaction.TransactionScreen(shopID: shopId),
        ];

        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: bgColor,
            extendBody: true,

            drawer: Drawer(
              backgroundColor: bgColor,
              child: SafeArea(child: _profileDrawer(user, shopId, shopName)),
            ),

            endDrawer: Drawer(
              backgroundColor: bgColor,
              child: SafeArea(child: _notificationsDrawer()),
            ),

            bottomNavigationBar: _fixedBottomNav(),

            body: Stack(
              children: [
                _blurCircle(primaryColor.withOpacity(0.15), 300,
                    top: -100, right: -100),
                _blurCircle(Colors.green.withOpacity(0.1), 350,
                    bottom: 100, left: -100),
                SafeArea(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) => setState(() => _activeTabIndex = i),
                    children: tabs,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ================= FIXED BOTTOM NAV =================
  Widget _fixedBottomNav() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: _bottomNavHeight,
          decoration: BoxDecoration(
            color: bgColor.withOpacity(0.86),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(0, Icons.storefront_outlined, "Home"),
                  _navItem(1, Icons.inventory_2_outlined, "Inventory"),
                  _chatNavItem(2),
                  _navItem(3, Icons.receipt_long_outlined, "Transactions"),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chatNavItem(int index) {
    return _navItem(index, Icons.chat_bubble_outline, "Chats");
  }

  Widget _buildJunkshopNotifBell() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return InkWell(
        onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
        borderRadius: BorderRadius.circular(50),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.notifications_outlined, color: Colors.grey.shade300),
        ),
      );
    }

final sellRequestsStream = FirebaseFirestore.instance
    .collection('Users')
    .doc(uid)
    .collection('sell_requests')
    .snapshots();

final dropoffRequestsStream = FirebaseFirestore.instance
    .collection('dropoff_requests')
    .where('junkshopId', isEqualTo: uid)
    .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: sellRequestsStream,
      builder: (context, sellSnap) {
        final sellUnread = (sellSnap.data?.docs ?? []).where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final seen = data['seen'] == true;
        final receiptSaved = data['receiptSaved'] == true;
        final status = (data['status'] ?? '').toString();

        return !seen &&
            !receiptSaved &&
            status != 'completed' &&
            status != 'processed';
      }).length;

        return StreamBuilder<QuerySnapshot>(
          stream: dropoffRequestsStream,
          builder: (context, dropSnap) {
            final dropUnread = (dropSnap.data?.docs ?? []).where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final readByJunkshop = data['readByJunkshop'] == true;
            final receiptSaved = data['receiptSaved'] == true;
            final cleared = data['clearedByJunkshop'] == true;
            final status = (data['status'] ?? '').toString();

            return !readByJunkshop &&
                !receiptSaved &&
                !cleared &&
                status != 'completed';
          }).length;
            final unreadCount = sellUnread + dropUnread;
            final hasUnread = unreadCount > 0;

            return Stack(
              children: [
                InkWell(
                  onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
                  borderRadius: BorderRadius.circular(50),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.notifications_outlined,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ),
                if (hasUnread)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _clearAllCancelledDropoffs() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final snap = await FirebaseFirestore.instance
      .collection('dropoff_requests')
      .where('junkshopId', isEqualTo: user.uid)
      .where('status', isEqualTo: 'cancelled')
      .get();

  final batch = FirebaseFirestore.instance.batch();

  for (final doc in snap.docs) {
    final data = doc.data();
    final cleared = data['clearedByJunkshop'] == true;

    if (!cleared) {
      batch.set(
        doc.reference,
        {
          'clearedByJunkshop': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  await batch.commit();
}

  // ================= DRAWERS =================
  Widget _notificationsDrawer() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(
        child: Text("Not logged in.", style: TextStyle(color: Colors.white)),
      );
    }

final sellRequestsStream = FirebaseFirestore.instance
    .collection('Users')
    .doc(user.uid)
    .collection('sell_requests')
    .orderBy('createdAt', descending: true)
    .limit(50)
    .snapshots();

final dropoffRequestsStream = FirebaseFirestore.instance
    .collection('dropoff_requests')
    .where('junkshopId', isEqualTo: user.uid)
    .orderBy('createdAt', descending: true)
    .limit(50)
    .snapshots();

    String hhmm(DateTime dt) =>
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

    String dropoffTitleFromStatus(String status) {
      switch (status) {
        case 'arrived':
          return 'Household arrived';
        case 'cancelled':
          return 'Drop-off cancelled';
        case 'completed':
          return 'Drop-off completed';
        case 'en_route':
        default:
          return 'Incoming drop-off';
      }
    }

    String dropoffMessageFromData(Map<String, dynamic> data) {
      final householdName = (data['householdName'] ?? 'A household').toString();
      final junkshopName = (data['junkshopName'] ?? 'your junkshop').toString();
      final status = (data['status'] ?? '').toString();
      final reason = (data['cancelReason'] ?? '').toString().trim();

      switch (status) {
        case 'arrived':
          return '$householdName has arrived at $junkshopName.';
        case 'cancelled':
          if (reason.isNotEmpty) {
            return '$householdName cancelled the drop-off. Reason: $reason';
          }
          return '$householdName cancelled the drop-off.';
        case 'completed':
          return '$householdName completed the drop-off.';
        case 'en_route':
        default:
          return '$householdName is on the way to $junkshopName.';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
Row(
  children: [
    IconButton(
      icon: const Icon(Icons.close, color: Colors.white),
      onPressed: () => Navigator.pop(context),
    ),
    const SizedBox(width: 8),
    const Expanded(
      child: Text(
        "Notifications",
        style: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
    TextButton(
      onPressed: () async {
        await _clearAllCancelledDropoffs();
      },
      child: const Text(
        "Clear",
        style: TextStyle(
          color: Colors.redAccent,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  ],
),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: sellRequestsStream,
              builder: (context, sellSnap) {
                return StreamBuilder<QuerySnapshot>(
                  stream: dropoffRequestsStream,
                  builder: (context, dropSnap) {
                    if (sellSnap.connectionState == ConnectionState.waiting ||
                        dropSnap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (sellSnap.hasError) {
                      return Center(
                        child: Text(
                          "Error loading sell requests: ${sellSnap.error}",
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

                    if (dropSnap.hasError) {
                      return Center(
                        child: Text(
                          "Error loading drop-off requests: ${dropSnap.error}",
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }

final List<Map<String, dynamic>> items = [];

// SELL REQUESTS
for (final d in sellSnap.data?.docs ?? []) {
  final data = d.data() as Map<String, dynamic>;
  final status = (data['status'] ?? '').toString();
  final receiptSaved = data['receiptSaved'] == true;

  if (receiptSaved || status == 'completed' || status == 'processed') {
    continue;
  }

  final ts = data['createdAt'] as Timestamp?;
  items.add({
    'kind': 'sell_request',
    'docId': d.id,
    'data': data,
    'createdAt': ts,
  });
}

// DROPOFF REQUESTS
for (final d in dropSnap.data?.docs ?? []) {
  final data = d.data() as Map<String, dynamic>;
  final status = (data['status'] ?? '').toString();
  final receiptSaved = data['receiptSaved'] == true;
  final cleared = data['clearedByJunkshop'] == true;

  if (receiptSaved || status == 'completed' || cleared) {
    continue;
  }

  final ts = (data['updatedAt'] as Timestamp?) ??
      (data['createdAt'] as Timestamp?);

  items.add({
    'kind': 'dropoff_request',
    'docId': d.id,
    'data': data,
    'createdAt': ts,
  });
}

                    items.sort((a, b) {
                      final aTs = a['createdAt'] as Timestamp?;
                      final bTs = b['createdAt'] as Timestamp?;
                      if (aTs == null && bTs == null) return 0;
                      if (aTs == null) return 1;
                      if (bTs == null) return -1;
                      return bTs.compareTo(aTs);
                    });

                    if (items.isEmpty) {
                      return const Center(
                        child: Text(
                          "No notifications yet.",
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        final kind = item['kind'] as String;
                        final docId = item['docId'] as String;
                        final data = item['data'] as Map<String, dynamic>;
                        final ts = item['createdAt'] as Timestamp?;
                        final dt = ts?.toDate();

                        if (kind == 'sell_request') {
                          final collectorName =
                              (data['collectorName'] ?? '').toString().trim();
                          final collectorId =
                              (data['collectorId'] ?? '').toString().trim();
                          final kg = ((data['kg'] as num?) ?? 0).toDouble();
                          final seen = data['seen'] == true;
                          final status = (data['status'] ?? '').toString();

                          final sellTitle = status == 'arrived'
                              ? (collectorName.isEmpty
                                  ? "Collector arrived"
                                  : "$collectorName arrived at Mores Scrap")
                              : (collectorName.isEmpty
                                  ? "Incoming collector sell request"
                                  : "$collectorName is on the way");

                          final sellSubtitle = status == 'arrived'
                              ? "${kg.toStringAsFixed(2)} kg ready for confirmation"
                              : "${kg.toStringAsFixed(2)} kg incoming";

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                              ),
                            ),
                            child: ListTile(
                              onTap: status == 'arrived'
                                  ? () async {
                                      final action = await showDialog<String>(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          backgroundColor: const Color(0xFF0F172A),
                                          title: const Text(
                                            "Confirm arrival",
                                            style: TextStyle(color: Colors.white),
                                          ),
                                          content: Text(
                                            collectorName.isEmpty
                                                ? "Did the collector really arrive at Mores Scrap?"
                                                : "Did $collectorName really arrive at Mores Scrap?",
                                            style: const TextStyle(color: Colors.white70),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, 'dismiss'),
                                              child: const Text(
                                                "NOT HERE",
                                                style: TextStyle(color: Colors.redAccent),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, 'proceed'),
                                              child: const Text(
                                                "PROCEED",
                                                style: TextStyle(color: Colors.greenAccent),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (action == 'dismiss') {
                                        await FirebaseFirestore.instance
                                            .collection('Users')
                                            .doc(user.uid)
                                            .collection('sell_requests')
                                            .doc(docId)
                                            .set({
                                          'seen': true,
                                          'status': 'dismissed',
                                          'updatedAt': FieldValue.serverTimestamp(),
                                        }, SetOptions(merge: true));

                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Sell request dismissed.")),
                                        );
                                        return;
                                      }

                                      if (action != 'proceed') return;

                                      await FirebaseFirestore.instance
                                          .collection('Users')
                                          .doc(user.uid)
                                          .collection('sell_requests')
                                          .doc(docId)
                                          .set({
                                        'seen': true,
                                        'status': 'confirmed',
                                        'junkshopConfirmedArrival': true,
                                        'updatedAt': FieldValue.serverTimestamp(),
                                      }, SetOptions(merge: true));

                                      if (!context.mounted) return;
                                      Navigator.pop(context);

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => receipt.ReceiptScreen(
                                            shopID: user.uid,
                                            prefillCollectorName:
                                                collectorName.isEmpty ? null : collectorName,
                                            prefillCollectorId:
                                                collectorId.isEmpty ? null : collectorId,
                                            sellRequestId: docId,
                                            prefillSourceType: "collector",
                                          ),
                                        ),
                                      );
                                    }
                                  : () async {
                                      await FirebaseFirestore.instance
                                          .collection('Users')
                                          .doc(user.uid)
                                          .collection('sell_requests')
                                          .doc(docId)
                                          .set({
                                        'seen': true,
                                        'updatedAt': FieldValue.serverTimestamp(),
                                      }, SetOptions(merge: true));
                                    },
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: status == 'arrived'
                                      ? Colors.green.withOpacity(0.15)
                                      : seen
                                          ? Colors.white.withOpacity(0.08)
                                          : Colors.orange.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  status == 'arrived'
                                      ? Icons.check_circle_outline
                                      : Icons.local_shipping_outlined,
                                  color: status == 'arrived'
                                      ? Colors.greenAccent
                                      : seen
                                          ? Colors.white70
                                          : Colors.orangeAccent,
                                ),
                              ),
                              title: Text(
                                sellTitle,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                sellSubtitle,
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 12,
                                ),
                              ),
                              trailing: Text(
                                dt == null ? "" : hhmm(dt),
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          );
                        }
                        final status = (data['status'] ?? 'en_route').toString();
                        final title = dropoffTitleFromStatus(status);
                        final message = dropoffMessageFromData(data);
                        final householdName =
                            (data['householdName'] ?? '').toString().trim();
                        final householdId =
                            (data['householdId'] ?? '').toString().trim();
                        final readByJunkshop = data['readByJunkshop'] == true;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: ListTile(
                            onTap: status == 'arrived'
                                ? () async {
                                    final action = await showDialog<String>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        backgroundColor: const Color(0xFF0F172A),
                                        title: const Text(
                                          "Confirm arrival",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                        content: Text(
                                          householdName.isEmpty
                                              ? "Has the resident really arrived?"
                                              : "Has $householdName really arrived at the junkshop?",
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, 'dismiss'),
                                            child: const Text(
                                              "NOT HERE",
                                              style: TextStyle(color: Colors.redAccent),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(context, 'proceed'),
                                            child: const Text(
                                              "PROCEED",
                                              style: TextStyle(color: Colors.greenAccent),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (action == 'dismiss') {
                                      await FirebaseFirestore.instance
                                          .collection('dropoff_requests')
                                          .doc(docId)
                                          .set({
                                        'clearedByJunkshop': true,
                                        'updatedAt': FieldValue.serverTimestamp(),
                                      }, SetOptions(merge: true));

                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text("Drop-off notification dismissed.")),
                                      );
                                      return;
                                    }

                                    if (action != 'proceed') return;

                                    await FirebaseFirestore.instance
                                        .collection('dropoff_requests')
                                        .doc(docId)
                                        .set({
                                      'readByJunkshop': true,
                                      'updatedAt': FieldValue.serverTimestamp(),
                                    }, SetOptions(merge: true));

                                    if (!context.mounted) return;
                                    Navigator.pop(context);

                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => receipt.ReceiptScreen(
                                          shopID: user.uid,
                                          prefillCollectorName:
                                              householdName.isEmpty ? null : householdName,
                                          prefillCollectorId:
                                              householdId.isEmpty ? null : householdId,
                                          prefillSourceType: "household",
                                          sellRequestId: docId,
                                        ),
                                      ),
                                    );
                                  }
                                : null,
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: readByJunkshop
                      ? Colors.white.withOpacity(0.08)
                      : status == 'cancelled'
                          ? Colors.red.withOpacity(0.15)
                          : status == 'arrived'
                              ? Colors.green.withOpacity(0.15)
                              : Colors.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  status == 'cancelled'
                      ? Icons.cancel_outlined
                      : status == 'arrived'
                          ? Icons.check_circle_outline
                          : Icons.store_mall_directory_outlined,
                  color: readByJunkshop
                      ? Colors.white70
                      : status == 'cancelled'
                          ? Colors.redAccent
                          : status == 'arrived'
                              ? Colors.greenAccent
                              : Colors.lightBlueAccent,
                              ),
                            ),
                            title: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              message,
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                            trailing: Text(
                              dt == null ? "" : hhmm(dt),
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileDrawer(User? user, String shopId, String shopName) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              const Text(
                "Profile",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Icon(Icons.storefront, size: 80, color: Colors.white54),
          const SizedBox(height: 14),
          Text(
            shopName,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(user?.email ?? "",
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 18),

          // Impact card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Impact",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 10),
                Text(
                  "Your junkshop helps the community and the environment by increasing recycling, supporting collectors, and reducing waste in landfills.",
                  style: TextStyle(
                      color: Colors.white70, fontSize: 13, height: 1.3),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),



          const SizedBox(height: 22),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (!mounted) return;
                Navigator.pushReplacementNamed(context, '/login');
              },
              icon: const Icon(Icons.logout),
              label: const Text("Logout"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================= NAV ITEM =================
  Widget _navItem(int index, IconData icon, String label) {
    final isActive = _activeTabIndex == index;

    return GestureDetector(
      onTap: () => _goToTab(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isActive ? primaryColor : Colors.grey.shade500),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isActive ? primaryColor : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= BACKGROUND BLUR =================
  Widget _blurCircle(
    Color color,
    double size, {
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}
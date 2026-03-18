import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants/categories.dart';
import 'package:intl/intl.dart';

class ReceiptScreen extends StatefulWidget {
  final String shopID;

  final String? prefillCollectorName;
  final String? prefillCollectorId;
  final String? sellRequestId;
  final String? prefillSourceType; // "collector" | "household" | null

  final String? initialTransactionType; // "sell" or "buy"

  const ReceiptScreen({
    super.key,
    required this.shopID,
    this.prefillCollectorName,
    this.prefillCollectorId,
    this.sellRequestId,
    this.initialTransactionType,
    this.prefillSourceType,
  });

  

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  final TextEditingController _walkInNameCtrl = TextEditingController();
  final TextEditingController _sourceNameCtrl = TextEditingController();
  final TextEditingController _customerCtrl = TextEditingController();

  final ScrollController _scrollCtrl = ScrollController();

final NumberFormat _num2 = NumberFormat('#,##0.##');

String _formatMoney(num value) {
  if (value % 1 == 0) {
    return NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 0,
    ).format(value);
  }

  return NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 2,
  ).format(value);
}

String _formatKg(num value) => '${_num2.format(value)} kg';
String _formatNumber(num value) => _num2.format(value);

  bool _saving = false;
  String _txType = "sell"; // sell | buy

  static const List<String> _sellBranches = [
    "JMC Plastic Corporation Valenzuela City",
    "ECO fortunes Cabuyao City",
  ];
  String? _selectedSellBranch;

  String? _sourceUserId;

  final List<_ReceiptItem> _items = [];

double get _transportCost {
  if (_txType != "sell") return 0.0;

  final kg = _totalWeightKg;
  final branch = _selectedSellBranch ?? "";

  if (branch == "ECO fortunes Cabuyao City") {
    if (kg >= 1000 && kg <= 4000) return 4000.0;
    return 0.0;
  }

  // Default: JMC Plastic Corporation Valenzuela City
  if (kg >= 4000 && kg <= 8000) return 10000.0;
  if (kg > 8000 && kg <= 12000) return 15000.0;
  if (kg > 12000 && kg <= 18000) return 18000.0;

  return 0.0;
}
double get _sellMinKg {
  final branch = _selectedSellBranch ?? "";

  if (branch == "ECO fortunes Cabuyao City") {
    return 1000.0;
  }

  return 4000.0;
}

double get _sellMaxKg {
  final branch = _selectedSellBranch ?? "";

  if (branch == "ECO fortunes Cabuyao City") {
    return 4000.0;
  }

  return 18000.0;
}

  double get _netSellAmount {
    if (_txType != "sell") return _totalAmount;

    final net = _totalAmount - _transportCost;
    return net < 0 ? 0.0 : net;
  }

  double get _totalAmount => _items.fold(0.0, (sum, it) => sum + it.subtotal);

  double get _totalWeightKg {
    return _items.fold(
      0.0,
      (sum, it) => sum + (double.tryParse(it.weightCtrl.text.trim()) ?? 0.0),
    );
  }

  bool get _isPrefilledCollectorBuy =>
      !(_openedFromCollectorSellRequest) &&
      (widget.prefillSourceType == "collector");

  bool get _isPrefilledHouseholdWalkIn =>
      !(_openedFromCollectorSellRequest) &&
      (widget.prefillSourceType == "household");

  bool get _openedFromCollectorSellRequest =>
      (widget.sellRequestId?.trim().isNotEmpty ?? false) &&
      widget.prefillSourceType == "collector";

  bool _isLockedSellRequestItem(int index) => false;

  Set<String> _selectedSellInventoryIds({_ReceiptItem? exceptItem}) {
    return _items
        .where((it) => it.inventoryDocId != null && !identical(it, exceptItem))
        .map((it) => it.inventoryDocId!)
        .toSet();
  }

  bool _isSellItemOverStock(_ReceiptItem item) {
    if (_txType != "sell") return false;

    if (item.inventoryDocId == null) return false;

    final totalForSameInventory = _items
        .where((it) => it.inventoryDocId == item.inventoryDocId)
        .fold<double>(
          0.0,
          (sum, it) => sum + (double.tryParse(it.weightCtrl.text.trim()) ?? 0.0),
        );

    return totalForSameInventory > item.availableKg;
  }

  double _remainingSellKg(_ReceiptItem item) {
    if (item.inventoryDocId == null) return 0.0;

    final totalForSameInventory = _items
        .where((it) => it.inventoryDocId == item.inventoryDocId)
        .fold<double>(
          0.0,
          (sum, it) => sum + (double.tryParse(it.weightCtrl.text.trim()) ?? 0.0),
        );

    final remaining = item.availableKg - totalForSameInventory;
    return remaining < 0 ? 0.0 : remaining;
  }

  bool get _hasInvalidSellWeight {
    if (_txType != "sell") return false;
    for (final item in _items) {
      if (_isSellItemOverStock(item)) return true;
    }
    return false;
  }

  void _recalcBuyItem(_ReceiptItem it) {
    if (_txType != "buy") return;

    final cat = normalizeCategoryKey(it.categoryValue ?? kMajorCategories.first);
    final kg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;

    final costPerKg = kFixedBuyCostPerKg[cat] ?? 0.0;
    it.buyCostPerKg = costPerKg;

    final totalCost = kg * costPerKg;
    it.subtotalCtrl.text = _formatNumber(totalCost);
  }

  void _recalcSellItem(_ReceiptItem it, {bool keepManualPrice = true}) {
    if (_txType != "sell") return;

    final cat = normalizeCategoryKey(it.categoryValue ?? kMajorCategories.first);
    final kg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;

    final defaultSellPerKg = kFixedSellPricePerKg[cat] ?? 0.0;

    if (!keepManualPrice || it.sellPricePerKg == null || it.sellPricePerKg! <= 0) {
      it.sellPricePerKg = defaultSellPerKg;
    }

    final sellPerKg = it.sellPricePerKg ?? defaultSellPerKg;
    final sellTotal = kg * sellPerKg;
    it.subtotalCtrl.text = _formatNumber(sellTotal);
  }

  

  Future<void> _addItem() async {
    final it = _ReceiptItem();

    if (_txType == "buy") {
      it.categoryValue = kMajorCategories.first;
      it.subCategoryValue = kBuySubCategories.first;
      _recalcBuyItem(it);
    }

    setState(() {
      _items.add(it);
    });

    await Future.delayed(const Duration(milliseconds: 120));

    if (_scrollCtrl.hasClients) {
      await _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 260,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }

    if (!mounted) return;

    if (_txType == "sell") {
      await _pickInventoryItem(it);
    }
  }

  void _removeItem(int index) => setState(() {
        _items[index].dispose();
        _items.removeAt(index);
      });

  @override
  void initState() {
    super.initState();

    _selectedSellBranch = _sellBranches.first;

    if (widget.initialTransactionType == "buy" ||
        widget.initialTransactionType == "sell") {
      _txType = widget.initialTransactionType!;
    }

    final name = widget.prefillCollectorName?.trim() ?? "";
    final id = widget.prefillCollectorId?.trim();

    if (_openedFromCollectorSellRequest) {
      _txType = "buy";

      if (name.isNotEmpty) {
        _sourceNameCtrl.text = name;
      }

      _sourceUserId = (id != null && id.isNotEmpty) ? id : null;

      final it = _ReceiptItem();
      it.categoryValue = kMajorCategories.first;
      it.subCategoryValue = kBuySubCategories.first;
      _recalcBuyItem(it);
      _items.add(it);
    } else if (_isPrefilledCollectorBuy) {
      _txType = "buy";

      if (name.isNotEmpty) {
        _sourceNameCtrl.text = name;
      }

      _sourceUserId = (id != null && id.isNotEmpty) ? id : null;

      final it = _ReceiptItem();
      it.categoryValue = kMajorCategories.first;
      it.subCategoryValue = kBuySubCategories.first;
      _recalcBuyItem(it);
      _items.add(it);
    } else if (_isPrefilledHouseholdWalkIn) {
      _txType = "buy";

      if (name.isNotEmpty) {
        _walkInNameCtrl.text = name;
      }

      _sourceUserId = null;

      final it = _ReceiptItem();
      it.categoryValue = kMajorCategories.first;
      it.subCategoryValue = kBuySubCategories.first;
      _recalcBuyItem(it);
      _items.add(it);
    }

    if (_items.isEmpty) {
      final it = _ReceiptItem();

      if (_txType == "buy") {
        it.categoryValue = kMajorCategories.first;
        it.subCategoryValue = kBuySubCategories.first;
        _recalcBuyItem(it);
      }

      _items.add(it);
    }
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _sourceNameCtrl.dispose();
    _walkInNameCtrl.dispose();
    _scrollCtrl.dispose();

    for (final i in _items) {
      i.dispose();
    }

    super.dispose();
  }

  Future<void> _pickInventoryItem(_ReceiptItem item) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _InventoryPickerSheet(
        shopID: widget.shopID,
        excludedInventoryIds: _selectedSellInventoryIds(exceptItem: item),
      ),
    );

    if (picked == null) return;

    setState(() {
      item.inventoryDocId = picked['id'] as String;
      item.sellPickedName = (picked['name'] ?? '').toString();
      item.categoryValue = (picked['category'] ?? '').toString();
      item.subCategoryValue = (picked['subCategory'] ?? '').toString();
      item.availableKg = (picked['unitsKg'] as num?)?.toDouble() ?? 0.0;

      item.sellPricePerKg =
          kFixedSellPricePerKg[normalizeCategoryKey(item.categoryValue ?? "")] ??
              0.0;
      _recalcSellItem(item, keepManualPrice: true);
    });
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.055),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );
  }

  Future<String?> _findInventoryDocIdForBuy(String cat, String sub) async {
    final snap = await FirebaseFirestore.instance
        .collection('Users')
        .doc(widget.shopID)
        .collection('inventory')
        .where('category', isEqualTo: cat)
        .where('subCategory', isEqualTo: sub)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  Future<void> _saveReceipt() async {
  if (_saving) return;
  setState(() => _saving = true);

  final isSell = _txType == "sell";
  final fromCollectorSellRequest = _openedFromCollectorSellRequest;

  final fromHouseholdDropoff = !isSell &&
      widget.prefillSourceType == "household" &&
      (widget.sellRequestId?.trim().isNotEmpty ?? false);

  final isWalkInBuy = !isSell &&
      !_openedFromCollectorSellRequest &&
      (_isPrefilledHouseholdWalkIn || _sourceUserId == null);

  final collectorName = _sourceNameCtrl.text.trim();
  final walkInName = _walkInNameCtrl.text.trim();

  try {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add at least 1 item.")),
      );
      return;
    }

    if (!isSell) {
      if (isWalkInBuy) {
        if (walkInName.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Enter walk-in name.")),
          );
          return;
        }
      } else {
        if (collectorName.isEmpty && !fromHouseholdDropoff) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Collector info is missing.")),
          );
          return;
        }
      }
    }

    final sourceType = isSell
        ? ""
        : fromHouseholdDropoff
            ? "household"
            : (isWalkInBuy ? "walkin" : "collector");

    final sourceName = isSell
        ? ""
        : fromHouseholdDropoff
            ? walkInName
            : (isWalkInBuy ? walkInName : collectorName);

    final partyName = isSell
        ? _selectedSellBranch
        : fromHouseholdDropoff
            ? walkInName
            : (isWalkInBuy ? walkInName : collectorName);

    double totalWeightKg = 0.0;

    for (final it in _items) {
      final kg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;

      if (kg <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Weight must be greater than 0.")),
        );
        return;
      }

      totalWeightKg += kg;

      if (isSell && it.inventoryDocId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Select an inventory item for each SELL line."),
          ),
        );
        return;
      }
    }

    if (isSell) {
      if (totalWeightKg < _sellMinKg) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Minimum sell weight for ${_selectedSellBranch ?? 'this branch'} is ${_formatNumber(_sellMinKg)} kg.",
            ),
          ),
        );
        return;
      }

      if (totalWeightKg > _sellMaxKg) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Maximum sell weight for ${_selectedSellBranch ?? 'this branch'} is ${_formatNumber(_sellMaxKg)} kg.",
            ),
          ),
        );
        return;
      }
    }

    if (_hasInvalidSellWeight) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("One or more sell items exceed available stock."),
        ),
      );
      return;
    }

    final db = FirebaseFirestore.instance;
    final shopRef = db.collection('Users').doc(widget.shopID);
    final txCol = shopRef.collection('transaction');
    final invCol = shopRef.collection('inventory');

    final Map<String, _BuyInventoryGroup> buyGroups = {};
    final Map<String, String?> buyTargetIds = {};
    final Map<String, _SellInventoryGroup> sellGroups = {};

    if (!isSell) {
      for (final it in _items) {
        final cat = normalizeCategoryKey(it.categoryValue ?? "");
        final sub = (it.subCategoryValue ?? "").trim();
        final kg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;
        final key = "$cat|$sub";

        if (buyGroups.containsKey(key)) {
          buyGroups[key]!.totalKg += kg;
        } else {
          buyGroups[key] = _BuyInventoryGroup(
            category: cat,
            subCategory: sub,
            totalKg: kg,
          );
        }
      }

      for (final entry in buyGroups.entries) {
        final group = entry.value;
        buyTargetIds[entry.key] =
            await _findInventoryDocIdForBuy(group.category, group.subCategory);
      }
    } else {
      for (final it in _items) {
        final id = it.inventoryDocId!;
        final kg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;
        final cat = normalizeCategoryKey(it.categoryValue ?? "");
        final sub = (it.subCategoryValue ?? "").trim();
        final name = (it.sellPickedName ?? "").trim();

        if (sellGroups.containsKey(id)) {
          sellGroups[id]!.totalKg += kg;
        } else {
          sellGroups[id] = _SellInventoryGroup(
            inventoryDocId: id,
            itemName: name,
            category: cat,
            subCategory: sub,
            totalKg: kg,
          );
        }
      }
    }

    await db.runTransaction((trx) async {
      final txRef = txCol.doc();
      final itemsPayload = <Map<String, dynamic>>[];

      DocumentReference<Map<String, dynamic>>? sellReqRef;
      DocumentSnapshot<Map<String, dynamic>>? sellReqSnap;

      DocumentReference<Map<String, dynamic>>? dropoffReqRef;
      DocumentSnapshot<Map<String, dynamic>>? dropoffReqSnap;

      String? collectorIdFromSellRequest;
      String? collectorTransactionIdFromSellRequest;
      double collectorKgFromSellRequest = 0.0;

      DocumentReference<Map<String, dynamic>>? collectorInventoryRef;
      DocumentSnapshot<Map<String, dynamic>>? collectorInventorySnap;

      if (fromCollectorSellRequest && widget.sellRequestId != null) {
        sellReqRef = db
            .collection('Users')
            .doc(widget.shopID)
            .collection('sell_requests')
            .doc(widget.sellRequestId);

        sellReqSnap = await trx.get(sellReqRef);
      }

      if (fromHouseholdDropoff && widget.sellRequestId != null) {
        dropoffReqRef = db
            .collection('dropoff_requests')
            .doc(widget.sellRequestId);

        dropoffReqSnap = await trx.get(dropoffReqRef);
      }

      final Map<String, DocumentSnapshot<Map<String, dynamic>>> sellInventorySnaps =
          {};

      if (isSell) {
        for (final entry in sellGroups.entries) {
          final invRef = invCol.doc(entry.key);
          sellInventorySnaps[entry.key] = await trx.get(invRef);
        }
      }

      if (fromCollectorSellRequest &&
          widget.sellRequestId != null &&
          sellReqRef != null) {
        if (sellReqSnap == null || !sellReqSnap.exists) {
          throw Exception("Sell request not found.");
        }

        final sellReqData = sellReqSnap.data() ?? {};
        final status = (sellReqData['status'] ?? '').toString();

        if (status == 'completed' || status == 'processed') {
          throw Exception("This sell request was already processed.");
        }

        collectorIdFromSellRequest =
            (sellReqData['collectorId'] ?? '').toString().trim();

        collectorTransactionIdFromSellRequest =
            (sellReqData['collectorTransactionId'] ?? '').toString().trim();

        collectorKgFromSellRequest =
            ((sellReqData['kg'] as num?) ?? 0).toDouble();

        if (collectorIdFromSellRequest == null ||
            collectorIdFromSellRequest!.isEmpty) {
          throw Exception("Missing collectorId in sell request.");
        }

        if (collectorKgFromSellRequest <= 0) {
          throw Exception("Missing or invalid kg in sell request.");
        }

        collectorInventoryRef = db
            .collection('Users')
            .doc(collectorIdFromSellRequest)
            .collection('inventory')
            .doc('summary');

        collectorInventorySnap = await trx.get(collectorInventoryRef);
      }

      if (fromHouseholdDropoff &&
          widget.sellRequestId != null &&
          dropoffReqRef != null) {
        if (dropoffReqSnap == null || !dropoffReqSnap.exists) {
          throw Exception("Drop-off request not found.");
        }

        final dropoffData = dropoffReqSnap.data() ?? {};
        final status = (dropoffData['status'] ?? '').toString();

        if (status == 'completed') {
          throw Exception("This drop-off request was already completed.");
        }
      }

      if (isSell) {
        for (final entry in sellGroups.entries) {
          final group = entry.value;
          final invSnap = sellInventorySnaps[group.inventoryDocId];

          if (invSnap == null || !invSnap.exists) {
            throw Exception("Inventory item not found.");
          }

          final invData = invSnap.data() as Map<String, dynamic>;
          final currentKg = (invData['unitsKg'] as num?)?.toDouble() ?? 0.0;

          if (currentKg < group.totalKg) {
            final itemName = (invData['name'] ?? group.itemName).toString();
            throw Exception(
              "Not enough stock for $itemName. Available: ${_formatKg(currentKg)}",
            );
          }
        }
      }

      for (final it in _items) {
        final weightKg = double.tryParse(it.weightCtrl.text.trim()) ?? 0.0;
        final cat = normalizeCategoryKey(it.categoryValue ?? "");
        final sub = (it.subCategoryValue ?? "").trim();

        if (isSell) {
          final sellPerKg =
              it.sellPricePerKg ?? (kFixedSellPricePerKg[cat] ?? 0.0);
          final buyCostPerKg = kFixedBuyCostPerKg[cat] ?? 0.0;

          final sellTotal = weightKg * sellPerKg;
          final costTotal = weightKg * buyCostPerKg;
          final profit = sellTotal - costTotal;

          itemsPayload.add({
            'inventoryDocId': it.inventoryDocId,
            'itemName': (it.sellPickedName ?? "").trim(),
            'category': cat,
            'subCategory': sub,
            'weightKg': weightKg,
            'sellPricePerKg': sellPerKg,
            'sellTotal': sellTotal,
            'costPerKg': buyCostPerKg,
            'costTotal': costTotal,
            'profit': profit,
            'subtotal': sellTotal,
          });
        } else {
          final buyCostPerKg = kFixedBuyCostPerKg[cat] ?? 0.0;
          final costTotal = weightKg * buyCostPerKg;

          itemsPayload.add({
            'itemName': "$cat • $sub",
            'category': cat,
            'subCategory': sub,
            'weightKg': weightKg,
            'costPerKg': buyCostPerKg,
            'costTotal': costTotal,
            'subtotal': costTotal,
          });
        }
      }

      if (!isSell) {
        for (final entry in buyGroups.entries) {
          final key = entry.key;
          final group = entry.value;
          final targetId = buyTargetIds[key];

          if (targetId != null) {
            final existingRef = invCol.doc(targetId);
            trx.update(existingRef, {
              'unitsKg': FieldValue.increment(group.totalKg),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            final newInvRef = invCol.doc();
            trx.set(newInvRef, {
              'name': "${group.category} • ${group.subCategory}",
              'category': group.category,
              'subCategory': group.subCategory,
              'unitsKg': group.totalKg,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } else {
        for (final entry in sellGroups.entries) {
          final group = entry.value;
          final invSnap = sellInventorySnaps[group.inventoryDocId]!;
          final invData = invSnap.data() as Map<String, dynamic>;
          final currentKg = (invData['unitsKg'] as num?)?.toDouble() ?? 0.0;
          final newKg = currentKg - group.totalKg;

          trx.update(invCol.doc(group.inventoryDocId), {
            'unitsKg': newKg,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      if (fromCollectorSellRequest &&
          collectorIdFromSellRequest != null &&
          collectorIdFromSellRequest!.isNotEmpty &&
          collectorInventoryRef != null &&
          collectorInventorySnap != null) {
        final currentCollectorKg = collectorInventorySnap!.exists
            ? (((collectorInventorySnap!.data() as Map<String, dynamic>)['totalKg']
                        as num?) ??
                    0)
                .toDouble()
            : 0.0;

        if (currentCollectorKg < collectorKgFromSellRequest) {
          throw Exception(
            "Collector inventory is too low. Available: ${_formatKg(currentCollectorKg)}",
          );
        }

        trx.set(
          collectorInventoryRef!,
          {
            'totalKg': FieldValue.increment(-collectorKgFromSellRequest),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      final grossAmount = _totalAmount;
      final transportCost = isSell ? _transportCost : 0.0;
      final netAmount = isSell ? _netSellAmount : _totalAmount;

      final payload = <String, dynamic>{
        'transactionType': _txType,
        'customerName': partyName,
        'items': itemsPayload,
        'totalAmount': grossAmount,
        'totalWeightKg': totalWeightKg,
        'transactionDate': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (isSell) {
        payload['grossAmount'] = grossAmount;
        payload['transportCost'] = transportCost;
        payload['netAmount'] = netAmount;
      }

      if (!isSell) {
        payload['sourceType'] = sourceType;
        payload['sourceName'] = sourceName;

        if (!isWalkInBuy && _sourceUserId != null) {
          payload['sourceUserId'] = _sourceUserId;
        }
      }

      if (fromCollectorSellRequest && widget.sellRequestId != null) {
        payload['sellRequestId'] = widget.sellRequestId;
        payload['receiptOrigin'] = 'collector_sell_request';
      }

      if (fromHouseholdDropoff && widget.sellRequestId != null) {
        payload['dropoffRequestId'] = widget.sellRequestId;
        payload['receiptOrigin'] = 'household_dropoff';
      }

      trx.set(txRef, payload);

      if (fromCollectorSellRequest &&
          widget.sellRequestId != null &&
          sellReqRef != null) {
        trx.set(
          sellReqRef,
          {
            'status': 'completed',
            'seen': true,
            'receiptSaved': true,
            'receiptTransactionId': txRef.id,
            'processedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      if (fromCollectorSellRequest &&
          collectorIdFromSellRequest != null &&
          collectorIdFromSellRequest!.isNotEmpty &&
          collectorTransactionIdFromSellRequest != null &&
          collectorTransactionIdFromSellRequest!.isNotEmpty) {
        final collectorTxnRef = db
            .collection('Users')
            .doc(collectorIdFromSellRequest)
            .collection('transactions')
            .doc(collectorTransactionIdFromSellRequest);

        trx.set(
          collectorTxnRef,
          {
            'status': 'completed',
            'receiptTransactionId': txRef.id,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      if (fromHouseholdDropoff &&
          widget.sellRequestId != null &&
          dropoffReqRef != null) {
        trx.set(
          dropoffReqRef,
          {
            'status': 'completed',
            'readByJunkshop': true,
            'receiptSaved': true,
            'receiptTransactionId': txRef.id,
            'processedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });

    if (!mounted) return;
    Navigator.pop(context);
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Save failed: $e")),
    );
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}

  @override
  Widget build(BuildContext context) {
    final isSell = _txType == "sell";

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(isSell ? "Selling Transaction" : "Buying Transaction"),
      ),
      body: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _glassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label(isSell ? "Client" : "Walk-in"),
                  const SizedBox(height: 8),
                  if (isSell) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _sellBranches.contains(_selectedSellBranch)
                          ? _selectedSellBranch
                          : _sellBranches.first,
                      items: _sellBranches
                          .map(
                            (b) => DropdownMenuItem(
                              value: b,
                              child: Text(b, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _selectedSellBranch = v);
                      },
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Colors.white),
                      decoration: _dropdownDecoration(""),
                    ),
                  ] else if (_openedFromCollectorSellRequest ||
                      _isPrefilledCollectorBuy) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Collector",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _sourceNameCtrl.text.isEmpty
                                ? "Unknown Collector"
                                : _sourceNameCtrl.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_isPrefilledHouseholdWalkIn) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Walk-in",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _walkInNameCtrl.text.isEmpty
                                ? "Unknown Walk-in"
                                : _walkInNameCtrl.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _walkInNameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration("Enter walk-in name"),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Items",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add, color: Colors.green),
                  label: Text(
                    isSell ? "Add Sell Item" : "Add Buy Item",
                    style: const TextStyle(color: Colors.green),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;

              final pickedLabel = item.inventoryDocId == null
                  ? "Select Item"
                  : "${item.sellPickedName ?? ''} • ${item.categoryValue ?? ''}";

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _glassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          "Item ${index + 1}",
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label(isSell ? "Item" : "Category"),
                                const SizedBox(height: 6),
                                if (isSell) ...[
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _pickInventoryItem(item),
                                      icon: const Icon(
                                        Icons.inventory_2,
                                        color: Colors.white,
                                      ),
                                      label: Text(
                                        pickedLabel,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                          color: Colors.white.withOpacity(0.2),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        backgroundColor:
                                            Colors.black.withOpacity(0.2),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                          horizontal: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (item.inventoryDocId != null) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "Available: ${_formatKg(item.availableKg)}",
                                          style: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          "Remaining: ${_formatKg(_remainingSellKg(item))}",
                                          style: TextStyle(
                                            color: _isSellItemOverStock(item)
                                                ? Colors.redAccent
                                                : const Color(0xFF1FA9A7),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_isSellItemOverStock(item)) ...[
                                      const SizedBox(height: 6),
                                      const Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          "Entered weight exceeds available stock",
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                                if (!isSell) ...[
                                  DropdownButtonFormField<String>(
                                    initialValue:
                                        item.categoryValue ?? kMajorCategories.first,
                                    items: kMajorCategories
                                        .map(
                                          (c) => DropdownMenuItem(
                                            value: c,
                                            child: Text(
                                              c,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(() {
                                      item.categoryValue = v;
                                      _recalcBuyItem(item);
                                    }),
                                    dropdownColor: const Color(0xFF0F172A),
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _dropdownDecoration(""),
                                  ),
                                  const SizedBox(height: 10),
                                  _label("Sub-category"),
                                  const SizedBox(height: 6),
                                  DropdownButtonFormField<String>(
                                    initialValue: item.subCategoryValue ??
                                        kBuySubCategories.first,
                                    items: kBuySubCategories
                                        .map(
                                          (c) => DropdownMenuItem(
                                            value: c,
                                            child: Text(
                                              c,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => setState(() {
                                      item.subCategoryValue = v;
                                      _recalcBuyItem(item);
                                    }),
                                    dropdownColor: const Color(0xFF0F172A),
                                    style: const TextStyle(color: Colors.white),
                                    decoration: _dropdownDecoration(""),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _isLockedSellRequestItem(index)
                                ? null
                                : () => _removeItem(index),
                            icon: Icon(
                              Icons.close,
                              color: _isLockedSellRequestItem(index)
                                  ? Colors.white24
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _textField(
                                  controller: item.weightCtrl,
                                  label: "Weight (kg)",
                                  hint: "0.0",
                                  readOnly: _isLockedSellRequestItem(index),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  onChanged: (_) => setState(() {
                                    if (isSell) {
                                      _recalcSellItem(item, keepManualPrice: true);
                                    } else {
                                      _recalcBuyItem(item);
                                    }
                                  }),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _textField(
                                  controller: item.subtotalCtrl,
                                  label: isSell ? "Subtotal (₱)" : "Cost (₱)",
                                  hint: "0.00",
                                  readOnly: true,
                                ),
                              ),
                            ],
                          ),
                          if (isSell) ...[
                            const SizedBox(height: 10),
                            _label("Sell Price Per Kg"),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        final current = item.sellPricePerKg ??
                                            (kFixedSellPricePerKg[
                                                    normalizeCategoryKey(
                                                      item.categoryValue ?? "",
                                                    )
                                                  ] ??
                                                0.0);

                                        final next = current - 1;
                                        item.sellPricePerKg = next < 0 ? 0 : next;
                                        _recalcSellItem(
                                          item,
                                          keepManualPrice: true,
                                        );
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: Colors.redAccent,
                                      size: 30,
                                    ),
                                  ),
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        "${_formatMoney(item.sellPricePerKg ?? 0)} / kg",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        final current = item.sellPricePerKg ??
                                            (kFixedSellPricePerKg[
                                                    normalizeCategoryKey(
                                                      item.categoryValue ?? "",
                                                    )
                                                  ] ??
                                                0.0);

                                        item.sellPricePerKg = current + 1;
                                        _recalcSellItem(
                                          item,
                                          keepManualPrice: true,
                                        );
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.keyboard_arrow_up_rounded,
                                      color: Colors.greenAccent,
                                      size: 30,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
_glassCard(
  child: Column(
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            isSell ? "Gross Amount" : "Total Cost",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            _formatMoney(_totalAmount),
            style: TextStyle(
              color: primaryColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "Total Weight",
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            _formatKg(_totalWeightKg),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),

      if (isSell) ...[
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _selectedSellBranch == "ECO fortunes Cabuyao City"
                ? "Allowed weight: 1,000–4,000 kg • Shipping fee: ₱4,000"
                : "Allowed weight: 4,000–18,000 kg • Shipping fee depends on total weight",
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Transport Deduction",
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              "- ${_formatMoney(_transportCost)}",
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (_saving || _hasInvalidSellWeight) ? null : _saveReceipt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  _saving ? "SAVING..." : "SAVE RECEIPT",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                "Transaction Date is saved automatically",
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool readOnly = false,
    TextInputType keyboardType = TextInputType.text,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B)),
      filled: true,
      fillColor: Colors.black.withOpacity(0.2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  InputDecoration _dropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
      filled: true,
      fillColor: Colors.black.withOpacity(0.2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }
}

class _ReceiptItem {
  final TextEditingController weightCtrl = TextEditingController();
  final TextEditingController subtotalCtrl = TextEditingController();

  String? inventoryDocId;
  String? sellPickedName;

  String? categoryValue;
  String? subCategoryValue;

  double? buyCostPerKg;
  double? sellPricePerKg;

  double availableKg = 0.0;

  double get subtotal {
    final raw = subtotalCtrl.text.trim().replaceAll(',', '');
    return double.tryParse(raw) ?? 0.0;
  }

  void dispose() {
    weightCtrl.dispose();
    subtotalCtrl.dispose();
  }
}

class _BuyInventoryGroup {
  final String category;
  final String subCategory;
  double totalKg;

  _BuyInventoryGroup({
    required this.category,
    required this.subCategory,
    required this.totalKg,
  });
}

class _SellInventoryGroup {
  final String inventoryDocId;
  final String itemName;
  final String category;
  final String subCategory;
  double totalKg;

  _SellInventoryGroup({
    required this.inventoryDocId,
    required this.itemName,
    required this.category,
    required this.subCategory,
    required this.totalKg,
  });
}

class _InventoryPickerSheet extends StatefulWidget {
  final String shopID;
  final Set<String> excludedInventoryIds;

  const _InventoryPickerSheet({
    required this.shopID,
    required this.excludedInventoryIds,
  });

  @override
  State<_InventoryPickerSheet> createState() => _InventoryPickerSheetState();
}

class _InventoryPickerSheetState extends State<_InventoryPickerSheet> {
  String q = "";

  final NumberFormat _num2 = NumberFormat('#,##0.##');
  String _formatKg(num value) => '${_num2.format(value)} kg';

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Search inventory...",
                hintStyle: const TextStyle(color: Color(0xFF64748B)),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Users')
                  .doc(widget.shopID)
                  .collection('inventory')
                  .orderBy('updatedAt', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  return Center(
                    child: Text(
                      "Error: ${snap.error}",
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  );
                }

                final docs = snap.data?.docs ?? [];

                final filtered = docs.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  final unitsKg = (m['unitsKg'] as num?)?.toDouble() ?? 0.0;

                  if (unitsKg <= 0) return false;
                  if (widget.excludedInventoryIds.contains(d.id)) return false;

                  if (q.isEmpty) return true;

                  final hay = [
                    (m['name'] ?? '').toString(),
                    (m['category'] ?? '').toString(),
                    (m['subCategory'] ?? '').toString(),
                  ].join(' ').toLowerCase();

                  return hay.contains(q);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text(
                      "No matching items",
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = filtered[i];
                    final m = d.data() as Map<String, dynamic>;

                    final name =
                        (m['Name'] ?? m['displayName'] ?? m['name'] ?? '')
                            .toString();
                    final category = (m['category'] ?? '').toString();
                    final subCategory = (m['subCategory'] ?? '').toString();
                    final unitsKg = (m['unitsKg'] as num?)?.toDouble() ?? 0.0;

                    return ListTile(
                      tileColor: Colors.white.withOpacity(0.06),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        "$category • $subCategory • ${_formatKg(unitsKg)}",
                        style: const TextStyle(color: Colors.grey),
                      ),
                      onTap: () {
                        Navigator.pop(context, {
                          'id': d.id,
                          'name': name,
                          'category': category,
                          'subCategory': subCategory,
                          'unitsKg': unitsKg,
                        });
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
}
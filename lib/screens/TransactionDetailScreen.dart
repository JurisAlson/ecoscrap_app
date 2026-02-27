// ===================== transactiondetailscreen.dart (UPDATED: Walk-in display) =====================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TransactionDetailScreen extends StatefulWidget {
  final String shopID;
  final Map<String, dynamic> transactionData;

  const TransactionDetailScreen({
    super.key,
    required this.shopID,
    required this.transactionData,
  });

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  static const Color bgColor = Color(0xFF0F172A);
  static const Color primaryColor = Color(0xFF1FA9A7);

  String _formatDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return "$y-$m-$day  $hh:$mm";
  }

  double _sumKg(List items) {
    double total = 0.0;
    for (final it in items) {
      final m = (it as Map<String, dynamic>);
      total += (m['weightKg'] as num?)?.toDouble() ?? 0.0;
    }
    return total;
  }

  String _titleCase(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1).toLowerCase();
  }

  bool _isWalkInType(String raw) {
    final v = raw.trim().toLowerCase();
    return v == "walkin" || v == "walk-in" || v == "walk in" || v == "walk_in";
  }

  @override
  Widget build(BuildContext context) {
    final txType =
        (widget.transactionData['transactionType'] ?? '').toString().toLowerCase();

    // ✅ firestore uses "sell" / "buy"
    final isSale = txType == 'sell';

    final customerName = (widget.transactionData['customerNameDisplay'] ??
            widget.transactionData['customerName'] ??
            '')
        .toString()
        .trim();

    final sourceTypeRaw =
        (widget.transactionData['sourceType'] ?? '').toString().trim(); // resident|collector|walkin
    final sourceNameRaw =
        (widget.transactionData['sourceName'] ?? '').toString().trim();

    String partyLine = customerName;

    if (!isSale) {
      // BUY
      if (_isWalkInType(sourceTypeRaw) ||
          (sourceTypeRaw.isEmpty && sourceNameRaw.isEmpty && customerName.isEmpty)) {
        partyLine = sourceNameRaw.isEmpty ? "Walk-in" : "Walk-in • $sourceNameRaw";
      } else {
        final prettyType = _titleCase(sourceTypeRaw);
        if (prettyType.isNotEmpty && sourceNameRaw.isNotEmpty) {
          partyLine = "$prettyType • $sourceNameRaw";
        } else if (sourceNameRaw.isNotEmpty) {
          partyLine = sourceNameRaw;
        } else if (customerName.isNotEmpty) {
          partyLine = customerName; // fallback (older data)
        } else {
          partyLine = "Walk-in";
        }
      }
    } else {
      // SELL
      if (partyLine.isEmpty) partyLine = "Walk-in customer";
    }

    final totalAmount =
        (widget.transactionData['totalAmount'] as num?)?.toDouble() ?? 0.0;

    final ts = widget.transactionData['transactionDate'] as Timestamp?;
    final date = ts?.toDate();

    final items = (widget.transactionData['items'] as List<dynamic>?) ?? [];

    final txId = (widget.transactionData['receiptId'] ??
            widget.transactionData['transactionId'] ??
            '')
        .toString();

    final totalKg = _sumKg(items);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(isSale ? "Sell Receipt" : "Buy Receipt"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection("Users")
              .doc(widget.shopID)
              .get(),
          builder: (context, snap) {
            final shopName = (() {
              if (snap.data?.exists != true) return "Junkshop";
              final data = snap.data!.data() as Map<String, dynamic>;
              final name = (data['shopName'] ?? '').toString().trim();
              return name.isEmpty ? "Junkshop" : name;
            })();

            return Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shopName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 8),

                  if (date != null)
                    Text(
                      _formatDate(date),
                      style: const TextStyle(color: Colors.grey),
                    ),

                  const SizedBox(height: 8),

                  Text(
                    partyLine,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 12),
                  Divider(color: Colors.white.withOpacity(0.08)),

                  ...items.map((raw) {
                    final item = raw as Map<String, dynamic>;
                    final itemName = (item['itemName'] ?? '').toString();
                    final weight = (item['weightKg'] as num?)?.toDouble() ?? 0.0;

                    final subtotal =
                        (item['subtotal'] as num?)?.toDouble() ??
                        (item['sellTotal'] as num?)?.toDouble() ??
                        (item['costTotal'] as num?)?.toDouble() ??
                        0.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  itemName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${weight.toStringAsFixed(2)} kg",
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "₱${subtotal.toStringAsFixed(2)}",
                            style: TextStyle(
                              color: isSale ? Colors.greenAccent : Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  Divider(color: Colors.white.withOpacity(0.08)),

                  const SizedBox(height: 8),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isSale ? "TOTAL SOLD" : "TOTAL KG",
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "${totalKg.toStringAsFixed(2)} kg",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "TOTAL",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "₱${totalAmount.toStringAsFixed(2)}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    "Transaction ID",
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            txId,
                            style: const TextStyle(color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, color: Colors.white70),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: txId));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Transaction ID copied")),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),
                  const Text(
                    "Tap to copy.",
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
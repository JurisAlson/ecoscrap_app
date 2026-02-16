import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TransactionDetailScreen extends StatelessWidget {
  final Map<String, dynamic> transactionData;

  const TransactionDetailScreen({
    super.key,
    required this.transactionData,
  });

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

  @override
  Widget build(BuildContext context) {
    final isSale =
        (transactionData['transactionType'] ?? '').toString() == 'sale';

    // ✅ Proper name handling (works for both SALE and BUY)
    final partyName = (
      transactionData['customerNameDisplay'] ??
      transactionData['customerName'] ??
      ''
    ).toString().trim();

    final total =
        (transactionData['totalAmount'] as num?)?.toDouble() ?? 0.0;

    final ts = transactionData['transactionDate'] as Timestamp?;
    final date = ts?.toDate();

    final items =
        (transactionData['items'] as List<dynamic>?) ?? [];

    // ✅ Total KG (fallback supported)
    double totalKg =
        (transactionData['totalWeightKg'] as num?)?.toDouble() ?? -1;

    if (totalKg < 0) {
      totalKg = 0.0;
      for (final it in items) {
        final m = it as Map<String, dynamic>;
        totalKg += (m['weightKg'] as num?)?.toDouble() ?? 0.0;
      }
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(isSale ? "Sale Receipt" : "Buy Receipt"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ Always show name
                  Text(
                    partyName.isEmpty
                        ? (isSale
                            ? "Walk-in customer"
                            : "Unknown supplier/source")
                        : partyName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  if (date != null)
                    Text(
                      _formatDate(date),
                      style: const TextStyle(color: Colors.grey),
                    ),

                  const SizedBox(height: 10),

                  Text(
                    "${totalKg.toStringAsFixed(2)} kg ${isSale ? "sold" : "bought"}",
                    style: TextStyle(
                      color:
                          isSale ? Colors.greenAccent : Colors.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Items List
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item =
                      items[index] as Map<String, dynamic>;

                  final name =
                      (item['itemName'] ?? '').toString();

                  final weight =
                      (item['weightKg'] as num?)?.toDouble() ?? 0.0;

                  final subtotal =
                      (item['subtotal'] as num?)?.toDouble() ?? 0.0;

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                    color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${weight.toStringAsFixed(2)} kg",
                                style: const TextStyle(
                                    color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          "₱${subtotal.toStringAsFixed(2)}",
                          style: TextStyle(
                            color: isSale
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Total
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "TOTAL",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "₱${total.toStringAsFixed(2)}",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
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
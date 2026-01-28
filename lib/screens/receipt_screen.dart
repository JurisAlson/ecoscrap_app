import 'package:flutter/material.dart';
import 'dart:ui';

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final Color primaryColor = const Color(0xFF1FA9A7);
  final Color bgColor = const Color(0xFF0F172A);

  final TextEditingController _customerCtrl = TextEditingController();

  final List<_ReceiptItem> _items = [];

  double get _totalAmount {
    double total = 0;
    for (final i in _items) {
      total += i.subtotal;
    }
    return total;
  }

  void _addItem() {
    setState(() {
      _items.add(_ReceiptItem());
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: const Text("New Receipt"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CUSTOMER CARD
            _glassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label("Customer Name"),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customerCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration("Enter customer name"),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ITEMS
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
                  label: const Text("Add Item",
                      style: TextStyle(color: Colors.green)),
                ),
              ],
            ),

            const SizedBox(height: 8),

            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _glassCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _textField(
                              controller: item.itemNameCtrl,
                              label: "Item Name",
                              hint: "e.g. PP White",
                            ),
                          ),
                          IconButton(
                            onPressed: () => _removeItem(index),
                            icon: const Icon(Icons.close, color: Colors.red),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _textField(
                              controller: item.weightCtrl,
                              label: "Weight (kg)",
                              hint: "0.0",
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _textField(
                              controller: item.subtotalCtrl,
                              label: "Subtotal (₱)",
                              hint: "0.00",
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 16),

            // TOTAL
            _glassCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Total Amount",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "₱${_totalAmount.toStringAsFixed(2)}",
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // SAVE BUTTON
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  // 🔜 Firestore save logic goes here
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text(
                  "SAVE RECEIPT",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            Center(
              child: Text(
                "Transaction Date is saved automatically",
                style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== UI HELPERS =====

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: Colors.grey.shade400,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
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
      hintStyle: TextStyle(color: Colors.grey.shade500),
      filled: true,
      fillColor: Colors.black.withOpacity(0.2),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }
}

// ===== MODEL FOR ITEM FORM =====
class _ReceiptItem {
  final TextEditingController itemNameCtrl = TextEditingController();
  final TextEditingController weightCtrl = TextEditingController();
  final TextEditingController subtotalCtrl = TextEditingController();

  double get subtotal =>
      double.tryParse(subtotalCtrl.text.trim()) ?? 0;

  void dispose() {
    itemNameCtrl.dispose();
    weightCtrl.dispose();
    subtotalCtrl.dispose();
  }
}

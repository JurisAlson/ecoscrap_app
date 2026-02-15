import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class InventoryScreen extends StatefulWidget {
  final String shopID;

  const InventoryScreen({super.key, required this.shopID});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _query = "";

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Junkshop')
          .doc(widget.shopID)
          .collection('inventory')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F172A),
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        final items = docs.where((doc) {
          if (_query.isEmpty) return true;
          final data = doc.data() as Map<String, dynamic>;
          final hay = [
            data['name'] ?? '',
            data['category'] ?? '',
            data['subCategory'] ?? '',
            data['notes'] ?? '',
            (data['unitsKg'] ?? '').toString(),
          ].join(' ').toLowerCase();
          return hay.contains(_query.toLowerCase());
        }).toList();

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Search inventory...",
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: items.isEmpty
                      ? _emptyState()
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final doc = items[i];
                            final data = doc.data() as Map<String, dynamic>;

                            final name = data['name'] ?? 'Unnamed item';
                            final category = data['category'] ?? 'PP WHITE';
                            final subCategory = data['subCategory'] ?? '';
                            final unitsKg = (data['unitsKg'] as num?)?.toDouble() ?? 0.0;

                            return ListTile(
                              tileColor: Colors.white.withOpacity(0.06),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                "$category • $subCategory • ${unitsKg.toStringAsFixed(2)} kg",
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                              // ✅ view-only: no trailing edit/delete
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text("No inventory items yet", style: TextStyle(color: Colors.grey)),
          SizedBox(height: 6),
          Text(
            "Add items through Transactions (Buy/Sell).",
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

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
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('Junkshop')
          .doc(widget.shopID)
          .collection('inventory')
          .orderBy('updatedAt', descending: true)
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
          final data = doc.data();
          final hay = [
            (data['name'] ?? '').toString(),
            (data['category'] ?? '').toString(),
            (data['subCategory'] ?? '').toString(),
            (data['notes'] ?? '').toString(),
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
                      ? const Center(
                          child: Text("No inventory items yet",
                              style: TextStyle(color: Colors.grey)),
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final data = items[i].data();

                            final name = (data['name'] ?? 'Unnamed item').toString();
                            final category = (data['category'] ?? '').toString();
                            final subCategory = (data['subCategory'] ?? '').toString();
                            final unitsKg = (data['unitsKg'] as num?)?.toDouble() ?? 0.0;

                            return ListTile(
                              tileColor: Colors.white.withOpacity(0.06),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                "$category • $subCategory • ${unitsKg.toStringAsFixed(2)} kg",
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
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
}
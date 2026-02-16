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
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSearchField(),
            const SizedBox(height: 12),
            Expanded(child: _buildInventoryList()),
          ],
        ),
      ),
    );
  }

  /// 🔎 SEARCH FIELD (Stable — not inside StreamBuilder)
  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      cursorColor: Colors.greenAccent,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "Search inventory...",
        hintStyle: TextStyle(color: Colors.grey.shade500),
        prefixIcon: const Icon(Icons.search, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.greenAccent),
        ),
      ),
      onChanged: (v) => setState(() => _query = v.trim()),
    );
  }

  /// 📦 INVENTORY LIST (Only this rebuilds)
  Widget _buildInventoryList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Junkshop')
          .doc(widget.shopID)
          .collection('inventory')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              "Error: ${snapshot.error}",
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        final items = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final unitsKg = (data['unitsKg'] as num?)?.toDouble() ?? 0.0;

          // ✅ hide zero/negative items
          if (unitsKg <= 0) return false;

          if (_query.isEmpty) return true;

          final hay = [
            data['name'] ?? '',
            data['category'] ?? '',
            data['subCategory'] ?? '',
            data['notes'] ?? '',
            unitsKg.toString(),
          ].join(' ').toLowerCase();

          return hay.contains(_query.toLowerCase());
        }).toList();

        if (items.isEmpty) {
          return _emptyStateViewOnly();
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final doc = items[i];
            final data = doc.data() as Map<String, dynamic>;

            final name = data['name'] ?? 'Unnamed item';
            final category = data['category'] ?? 'PP WHITE';
            final subCategory = data['subCategory'] ?? '';
            final unitsKg =
                (data['unitsKg'] as num?)?.toDouble() ?? 0.0;

            return ListTile(
              tileColor: Colors.white.withOpacity(0.06),
              title: Text(
                name,
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                "$category • $subCategory • ${unitsKg.toStringAsFixed(2)} kg",
                style: TextStyle(color: Colors.grey.shade400),
              ),
            );
          },
        );
      },
    );
  }

  /// 📭 EMPTY STATE (View Only)
  Widget _emptyStateViewOnly() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.inventory_2, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text(
            "No inventory items yet",
            style: TextStyle(color: Colors.grey),
          ),
          SizedBox(height: 8),
          Text(
            "View only mode (Junkshop)",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
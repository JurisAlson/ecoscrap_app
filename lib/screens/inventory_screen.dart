import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:ui';


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
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(color: Colors.transparent),
      ),
    ),
  );
}

@override
Widget build(BuildContext context) {
  const Color primaryColor = Color(0xFF1FA9A7);
  const Color bgColor = Color(0xFF0F172A);

  return Scaffold(
    backgroundColor: bgColor,
    body: Stack(
      children: [

        // ✅ SAME glow as Transaction
        _blurCircle(primaryColor.withOpacity(0.15), 300, top: -100, right: -100),
        _blurCircle(Colors.green.withOpacity(0.1), 350, bottom: 100, left: -100),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              children: [
                const SizedBox(height: 18),

                _buildSearchField(),
                const SizedBox(height: 12),

                Expanded(child: _buildInventoryList()),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}


  /// 🔎 SEARCH FIELD (Stable — not inside StreamBuilder)
Widget _buildSearchField() {
  return TextField(
    controller: _searchController,
    cursorColor: Colors.white,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: "Search inventory...",
      hintStyle: const TextStyle(
        color: Color(0xFF64748B),
      ),
      prefixIcon: const Icon(
        Icons.search,
        color: Colors.white70,
      ),
      filled: true,
      fillColor: Colors.black.withOpacity(0.25),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 14,
      ),
    ),
    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
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

            return Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05), // ✅ same tone as Dashboard/Transaction
              borderRadius: BorderRadius.circular(16), // ✅ rounded
              border: Border.all(color: Colors.white.withOpacity(0.06)), // ✅ soft border
            ),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16), // ✅ prevents hard edge ripple
              ),
              title: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  subCategory.toString().trim().isEmpty
                      ? "$category • ${unitsKg.toStringAsFixed(2)} kg"
                      : "$category • $subCategory • ${unitsKg.toStringAsFixed(2)} kg",
                  style: const TextStyle(color: Colors.white54),
                ),
              ),
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
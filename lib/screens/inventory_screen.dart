import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class InventoryScreen extends StatefulWidget {
  final String shopID;

  const InventoryScreen({super.key, required this.shopID});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _query = "";
  String _selectedCategory = "All";

  final TextEditingController _searchController = TextEditingController();

  final List<String> _categories = const [
    "All",
    "PP WHITE",
    "HDPE",
    "PP COLOR",
    "PET",
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _timeAgo(Timestamp timestamp) {
    final date = timestamp.toDate();
    final diff = DateTime.now().difference(date);

    if (diff.inSeconds < 60) return "just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes} min ago";
    if (diff.inHours < 24) return "${diff.inHours} hr ago";
    if (diff.inDays < 7) return "${diff.inDays} days ago";

    return DateFormat('MMM d').format(date);
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
      child: IgnorePointer(
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
          _blurCircle(primaryColor.withOpacity(0.15), 300,
              top: -100, right: -100),
          _blurCircle(Colors.green.withOpacity(0.10), 350,
              bottom: 80, left: -120),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  _buildSearchField(),
                  const SizedBox(height: 12),
                  _buildCategoryFilters(),
                  const SizedBox(height: 16),
                  Expanded(child: _buildInventoryList()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      cursorColor: Colors.white,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "Search inventory...",
        hintStyle: const TextStyle(color: Color(0xFF64748B)),
        prefixIcon: const Icon(Icons.search, color: Colors.white70),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = "");
                },
              )
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
    );
  }

  Widget _buildCategoryFilters() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final category = _categories[i];
          final selected = category == _selectedCategory;

          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = category),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1FA9A7)
                    : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                category,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInventoryList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Users')
          .doc(widget.shopID)
          .collection('inventory')
          .orderBy('updatedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              "Error: ${snapshot.error}",
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;

        final items = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;

          final unitsKg = (data['unitsKg'] as num?)?.toDouble() ?? 0.0;
          if (unitsKg <= 0) return false;

          final category = (data['category'] ?? '').toString();

          if (_selectedCategory != "All" &&
              category.toUpperCase() != _selectedCategory.toUpperCase()) {
            return false;
          }

          if (_query.isEmpty) return true;

          final hay = [
            data['name'] ?? '',
            data['category'] ?? '',
            data['subCategory'] ?? '',
            data['notes'] ?? '',
          ].join(' ').toLowerCase();

          return hay.contains(_query);
        }).toList();

        if (items.isEmpty) return _emptyState();

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data = items[i].data() as Map<String, dynamic>;

            final name = (data['name'] ?? "Unnamed").toString();
            final category = (data['category'] ?? "PP WHITE").toString();
            final subCategory = (data['subCategory'] ?? "").toString();
            final unitsKg = (data['unitsKg'] as num?)?.toDouble() ?? 0.0;
            final Timestamp? updatedAt =
                data['updatedAt'] as Timestamp? ?? data['createdAt'] as Timestamp?;

            return _inventoryCard(
              name,
              category,
              subCategory,
              unitsKg,
              updatedAt,
            );
          },
        );
      },
    );
  }

  Widget _inventoryCard(
    String name,
    String category,
    String subCategory,
    double unitsKg,
    Timestamp? updatedAt,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF1FA9A7).withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.inventory_2, color: Color(0xFF1FA9A7)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subCategory.trim().isEmpty
                      ? category
                      : "$category • $subCategory",
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                if (updatedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      "Updated ${_timeAgo(updatedAt)}",
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                "Weight",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                "${unitsKg.toStringAsFixed(2)} kg",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2, size: 60, color: Colors.grey),
          SizedBox(height: 10),
          Text(
            "No inventory items yet",
            style: TextStyle(color: Colors.grey),
          ),
          SizedBox(height: 4),
          Text(
            "View only mode (Junkshop)",
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
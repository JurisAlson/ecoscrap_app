import 'package:flutter/material.dart';
import 'inventory_form_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _query = "";

  final List<Map<String, dynamic>> _items = [
    {
      'id': '1',
      'name': 'PP Color Class A',
      'category': 'PP Color',
      'subCategory': 'Class A',
      'quantityKg': 12.5,
      'notes': 'Clean and sorted',
    },
    {
      'id': '2',
      'name': 'HD Bottles',
      'category': 'HD',
      'subCategory': '',
      'quantityKg': 6.0,
      'notes': '',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _items.where((item) {
      if (_query.isEmpty) return true;
      final hay = [
        item['name'],
        item['category'],
        item['subCategory'],
        item['notes'],
      ].join(' ').toLowerCase();
      return hay.contains(_query);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final created = await Navigator.push<Map<String, dynamic>>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const InventoryFormScreen(mode: FormMode.create),
            ),
          );

          if (created != null) {
            setState(() {
              _items.insert(0, {
                ...created,
                'id': DateTime.now()
                    .microsecondsSinceEpoch
                    .toString(),
              });
            });
          }
        },
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Search (e.g., PP Color, HD, cups...)",
                hintStyle: TextStyle(color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        "No items found",
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final item = filtered[i];
                        final name = item['name'];
                        final category = item['category'];
                        final sub = item['subCategory'];
                        final qty =
                            (item['quantityKg'] ?? 0).toDouble();

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "$category${sub.isNotEmpty ? " • $sub" : ""}",
                                      style: TextStyle(
                                          color:
                                              Colors.grey.shade400),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "${qty.toStringAsFixed(2)} kg",
                                      style: TextStyle(
                                          color:
                                              Colors.grey.shade300),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    color: Colors.white),
                                onPressed: () async {
                                  final updated =
                                      await Navigator.push<
                                          Map<String, dynamic>>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          InventoryFormScreen(
                                        mode: FormMode.edit,
                                        initial: item,
                                      ),
                                    ),
                                  );

                                  if (updated != null) {
                                    setState(() {
                                      final idx = _items.indexWhere(
                                          (x) =>
                                              x['id'] ==
                                              item['id']);
                                      if (idx != -1) {
                                        _items[idx] = {
                                          ..._items[idx],
                                          ...updated
                                        };
                                      }
                                    });
                                  }
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.delete,
                                    color: Colors.red.shade300),
                                onPressed: () =>
                                    _confirmDelete(item['id']),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete item?"),
        content:
            const Text("This action cannot be undone."),
        actions: [
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text("Delete")),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        _items.removeWhere((x) => x['id'] == id);
      });
    }
  }
}

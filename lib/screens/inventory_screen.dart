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
          floatingActionButton: FloatingActionButton(
            backgroundColor: Colors.greenAccent,
            child: const Icon(Icons.add, color: Colors.black),
            onPressed: _addItem,
          ),
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
                            final notes = data['notes'] ?? '';
                            final unitsKg = (data['unitsKg'] as num?)?.toDouble() ?? 0.0;

                            return ListTile(
                              tileColor: Colors.white.withOpacity(0.06),
                              title: Text(name, style: const TextStyle(color: Colors.white)),
                              subtitle: Text(
                                "$category • $subCategory • ${unitsKg.toStringAsFixed(2)} kg",
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.white),
                                    onPressed: () async {
                                      final edited = await showDialog<Map<String, dynamic>>(
                                        context: context,
                                        builder: (_) => _EditInventoryDialog(
                                          initialName: name,
                                          initialCategory: category,
                                          initialSubCategory: subCategory,
                                          initialNotes: notes,
                                          initialUnitsKg: unitsKg,
                                        ),
                                      );

                                      if (edited == null) return;

                                      await FirebaseFirestore.instance
                                          .collection('Junkshop')
                                          .doc(widget.shopID)
                                          .collection('inventory')
                                          .doc(doc.id)
                                          .update({
                                        'name': edited['name'] ?? '',
                                        'category': edited['category'] ?? 'PP WHITE',
                                        'subCategory': edited['subCategory'] ?? '',
                                        'notes': edited['notes'] ?? '',
                                        'unitsKg': (edited['unitsKg'] as num?)?.toDouble() ?? 0.0,
                                        'updatedAt': FieldValue.serverTimestamp(),
                                      });
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red.shade300),
                                    onPressed: () => _confirmDelete(doc.id),
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
      },
    );
  }

  /// ➕ CREATE
  Future<void> _addItem() async {
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _EditInventoryDialog(
        initialName: '',
        initialCategory: 'PP WHITE',
        initialSubCategory: '',
        initialNotes: '',
        initialUnitsKg: 0.0,
      ),
    );

    if (created == null) return;

    await FirebaseFirestore.instance
        .collection('Junkshop')
        .doc(widget.shopID)
        .collection('inventory')
        .add({
      'name': created['name'] ?? '',
      'category': created['category'] ?? 'PP WHITE',
      'subCategory': created['subCategory'] ?? '',
      'notes': created['notes'] ?? '',
      'unitsKg': (created['unitsKg'] as num?)?.toDouble() ?? 0.0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 🗑 DELETE CONFIRM
  Future<void> _confirmDelete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete item?"),
        content: const Text("This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Delete")),
        ],
      ),
    );

    if (ok == true) {
      await FirebaseFirestore.instance
          .collection('Junkshop')
          .doc(widget.shopID)
          .collection('inventory')
          .doc(id)
          .delete();
    }
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inventory_2, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text("No inventory items yet", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add),
            label: const Text("Add Item"),
          ),
        ],
      ),
    );
  }
}

/*
|--------------------------------------------------------------------------
| Inventory Add / Edit Dialog (UI Only)
|--------------------------------------------------------------------------
| This dialog is used by BOTH:
| 1) Creating a new inventory item
| 2) Editing an existing inventory item
|
| Responsibilities:
| - Collect user input (name, category, subCategory, notes, unitsKg)
| - Return a Map<String, dynamic> back to the caller via Navigator.pop
|
| Important:
| - This widget DOES NOT talk to Firestore
| - It DOES NOT create or update documents
| - It DOES NOT handle timestamps
|
| Firestore responsibilities (create/update, timestamps) are handled
| in the parent screen (InventoryScreen).
|--------------------------------------------------------------------------
*/

class _EditInventoryDialog extends StatefulWidget {
  final String initialName;
  final String initialCategory;
  final String initialSubCategory;
  final String initialNotes;
  final double initialUnitsKg;

  const _EditInventoryDialog({
    required this.initialName,
    required this.initialCategory,
    required this.initialSubCategory,
    required this.initialNotes,
    this.initialUnitsKg = 0.0,
  });

  @override
  State<_EditInventoryDialog> createState() => _EditInventoryDialogState();
}

class _EditInventoryDialogState extends State<_EditInventoryDialog> {
  static const List<String> kCategories = [
    'PP WHITE',
    'PP BLACK',
    'PP COLOR',
    'PP TRANS',
  ];

  late TextEditingController nameCtrl;
  late TextEditingController subCategoryCtrl;
  late TextEditingController notesCtrl;
  late TextEditingController unitsKgCtrl;

  String? categoryValue;
  String? nameError;
  String? unitsError;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.initialName);
    subCategoryCtrl = TextEditingController(text: widget.initialSubCategory);
    notesCtrl = TextEditingController(text: widget.initialNotes);
    unitsKgCtrl = TextEditingController(text: widget.initialUnitsKg.toString());

    categoryValue = kCategories.contains(widget.initialCategory)
        ? widget.initialCategory
        : kCategories.first;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    subCategoryCtrl.dispose();
    notesCtrl.dispose();
    unitsKgCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = nameCtrl.text.trim();
    final unitsRaw = unitsKgCtrl.text.trim();

    setState(() {
      nameError = null;
      unitsError = null;
    });

    if (name.isEmpty) {
      setState(() => nameError = "Name is required");
      return;
    }

    final units = double.tryParse(unitsRaw);
    if (units == null || units < 0) {
      setState(() => unitsError = "Enter a valid kg value (0 or more)");
      return;
    }

    Navigator.pop(context, {
      'name': name,
      'category': categoryValue ?? kCategories.first,
      'subCategory': subCategoryCtrl.text.trim(),
      'notes': notesCtrl.text.trim(),
      'unitsKg': units,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Inventory Item"),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: "Name",
                errorText: nameError,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: categoryValue,
              items: kCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => categoryValue = v),
              decoration: const InputDecoration(labelText: "Category"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: subCategoryCtrl,
              decoration: const InputDecoration(labelText: "Sub-category"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: unitsKgCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: "Units (kg)",
                errorText: unitsError,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: "Notes"),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text("Save"),
        ),
      ],
    );
  }
}

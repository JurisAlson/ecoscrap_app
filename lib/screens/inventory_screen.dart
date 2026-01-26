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
          ].join(' ').toLowerCase();
          return hay.contains(_query.toLowerCase());
        }).toList();

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),

          /// ➕ ADD BUTTON
          floatingActionButton: FloatingActionButton(
            backgroundColor: Colors.greenAccent,
            child: const Icon(Icons.add, color: Colors.black),
            onPressed: _addItem,
          ),

          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                /// 🔍 SEARCH
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

                /// 📦 LIST
                Expanded(
                  child: items.isEmpty
                      ? _emptyState()
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final doc = items[i];
                            final data =
                                doc.data() as Map<String, dynamic>;

                            final name =
                                data['name'] ?? 'Unnamed item';
                            final category =
                                data['category'] ?? '';
                            final subCategory =
                                data['subCategory'] ?? '';
                            final notes = data['notes'] ?? '';

                            return ListTile(
                              tileColor:
                                  Colors.white.withOpacity(0.06),
                              title: Text(
                                name,
                                style: const TextStyle(
                                    color: Colors.white),
                              ),
                              subtitle: Text(
                                "$category • $subCategory",
                                style: TextStyle(
                                    color: Colors.grey.shade400),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  /// ✏️ EDIT
                                  IconButton(
                                    icon: const Icon(Icons.edit,
                                        color: Colors.white),
                                    onPressed: () async {
                                      final edited =
                                          await showDialog<
                                              Map<String, dynamic>>(
                                        context: context,
                                        builder: (_) =>
                                            _EditInventoryDialog(
                                          initialName: name,
                                          initialCategory: category,
                                          initialSubCategory:
                                              subCategory,
                                          initialNotes: notes,
                                        ),
                                      );

                                      if (edited != null) {
                                        await FirebaseFirestore
                                            .instance
                                            .collection('Junkshop')
                                            .doc(widget.shopID)
                                            .collection('inventory')
                                            .doc(doc.id)
                                            .update(edited);
                                      }
                                    },
                                  ),

                                  /// 🗑 DELETE
                                  IconButton(
                                    icon: Icon(Icons.delete,
                                        color:
                                            Colors.red.shade300),
                                    onPressed: () =>
                                        _confirmDelete(doc.id),
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
        initialCategory: '',
        initialSubCategory: '',
        initialNotes: '',
      ),
    );

    if (created != null) {
      await FirebaseFirestore.instance
          .collection('Junkshop')
          .doc(widget.shopID)
          .collection('inventory')
          .add({
        ...created,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// 🗑 DELETE CONFIRM
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
      await FirebaseFirestore.instance
          .collection('Junkshop')
          .doc(widget.shopID)
          .collection('inventory')
          .doc(id)
          .delete();
    }
  }

  /// 📭 EMPTY STATE
  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inventory_2,
              size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          const Text(
            "No inventory items yet",
            style: TextStyle(color: Colors.grey),
          ),
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

/// ✏️ ADD / EDIT DIALOG
class _EditInventoryDialog extends StatefulWidget {
  final String initialName;
  final String initialCategory;
  final String initialSubCategory;
  final String initialNotes;

  const _EditInventoryDialog({
    required this.initialName,
    required this.initialCategory,
    required this.initialSubCategory,
    required this.initialNotes,
  });

  @override
  State<_EditInventoryDialog> createState() =>
      _EditInventoryDialogState();
}

class _EditInventoryDialogState
    extends State<_EditInventoryDialog> {
  late TextEditingController nameCtrl;
  late TextEditingController categoryCtrl;
  late TextEditingController subCategoryCtrl;
  late TextEditingController notesCtrl;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.initialName);
    categoryCtrl =
        TextEditingController(text: widget.initialCategory);
    subCategoryCtrl =
        TextEditingController(text: widget.initialSubCategory);
    notesCtrl =
        TextEditingController(text: widget.initialNotes);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    categoryCtrl.dispose();
    subCategoryCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
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
                decoration:
                    const InputDecoration(labelText: "Name")),
            TextField(
                controller: categoryCtrl,
                decoration: const InputDecoration(
                    labelText: "Category")),
            TextField(
                controller: subCategoryCtrl,
                decoration: const InputDecoration(
                    labelText: "Sub-category")),
            TextField(
                controller: notesCtrl,
                decoration:
                    const InputDecoration(labelText: "Notes")),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel")),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, {
              'name': nameCtrl.text.trim(),
              'category': categoryCtrl.text.trim(),
              'subCategory': subCategoryCtrl.text.trim(),
              'notes': notesCtrl.text.trim(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          },
          child: const Text("Save"),
        ),
      ],
    );
  }
}
 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/categories.dart';

enum FormMode { create, edit }

class InventoryFormScreen extends StatefulWidget {
  final FormMode mode;
  final Map<String, dynamic>? initial;

  const InventoryFormScreen({
    super.key,
    required this.mode,
    this.initial,
  });

  @override
  State<InventoryFormScreen> createState() => _InventoryFormScreenState();
}

class _InventoryFormScreenState extends State<InventoryFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _sub = TextEditingController();
  final _qty = TextEditingController();
  final _notes = TextEditingController();

  String _category = kMajorCategories.first;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.initial;
    if (data != null) {
      _name.text = (data['name'] ?? '').toString();
      _category = (data['category'] ?? _category).toString();
      _sub.text = (data['subCategory'] ?? '').toString();

      // ✅ FIX: read unitsKg (same field you save)
      _qty.text = ((data['unitsKg'] ?? 0).toString());

      _notes.text = (data['notes'] ?? '').toString();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _sub.dispose();
    _qty.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.mode == FormMode.edit;

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? "Edit Item" : "Add Item")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: "Item name"),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? "Required" : null,
              ),
              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                value: _category,
                items: kMajorCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _category = v ?? kMajorCategories.first),
                decoration: const InputDecoration(labelText: "Category"),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _sub,
                decoration:
                    const InputDecoration(labelText: "Sub-category (optional)"),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: "Quantity (kg)"),
                validator: (v) {
                  final n = double.tryParse(v ?? "");
                  if (n == null || n < 0) return "Enter a valid number";
                  return null;
                },
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _notes,
                decoration: const InputDecoration(labelText: "Notes (optional)"),
                maxLines: 3,
              ),
              const SizedBox(height: 18),

              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? "Saving..." : (isEdit ? "Update" : "Create")),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    final payload = {
      'name': _name.text.trim(),
      'category': _category.trim(),
      'subCategory': _sub.text.trim(),
      'unitsKg': double.tryParse(_qty.text.trim()) ?? 0.0,
      'notes': _notes.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (!mounted) return;
    Navigator.pop(context, payload);
  }
}
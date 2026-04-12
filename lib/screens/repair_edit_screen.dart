import 'package:flutter/material.dart';

import '../models/repair_project.dart';
import '../models/repair_status.dart';
import '../services/repair_storage.dart';

/// Edycja metadanych naprawy (Read/Update w CRUD).
class RepairEditScreen extends StatefulWidget {
  const RepairEditScreen({super.key, required this.project});

  final RepairProject project;

  @override
  State<RepairEditScreen> createState() => _RepairEditScreenState();
}

class _RepairEditScreenState extends State<RepairEditScreen> {
  late final TextEditingController _category;
  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _boardId;
  late final TextEditingController _docUrl;
  late RepairStatus _status;
  late bool _boardConfirmed;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.project;
    _category = TextEditingController(text: p.deviceCategory);
    _brand = TextEditingController(text: p.brand);
    _model = TextEditingController(text: p.modelName);
    _boardId = TextEditingController(text: p.boardModelCode);
    _docUrl = TextEditingController(text: p.documentationUrl ?? '');
    _status = p.repairStatus;
    _boardConfirmed = p.boardIdentityConfirmed;
  }

  @override
  void dispose() {
    _category.dispose();
    _brand.dispose();
    _model.dispose();
    _boardId.dispose();
    _docUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final p = widget.project;
    final doc = _docUrl.text.trim();
    final updated = p.copyWith(
      deviceCategory: _category.text.trim(),
      brand: _brand.text.trim(),
      modelName: _model.text.trim(),
      boardModelCode: _boardId.text.trim(),
      repairStatus: _status,
      boardIdentityConfirmed: _boardConfirmed,
      documentationUrl: doc.isEmpty ? null : doc,
      clearDocumentationUrl: doc.isEmpty,
    );
    await RepairStorage.instance.saveRepair(updated);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edycja naprawy'),
        backgroundColor: const Color(0xFF1F1F1F),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Zapisz', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _category,
            decoration: const InputDecoration(
              labelText: 'Kategoria urządzenia',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _brand,
            decoration: const InputDecoration(
              labelText: 'Marka',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
              labelText: 'Model',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _boardId,
            decoration: const InputDecoration(
              labelText: 'Board ID / kod PCB',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Status',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<RepairStatus>(
                value: _status,
                isExpanded: true,
                dropdownColor: const Color(0xFF2C2C2C),
                items: RepairStatus.values
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.labelPl),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (v) {
                        if (v != null) setState(() => _status = v);
                      },
              ),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Tożsamość płyty potwierdzona'),
            value: _boardConfirmed,
            onChanged: _saving
                ? null
                : (v) => setState(() => _boardConfirmed = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _docUrl,
            decoration: const InputDecoration(
              labelText: 'Link do dokumentacji (opcjonalnie)',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 8),
          const Text(
            'Lista „krytycznych” układów i intake z kreatora zostają w projekcie — '
            'tu edytujesz głównie Board ID i status.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

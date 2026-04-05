import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/measurement_log_entry.dart';
import '../models/repair_project.dart';
import '../services/repair_storage.dart';

/// Szybkie logowanie pomiarów — duże przyciski, minimum kroków (brudne ręce).
class MeasurementsQuickScreen extends StatefulWidget {
  const MeasurementsQuickScreen({super.key, required this.repair});

  final RepairProject repair;

  @override
  State<MeasurementsQuickScreen> createState() =>
      _MeasurementsQuickScreenState();
}

class _MeasurementsQuickScreenState extends State<MeasurementsQuickScreen> {
  final _valueCtrl = TextEditingController();
  final _netCtrl = TextEditingController();
  MeasurementKind _kind = MeasurementKind.voltage;
  String _unitV = 'V';
  String _unitR = 'Ω';
  String _unitI = 'mA';
  List<MeasurementLogEntry> _recent = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await RepairStorage.instance.listMeasurements(widget.repair.id, limit: 30);
    if (mounted) setState(() => _recent = list);
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    _netCtrl.dispose();
    super.dispose();
  }

  double? _parseToBase() {
    var t = _valueCtrl.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return null;
    switch (_kind) {
      case MeasurementKind.voltage:
        return _unitV == 'mV' ? v / 1000 : v;
      case MeasurementKind.resistance:
        if (_unitR == 'kΩ') return v * 1000;
        if (_unitR == 'MΩ') return v * 1e6;
        return v;
      case MeasurementKind.current:
        return _unitI == 'mA' ? v / 1000 : v;
    }
  }

  String _displayUnit() {
    switch (_kind) {
      case MeasurementKind.voltage:
        return _unitV;
      case MeasurementKind.resistance:
        return _unitR;
      case MeasurementKind.current:
        return _unitI;
    }
  }

  Future<void> _save() async {
    final base = _parseToBase();
    if (base == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wpisz wartość liczbową')),
      );
      return;
    }
    setState(() => _saving = true);
    final display = '${_valueCtrl.text.trim().replaceAll(',', '.')} ${_displayUnit()}';
    final entry = MeasurementLogEntry.create(
      repairId: widget.repair.id,
      kind: _kind,
      value: base,
      unit: display,
      netLabel: _netCtrl.text.trim(),
    );
    await RepairStorage.instance.insertMeasurement(entry);
    _valueCtrl.clear();
    if (mounted) {
      setState(() => _saving = false);
    }
    await _reload();
    if (!mounted) return;
    FocusScope.of(context).requestFocus(FocusNode());
  }

  @override
  Widget build(BuildContext context) {
    final bid = widget.repair.boardId.trim().isEmpty ? '—' : widget.repair.boardId;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Pomiary'),
        backgroundColor: const Color(0xFF1F1F1F),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Board_ID',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
          SelectableText(
            bid,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.orangeAccent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.repair.displayTitle,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 20),
          SegmentedButton<MeasurementKind>(
            segments: const [
              ButtonSegment(
                value: MeasurementKind.voltage,
                label: Text('U · V'),
                icon: Icon(Icons.bolt, size: 18),
              ),
              ButtonSegment(
                value: MeasurementKind.resistance,
                label: Text('R · Ω'),
                icon: Icon(Icons.straighten, size: 18),
              ),
              ButtonSegment(
                value: MeasurementKind.current,
                label: Text('I · A'),
                icon: Icon(Icons.battery_charging_full, size: 18),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) {
              setState(() => _kind = s.first);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _netCtrl,
            decoration: const InputDecoration(
              labelText: 'Sieć / punkt (opcjonalnie)',
              hintText: 'np. 3V3, D1, szyna wejścia',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _valueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: false,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    labelText: 'Wartość',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _unitChips(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('ZAPISZ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 24),
          const Text(
            'Ostatnie',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          ..._recent.map(
            (e) => Card(
              color: const Color(0xFF252525),
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(
                  e.displayLine,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  e.measuredAt.toLocal().toString().split('.').first,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unitChips() {
    switch (_kind) {
      case MeasurementKind.voltage:
        return Wrap(
          spacing: 6,
          children: [
            ChoiceChip(
              label: const Text('V'),
              selected: _unitV == 'V',
              onSelected: (_) => setState(() => _unitV = 'V'),
            ),
            ChoiceChip(
              label: const Text('mV'),
              selected: _unitV == 'mV',
              onSelected: (_) => setState(() => _unitV = 'mV'),
            ),
          ],
        );
      case MeasurementKind.resistance:
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: const Text('Ω'),
              selected: _unitR == 'Ω',
              onSelected: (_) => setState(() => _unitR = 'Ω'),
            ),
            ChoiceChip(
              label: const Text('kΩ'),
              selected: _unitR == 'kΩ',
              onSelected: (_) => setState(() => _unitR = 'kΩ'),
            ),
            ChoiceChip(
              label: const Text('MΩ'),
              selected: _unitR == 'MΩ',
              onSelected: (_) => setState(() => _unitR = 'MΩ'),
            ),
          ],
        );
      case MeasurementKind.current:
        return Wrap(
          spacing: 6,
          children: [
            ChoiceChip(
              label: const Text('mA'),
              selected: _unitI == 'mA',
              onSelected: (_) => setState(() => _unitI = 'mA'),
            ),
            ChoiceChip(
              label: const Text('A'),
              selected: _unitI == 'A',
              onSelected: (_) => setState(() => _unitI = 'A'),
            ),
          ],
        );
    }
  }
}

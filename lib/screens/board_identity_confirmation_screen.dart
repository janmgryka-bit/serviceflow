import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/repair_project.dart';
import '../models/repair_status.dart';
import '../services/repair_storage.dart';
import 'diagnostic_dashboard_screen.dart';
import 'measurements_quick_screen.dart';

enum NextAfterConfirmation {
  diagnostic,
  measurements,
}

/// Formalny krok: potwierdzenie że pracujemy na właściwej płytce / rewizji + dokumentacja.
class BoardIdentityConfirmationScreen extends StatefulWidget {
  const BoardIdentityConfirmationScreen({
    super.key,
    required this.repair,
    this.nextAfterConfirmation = NextAfterConfirmation.diagnostic,
  });

  final RepairProject repair;
  final NextAfterConfirmation nextAfterConfirmation;

  @override
  State<BoardIdentityConfirmationScreen> createState() =>
      _BoardIdentityConfirmationScreenState();
}

class _BoardIdentityConfirmationScreenState
    extends State<BoardIdentityConfirmationScreen> {
  late final TextEditingController _urlCtrl;
  late String? _localPath;
  bool _confirmed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.repair.documentationUrl ?? '');
    _localPath = widget.repair.documentationLocalPath;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'zip'],
    );
    if (!mounted) return;
    if (r != null && r.files.isNotEmpty) {
      final p = r.files.single.path;
      setState(() => _localPath = p);
    }
  }

  Future<void> _submit() async {
    if (!_confirmed || _saving) return;
    setState(() => _saving = true);
    final url = _urlCtrl.text.trim();
    final path = _localPath?.trim();
    final updated = widget.repair.copyWith(
      boardIdentityConfirmed: true,
      repairStatus: RepairStatus.inDiagnosis,
      documentationUrl: url.isNotEmpty ? url : null,
      clearDocumentationUrl: url.isEmpty,
      documentationLocalPath:
          path != null && path.isNotEmpty ? path : null,
      clearDocumentationLocalPath: path == null || path.isEmpty,
    );
    await RepairStorage.instance.saveRepair(updated);
    if (!mounted) return;
    setState(() => _saving = false);

    final next = switch (widget.nextAfterConfirmation) {
      NextAfterConfirmation.diagnostic => DiagnosticDashboardScreen(repair: updated),
      NextAfterConfirmation.measurements => MeasurementsQuickScreen(repair: updated),
    };

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => next),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.repair;
    final chips = p.components
        .where((c) => c.value.trim().isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Potwierdzenie płyty'),
        backgroundColor: const Color(0xFF1F1F1F),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Zanim AI poprowadzi diagnozę, upewnij się że pracujesz na tej samej '
            'płytce co poniżej — kod PCB na urządzeniu musi się zgadzać, a krytyczne '
            'układy (CPU, Ethernet, PMIC itd.) muszą odpowiadać wybranej rewizji.',
            style: TextStyle(color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 20),
          Card(
            color: const Color(0xFF252525),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Board ID (kod PCB)',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    p.boardModelCode.isEmpty ? '—' : p.boardModelCode,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${p.displayTitle} · ${p.deviceCategory}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (chips.isNotEmpty) ...[
                    const Divider(height: 24),
                    const Text(
                      'Krytyczne / rewizje (z kreatora)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...chips.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                c.label,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                            Expanded(child: Text(c.value)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Dokumentacja (opcjonalnie)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Wklej link do schematu / boardview albo wskaż plik z dysku. '
            'Jeśli nic nie masz — też da się diagnozować zgodnie ze sztuką (bez PDF).',
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'URL (http/https)',
              hintText: 'https://…',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: _pickFile,
                child: const Text('Wybierz plik'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localPath == null || _localPath!.isEmpty
                      ? 'Brak pliku lokalnego'
                      : _localPath!,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_localPath != null && _localPath!.isNotEmpty)
                IconButton(
                  tooltip: 'Usuń plik',
                  onPressed: () => setState(() => _localPath = null),
                  icon: const Icon(Icons.clear),
                ),
            ],
          ),
          const SizedBox(height: 28),
          CheckboxListTile(
            value: _confirmed,
            onChanged: (v) => setState(() => _confirmed = v ?? false),
            title: const Text(
              'Potwierdzam: kod PCB na urządzeniu zgadza się z Board ID powyżej, '
              'a krytyczne układy odpowiadają tej rewizji — przechodzimy do diagnozy.',
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_confirmed && !_saving) ? _submit : null,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Potwierdzam i rozpoczynam diagnozę',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
        ],
      ),
    );
  }
}

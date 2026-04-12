import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/knowledge_index_result.dart';
import '../services/repair_storage.dart';

/// Wybór PDF, indeksacja lokalna (SQLite FTS) — treść trafia do promptu czatu diagnostycznego.
class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  Future<KnowledgeSourceMeta?>? _metaFuture;
  bool _indexing = false;
  String? _lastInfo;
  final TextEditingController _pathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _metaFuture = RepairStorage.instance.getKnowledgeSourceMeta();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  void _reloadMeta() {
    setState(() {
      _metaFuture = RepairStorage.instance.getKnowledgeSourceMeta();
    });
  }

  Future<void> _indexFromPath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      setState(() => _lastInfo = 'Podaj ścieżkę do pliku PDF.');
      return;
    }
    setState(() {
      _indexing = true;
      _lastInfo = 'Indeksowanie…';
    });
    final KnowledgeIndexResult r =
        await RepairStorage.instance.indexKnowledgePdf(trimmed);
    if (!mounted) return;
    setState(() {
      _indexing = false;
      _lastInfo = r.success
          ? 'Zindeksowano ${r.chunkCount} fragmentów.'
          : (r.message ?? 'Błąd indeksacji.');
    });
    _reloadMeta();
  }

  Future<void> _pickAndIndex() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null || path.isEmpty) {
        setState(() => _lastInfo = 'Brak ścieżki do pliku.');
        return;
      }
      await _indexFromPath(path);
    } catch (e, st) {
      debugPrint('FilePicker: $e\n$st');
      if (!mounted) return;
      setState(() {
        _lastInfo =
            'Okno wyboru pliku nie działa (na Linuxie zwykle brakuje zenity w PATH). '
            'Zainstaluj pakiet: sudo apt install zenity '
            'albo wpisz poniżej pełną ścieżkę do PDF i użyj „Indeksuj z wpisanej ścieżki”.';
      });
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć bazę wiedzy?'),
        content: const Text(
          'Lokalny indeks tego PDF zostanie usunięty. '
          'Indeks stron WWW w ustawieniach pozostaje. '
          'Plik PDF na dysku nie jest kasowany.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await RepairStorage.instance.clearKnowledgePdfOnly();
    if (!mounted) return;
    setState(() => _lastInfo = 'Indeks usunięty.');
    _reloadMeta();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Baza wiedzy (PDF)'),
        backgroundColor: const Color(0xFF1F1F1F),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Wskaż plik PDF (np. książkę serwisową). Tekst zostanie '
              'zapisany tylko lokalnie i dołączany do czatu diagnostycznego '
              'jako fragmenty pomocnicze — nic nie jest wysyłane na zewnątrz '
              'poza zwykłym promptem do modelu.',
              style: TextStyle(color: Colors.grey, height: 1.35),
            ),
            const SizedBox(height: 8),
            const Text(
              'Linux: do okna wyboru pliku potrzebny jest program zenity '
              '(sudo apt install zenity). Bez niego użyj wpisanej ścieżki poniżej.',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.3),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _indexing ? null : _pickAndIndex,
              icon: _indexing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_indexing ? 'Indeksowanie…' : 'Wybierz PDF i indeksuj'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
              ),
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Albo pełna ścieżka do pliku',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pathController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: '/ścieżka/do/pliku.pdf',
                hintStyle: TextStyle(color: Colors.white30),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              readOnly: _indexing,
              onSubmitted: _indexing ? null : (v) => _indexFromPath(v),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _indexing
                  ? null
                  : () => _indexFromPath(_pathController.text),
              child: const Text('Indeksuj z wpisanej ścieżki'),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _indexing ? null : _clear,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Usuń indeks z urządzenia'),
            ),
            if (_lastInfo != null) ...[
              const SizedBox(height: 16),
              Text(
                _lastInfo!,
                style: TextStyle(
                  color: _lastInfo!.startsWith('Zindeksowano')
                      ? Colors.greenAccent
                      : Colors.grey,
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'Stan',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<KnowledgeSourceMeta?>(
                future: _metaFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final meta = snapshot.data;
                  if (meta == null || meta.chunkCount == 0) {
                    return const Text(
                      'Brak indeksu — wybierz PDF powyżej.',
                      style: TextStyle(color: Colors.grey),
                    );
                  }
                  return SelectableText(
                    'Plik: ${meta.sourcePath}\n'
                    'Fragmentów: ${meta.chunkCount}\n'
                    'Data: ${meta.indexedAt.toLocal()}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.4,
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
}

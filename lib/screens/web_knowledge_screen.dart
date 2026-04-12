import 'package:flutter/material.dart';

import '../models/indexed_web_source.dart';
import '../services/repair_storage.dart';

/// Dodawanie adresów WWW, pobranie HTML, indeks FTS (RAG).
class WebKnowledgeScreen extends StatefulWidget {
  const WebKnowledgeScreen({super.key});

  @override
  State<WebKnowledgeScreen> createState() => _WebKnowledgeScreenState();
}

class _WebKnowledgeScreenState extends State<WebKnowledgeScreen> {
  final _urlController = TextEditingController();
  Future<List<IndexedWebSource>>? _listFuture;
  bool _busy = false;
  String? _info;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _listFuture = RepairStorage.instance.listIndexedWebSources();
    });
  }

  Future<void> _index() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      setState(() => _info = 'Wklej adres URL.');
      return;
    }
    setState(() {
      _busy = true;
      _info = 'Pobieranie i indeksowanie…';
    });
    final r = await RepairStorage.instance.indexKnowledgeUrl(raw);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _info = r.success
          ? 'OK — ${r.chunkCount} fragmentów.'
          : (r.message ?? 'Błąd.');
    });
    if (r.success) _urlController.clear();
    _reload();
  }

  Future<void> _delete(IndexedWebSource s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usunąć indeks tej strony?'),
        content: Text(s.url),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await RepairStorage.instance.deleteIndexedWebSource(s.id);
    _reload();
    if (mounted) {
      setState(() => _info = 'Usunięto: ${s.url}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Strony WWW (indeks)'),
        backgroundColor: const Color(0xFF1F1F1F),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Aplikacja pobiera HTML (jak przeglądarka), wycina tekst i zapisuje '
              'lokalnie. Strony z logowaniem lub CAPTCHA mogą nie dać treści. '
              'Używaj stabilnych URL (np. dokumentacja publiczna).',
              style: TextStyle(color: Colors.grey, height: 1.35, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'URL',
                hintText: 'https://…',
                border: OutlineInputBorder(),
              ),
              readOnly: _busy,
              onSubmitted: _busy ? null : (_) => _index(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _index,
              icon: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: const Text('Pobierz i indeksuj'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            if (_info != null) ...[
              const SizedBox(height: 12),
              Text(
                _info!,
                style: TextStyle(
                  color: _info!.startsWith('OK') ? Colors.greenAccent : Colors.grey,
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Zindeksowane',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<IndexedWebSource>>(
                future: _listFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    return const Text(
                      'Brak — dodaj URL powyżej.',
                      style: TextStyle(color: Colors.grey),
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final s = items[i];
                      return ListTile(
                        title: Text(
                          s.title.isEmpty ? s.url : s.title,
                          style: const TextStyle(fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${s.url}\n'
                          '${s.chunkCount} fragmentów · ${s.indexedAt.toLocal()}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(s),
                        ),
                      );
                    },
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

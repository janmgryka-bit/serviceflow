import 'package:flutter/material.dart';

import '../services/repair_storage.dart';
import 'knowledge_base_screen.dart';
import 'web_knowledge_screen.dart';

/// Ustawienia: baza wiedzy PDF, indeks stron WWW, czyszczenie całości.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ustawienia'),
        backgroundColor: const Color(0xFF1F1F1F),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Baza wiedzy (lokalna)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Fragmenty trafiają do promptu czatu diagnostycznego. '
            'Nic nie jest wysyłane poza normalnym żądaniem do modelu.',
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined, color: Colors.orangeAccent),
            title: const Text('PDF'),
            subtitle: const Text('Książka / dokument z dysku'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => const KnowledgeBaseScreen(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.link, color: Colors.orangeAccent),
            title: const Text('Strony WWW'),
            subtitle: const Text('Pobranie treści HTML i indeks (jak PDF)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => const WebKnowledgeScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          const Text(
            'Zarządzanie',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
            title: const Text('Usuń całą bazę wiedzy'),
            subtitle: const Text('PDF + strony WWW — operacja nieodwracalna lokalnie'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Usunąć całą bazę wiedzy?'),
                  content: const Text(
                    'Zostaną usunięte wszystkie zindeksowane fragmenty (PDF i WWW). '
                    'Pliki PDF na dysku i strony w internecie nie są kasowane.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Anuluj'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Usuń wszystko'),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                await RepairStorage.instance.clearKnowledgeBase();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Baza wiedzy wyczyszczona.')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

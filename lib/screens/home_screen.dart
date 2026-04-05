import 'package:flutter/material.dart';

import '../models/repair_project.dart';
import '../services/repair_storage.dart';
import 'diagnostic_dashboard_screen.dart';
import 'verification_wizard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<RepairProject>> _repairsFuture;

  @override
  void initState() {
    super.initState();
    _repairsFuture = RepairStorage.instance.loadRepairs();
  }

  void _refresh() {
    setState(() {
      _repairsFuture = RepairStorage.instance.loadRepairs();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ServiceFlow AI'),
        backgroundColor: const Color(0xFF1F1F1F),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: FilledButton(
              onPressed: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (context) => const VerificationWizardScreen(),
                  ),
                );
                _refresh();
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 22),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
              ),
              child: const Text(
                'Start New Repair',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Recent repairs',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<RepairProject>>(
              future: _repairsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not load history: ${snapshot.error}',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  );
                }
                final repairs = snapshot.data ?? [];
                if (repairs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No repairs yet. Start one to build your local history.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: repairs.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final r = repairs[index];
                    return ListTile(
                      title: Text(
                        r.displayTitle,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${r.boardModelCode} · ${r.id} · '
                        '${r.createdAt.toLocal().toString().split('.').first}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (context) =>
                                DiagnosticDashboardScreen(repair: r),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

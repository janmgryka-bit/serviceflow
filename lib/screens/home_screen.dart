import 'package:flutter/material.dart';

import '../models/repair_summary.dart';
import '../services/repair_storage.dart';
import 'diagnostic_dashboard_screen.dart';
import 'measurements_quick_screen.dart';
import 'verification_wizard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<RepairSummary>> _summariesFuture;

  @override
  void initState() {
    super.initState();
    _summariesFuture = RepairStorage.instance.loadRepairSummaries();
  }

  void _refresh() {
    setState(() {
      _summariesFuture = RepairStorage.instance.loadRepairSummaries();
    });
  }

  Future<void> _openRepair(String id, {required bool measurements}) async {
    final repair = await RepairStorage.instance.getRepairById(id);
    if (!mounted || repair == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => measurements
            ? MeasurementsQuickScreen(repair: repair)
            : DiagnosticDashboardScreen(repair: repair),
      ),
    );
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
                'Nowa naprawa',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              'Ostatnie (Board_ID)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<RepairSummary>>(
              future: _summariesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Błąd listy: ${snapshot.error}',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  );
                }
                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'Brak wpisów. Utwórz naprawę — zapis jest lokalny.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final r = items[index];
                    final bid = r.boardId.isEmpty ? '—' : r.boardId;
                    return ListTile(
                      title: Text(
                        bid,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.orangeAccent,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        '${r.deviceLabel}\n'
                        '${r.createdAt.toLocal().toString().split('.').first}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      isThreeLine: true,
                      leading: const Icon(Icons.memory_outlined),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Pomiary (szybki wpis)',
                            icon: const Icon(Icons.speed),
                            onPressed: () => _openRepair(r.id, measurements: true),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => _openRepair(r.id, measurements: false),
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

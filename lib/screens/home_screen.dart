import 'package:flutter/material.dart';

import '../models/repair_status.dart';
import '../models/repair_summary.dart';
import '../services/repair_storage.dart';
import 'board_identity_confirmation_screen.dart';
import 'diagnostic_dashboard_screen.dart';
import 'repair_edit_screen.dart';
import 'settings_screen.dart';
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

  Future<void> _openRepair(String id) async {
    final repair = await RepairStorage.instance.getRepairById(id);
    if (!mounted || repair == null) return;
    if (!repair.boardIdentityConfirmed) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => BoardIdentityConfirmationScreen(
            repair: repair,
            nextAfterConfirmation: NextAfterConfirmation.diagnostic,
          ),
        ),
      );
      _refresh();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => DiagnosticDashboardScreen(repair: repair),
      ),
    );
    _refresh();
  }

  Future<void> _editRepair(String id) async {
    final project = await RepairStorage.instance.getRepairById(id);
    if (!mounted || project == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => RepairEditScreen(project: project),
      ),
    );
    if (changed == true) _refresh();
  }

  Future<void> _deleteRepair(RepairSummary r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć naprawę?'),
        content: Text(
          'Board ID: ${r.boardId.isEmpty ? '—' : r.boardId}\n'
          '${r.deviceLabel}\n\n'
          'Zostaną usunięte też czat diagnostyczny i pomiary dla tej naprawy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await RepairStorage.instance.deleteRepair(r.id);
    _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Naprawa usunięta.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ServiceFlow AI'),
        backgroundColor: const Color(0xFF1F1F1F),
        actions: [
          IconButton(
            tooltip: 'Ustawienia',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
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
                    final statusLine =
                        '${r.repairStatus.labelPl}${r.boardIdentityConfirmed ? '' : ' · czeka na potwierdzenie'}';
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
                        '$statusLine · '
                        '${r.createdAt.toLocal().toString().split('.').first}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      isThreeLine: true,
                      leading: const Icon(Icons.memory_outlined),
                      onTap: () => _openRepair(r.id),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) async {
                          if (value == 'edit') await _editRepair(r.id);
                          if (value == 'delete') await _deleteRepair(r);
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('Edytuj'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                SizedBox(width: 12),
                                Text('Usuń', style: TextStyle(color: Colors.redAccent)),
                              ],
                            ),
                          ),
                        ],
                      ),
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

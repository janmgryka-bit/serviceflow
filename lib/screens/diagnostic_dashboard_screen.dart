import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/diagnostic_chat_message.dart';
import '../models/diagnostic_chat_snapshot.dart';
import '../models/diagnostic_phase.dart';
import '../models/repair_project.dart';
import '../models/repair_status.dart';
import '../services/diagnostic_chat_service.dart';
import '../services/diagnostic_workflow_template.dart';
import '../services/repair_storage.dart';
import '../widgets/diagnostic_drawer_camera_panel.dart';
import '../widgets/microscope_chat_image.dart';
import 'measurements_quick_screen.dart';

/// Interactive assistant flow: Groq-led diagnosis with optional technical drawer.
class DiagnosticDashboardScreen extends StatefulWidget {
  const DiagnosticDashboardScreen({super.key, required this.repair});

  final RepairProject repair;

  @override
  State<DiagnosticDashboardScreen> createState() =>
      _DiagnosticDashboardScreenState();
}

class _DiagnosticDashboardScreenState extends State<DiagnosticDashboardScreen> {
  late RepairProject _repair;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<DiagnosticChatMessage> _messages = [];
  final List<String> _checklist = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  String _technicalPreview = '';
  bool _chatMode = true;
  bool _sessionComplete = false;
  bool _loading = true;
  bool _sending = false;

  DiagnosticPhase _phase = DiagnosticPhase.powerInput;
  int _measurementCount = 0;

  @override
  void initState() {
    super.initState();
    _repair = widget.repair;
    _bootstrap();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshMeasurementCount());
  }

  Future<void> _refreshMeasurementCount() async {
    final n =
        await RepairStorage.instance.listMeasurements(_repair.id, limit: 5000);
    if (!mounted) return;
    setState(() => _measurementCount = n.length);
  }

  Future<void> _openMeasurementsQuick() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MeasurementsQuickScreen(repair: _repair),
      ),
    );
    await _refreshMeasurementCount();
  }

  /// Szablon VIN→szyny + unikalne wpisy z AI (tylko przy świeżej sesji).
  List<String> _mergeSeedWithAi(List<String> seed, List<String> ai) {
    final out = <String>[...seed];
    for (final x in ai) {
      if (!out.contains(x)) out.add(x);
    }
    return out;
  }

  Future<void> _bootstrap() async {
    final saved =
        await RepairStorage.instance.getDiagnosticChatSnapshot(_repair.id);
    if (!mounted) return;
    if (saved != null && saved.messages.isNotEmpty) {
      setState(() {
        _messages.addAll(saved.messages);
        _checklist.addAll(saved.checklist);
        _technicalPreview = saved.technicalPreview;
        _chatMode = saved.chatMode;
        _sessionComplete = saved.sessionComplete;
        _phase = diagnosticPhaseFromApi(saved.diagnosticPhase) ??
            DiagnosticPhase.powerInput;
        _loading = false;
      });
      _scrollToBottom();
      return;
    }
    await _startSession();
  }

  void _maybeOpenTechnicalDrawer(DiagnosticChatTurn turn) {
    if (!turn.showTechnicalDrawer || turn.technicalPreview.trim().isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scaffoldKey.currentState?.openEndDrawer();
    });
  }

  Future<void> _startSession() async {
    setState(() {
      _loading = true;
      _sessionComplete = false;
    });
    try {
      final turn = await DiagnosticChatService.startSession(_repair);
      if (!mounted) return;
      final seed = DiagnosticWorkflowTemplate.seedChecklist(_repair);
      setState(() {
        _messages.clear();
        _checklist.clear();
        _messages.add(
          DiagnosticChatMessage(isUser: false, text: turn.nextQuestion),
        );
        _technicalPreview = turn.technicalPreview;
        _checklist.addAll(_mergeSeedWithAi(seed, turn.checklistAdd));
        _sessionComplete = turn.sessionComplete;
        _phase = turn.phase ?? DiagnosticPhase.powerInput;
        _loading = false;
      });
      _maybeOpenTechnicalDrawer(turn);
      _persist();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _messages.add(
          DiagnosticChatMessage(
            isUser: false,
            text: 'Nie udało się uruchomić sesji: $e',
          ),
        );
      });
    }
  }

  Future<void> _nextStep() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending || _sessionComplete) return;

    final history = List<DiagnosticChatMessage>.from(_messages);

    setState(() {
      _messages.add(DiagnosticChatMessage(isUser: true, text: text));
      _sending = true;
    });
    _inputCtrl.clear();
    _scrollToBottom();

    try {
      final turn = await DiagnosticChatService.continueSession(
        _repair,
        history,
        text,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          DiagnosticChatMessage(isUser: false, text: turn.nextQuestion),
        );
        if (turn.technicalPreview.isNotEmpty) {
          _technicalPreview = turn.technicalPreview;
        }
        _checklist.addAll(turn.checklistAdd);
        _sessionComplete = turn.sessionComplete;
        if (turn.phase != null) {
          _phase = turn.phase!;
        }
        _sending = false;
      });
      _maybeOpenTechnicalDrawer(turn);
      _persist();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          DiagnosticChatMessage(
            isUser: false,
            text: 'Błąd: $e',
          ),
        );
        _sending = false;
      });
    }
  }

  Future<void> _onVisualEvidenceCaptured(String imagePath) async {
    if (!mounted || _sessionComplete || _sending) return;
    final prompt = DiagnosticChatService.kVisualEvidencePrompt;
    final history = List<DiagnosticChatMessage>.from(_messages);
    setState(() {
      _messages.add(
        DiagnosticChatMessage(
          isUser: true,
          text: prompt,
          localImagePath: imagePath,
        ),
      );
      _sending = true;
    });
    _scrollToBottom();
    try {
      final turn = await DiagnosticChatService.continueSession(
        _repair,
        history,
        prompt,
        microscopeImagePath: imagePath,
      );
      if (!mounted) return;
      setState(() {
        _messages.add(
          DiagnosticChatMessage(isUser: false, text: turn.nextQuestion),
        );
        if (turn.technicalPreview.isNotEmpty) {
          _technicalPreview = turn.technicalPreview;
        }
        _checklist.addAll(turn.checklistAdd);
        _sessionComplete = turn.sessionComplete;
        if (turn.phase != null) {
          _phase = turn.phase!;
        }
        _sending = false;
      });
      _maybeOpenTechnicalDrawer(turn);
      _persist();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          DiagnosticChatMessage(isUser: false, text: 'Błąd: $e'),
        );
        _sending = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _persist() async {
    try {
      await RepairStorage.instance.saveDiagnosticChatSnapshot(
        _repair.id,
        DiagnosticChatSnapshot(
          messages: List.from(_messages),
          checklist: List.from(_checklist),
          technicalPreview: _technicalPreview,
          chatMode: _chatMode,
          sessionComplete: _sessionComplete,
          diagnosticPhase: diagnosticPhaseToApi(_phase),
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repair = _repair;
    final drawerW = math.min(440.0, MediaQuery.sizeOf(context).width * 0.94);

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: Drawer(
        width: drawerW,
        backgroundColor: const Color(0xFF1A1A1A),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 8),
                child: Row(
                  children: [
                    Icon(Icons.tune, color: Colors.amber.shade200, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Szczegóły techniczne',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zamknij',
                      onPressed: () =>
                          Scaffold.of(context).closeEndDrawer(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Podgląd UVC (v4l2) — jak w guvcview; zamknij inne programy używające tej samej kamery.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              DiagnosticDrawerCameraPanel(
                repairId: repair.id,
                enabled: !_loading && !_sending && !_sessionComplete,
                onCaptured: _onVisualEvidenceCaptured,
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    _technicalPreview.isEmpty
                        ? 'Brak szczegółów technicznych w tym kroku.'
                        : _technicalPreview,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        title: Text('Asystent · ${repair.summaryLine}'),
        backgroundColor: const Color(0xFF1F1F1F),
        actions: [
          PopupMenuButton<RepairStatus>(
            tooltip: 'Status naprawy',
            onSelected: (s) async {
              final u = _repair.copyWith(repairStatus: s);
              await RepairStorage.instance.saveRepair(u);
              if (!mounted) return;
              setState(() => _repair = u);
            },
            itemBuilder: (context) => RepairStatus.values
                .map(
                  (s) => PopupMenuItem<RepairStatus>(
                    value: s,
                    child: Text(s.labelPl),
                  ),
                )
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.flag_outlined, size: 22),
                  const SizedBox(width: 6),
                  Text(
                    _repair.repairStatus.labelPl,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Pomiary',
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) =>
                      MeasurementsQuickScreen(repair: _repair),
                ),
              );
            },
            icon: const Icon(Icons.speed),
          ),
          if (_technicalPreview.isNotEmpty)
            IconButton(
              tooltip: 'Szczegóły techniczne',
              onPressed: () =>
                  _scaffoldKey.currentState?.openEndDrawer(),
              icon: const Icon(Icons.menu_book_outlined),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: true,
                  label: Text('Tryb czatu'),
                  icon: Icon(Icons.chat_bubble_outline, size: 18),
                ),
                ButtonSegment<bool>(
                  value: false,
                  label: Text('Lista kontrolna'),
                  icon: Icon(Icons.checklist, size: 18),
                ),
              ],
              selected: {_chatMode},
              onSelectionChanged: (Set<bool> s) {
                final v = s.first;
                setState(() => _chatMode = v);
                _persist();
              },
            ),
          ),
          IconButton(
            tooltip: 'Od nowa',
            onPressed: _loading || _sending
                ? null
                : () async {
                    await _startSession();
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: Colors.orange,
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'AI myśli…',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : _chatMode
              ? _buildChatArea()
              : _buildChecklistArea(),
    );
  }

  Widget _buildChatArea() {
    return Column(
      children: [
        _RepairHeaderBar(repair: _repair),
        _buildPhaseStrip(),
        _buildMeasurementsQuickCard(),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, i) {
              final m = _messages[i];
              return _ChatBubble(message: m);
            },
          ),
        ),
        if (_sending)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.orange,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'AI myśli…',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _inputCtrl,
                  minLines: 1,
                  maxLines: 5,
                  enabled: !_sessionComplete,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: _sessionComplete
                        ? 'Sesja zakończona — odśwież, aby zacząć od nowa'
                        : 'Twoje obserwacje… (Enter — nowa linia)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: (_sending || _sessionComplete)
                      ? null
                      : _nextStep,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  label: const Text('Następny krok'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChecklistArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RepairHeaderBar(repair: _repair),
        _buildPhaseStrip(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Lista kontrolna: pozycje [Szablon] to sugerowana kolejność szyn; '
            'asystent dopisuje własne punkty.',
            style: TextStyle(color: Colors.grey, fontSize: 11, height: 1.3),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Lista kontrolna (asystent + sesja)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.orange,
            ),
          ),
        ),
        Expanded(
          child: _checklist.isEmpty
              ? const Center(
                  child: Text(
                    'Brak pozycji — użyj trybu czatu i „Następny krok”.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _checklist.length,
                  itemBuilder: (context, i) {
                    return Card(
                      color: const Color(0xFF252525),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Text(
                          '${i + 1}.',
                          style: const TextStyle(color: Colors.orange),
                        ),
                        title: Text(_checklist[i]),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPhaseStrip() {
    const phases = DiagnosticPhase.values;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 4),
            child: Text(
              'Etap diagnozy (wg odpowiedzi AI)',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in phases)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: p.hintPl,
                      child: Material(
                        color: p == _phase
                            ? Colors.orange.withValues(alpha: 0.22)
                            : const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(
                            p.labelPl,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: p == _phase
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: p == _phase
                                  ? Colors.orangeAccent
                                  : Colors.grey.shade400,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeasurementsQuickCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: _loading || _sending ? null : _openMeasurementsQuick,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.speed, color: Colors.orangeAccent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _measurementCount == 0
                        ? 'Pomiary — szybki zapis napięcia, rezystancji i prądu '
                            '(osobno od czatu; zalecane przy każdej szynie)'
                        : 'Pomiary: $_measurementCount wpisów — dotknij, by dodać kolejny',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: Colors.grey.shade500),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final DiagnosticChatMessage message;

  @override
  Widget build(BuildContext context) {
    final user = message.isUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: user ? const Color(0xFF3E2723) : const Color(0xFF2E2E2E),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(user ? 14 : 4),
            bottomRight: Radius.circular(user ? 4 : 14),
          ),
          border: Border.all(
            color: user ? Colors.orange.withValues(alpha: 0.35) : Colors.white12,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user ? 'Ty' : 'Asystent',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: user ? Colors.orangeAccent : Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            if (message.localImagePath != null)
              buildMicroscopeChatImage(message.localImagePath!),
            SelectableText(
              message.text,
              style: const TextStyle(height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepairHeaderBar extends StatelessWidget {
  const _RepairHeaderBar({required this.repair});

  final RepairProject repair;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF252525),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              repair.displayTitle,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            Text(
              'Board_ID: ${repair.boardId.isNotEmpty ? repair.boardId : '—'} · '
              '${repair.brand.isNotEmpty ? repair.brand : '—'} / '
              '${repair.modelName.isNotEmpty ? repair.modelName : '—'}',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 12,
              ),
            ),
            if (repair.hasDocumentationAttached) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (repair.documentationUrl != null &&
                      repair.documentationUrl!.trim().isNotEmpty)
                    'URL: ${repair.documentationUrl}',
                  if (repair.documentationLocalPath != null &&
                      repair.documentationLocalPath!.trim().isNotEmpty)
                    'Plik: ${repair.documentationLocalPath}',
                ].join('\n'),
                style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

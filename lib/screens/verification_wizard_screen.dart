import 'dart:async';

import 'package:flutter/material.dart';

import '../models/ai_board_research_result.dart';
import '../models/critical_chip_entry.dart';
import '../models/repair_project.dart';
import '../services/repair_data_service.dart';
import '../services/repair_storage.dart';
import 'diagnostic_dashboard_screen.dart';

class VerificationWizardScreen extends StatefulWidget {
  const VerificationWizardScreen({super.key});

  @override
  State<VerificationWizardScreen> createState() =>
      _VerificationWizardScreenState();
}

class _VerificationWizardScreenState extends State<VerificationWizardScreen> {
  int _step = 0;

  final _deviceCategoryCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _modelNameCtrl = TextEditingController();
  final _boardCodeCtrl = TextEditingController();
  final _chatCtrl = TextEditingController();
  final _manualPcbOverrideCtrl = TextEditingController();

  AiBoardResearchResult? _aiResearch;
  bool _aiLookupLoading = false;
  Timer? _lookupDebounce;

  DetectedBoard? _selectedBoard;
  final Map<String, String> _variantSelections = {};

  bool _identifyHelpOpen = false;
  final List<({String role, String text})> _chatMessages = [];

  bool _saving = false;

  final _hwPcbCodeCtrl = TextEditingController();
  final _hwCpuGenerationCtrl = TextEditingController();
  final _hwPcbFocusNode = FocusNode();

  bool _hwPcbSeen = false;
  String? _hwEthernetChoice;

  void _resetHardwareChecklist() {
    _hwPcbSeen = false;
    _hwEthernetChoice = null;
  }

  void _clearHardwareFinalFields() {
    _hwPcbCodeCtrl.clear();
    _hwCpuGenerationCtrl.clear();
    _resetHardwareChecklist();
  }

  /// Manual PCB field on board step (before hardware confirmation).
  String get _resolvedPcbCode {
    final m = _manualPcbOverrideCtrl.text.trim();
    if (m.isNotEmpty) return m;
    return _selectedBoard?.boardCode ?? '';
  }

  /// Final PCB silk-screen code for this repair: hardware step edits win.
  String get _finalPcbSilkScreen {
    final h = _hwPcbCodeCtrl.text.trim();
    if (h.isNotEmpty) return h;
    return _resolvedPcbCode;
  }

  DetectedBoard? get _effectiveBoard {
    final r = _aiResearch;
    if (r == null || r.detectedBoards.isEmpty) return null;
    final pcb = _finalPcbSilkScreen;
    if (pcb.isEmpty) return null;

    if (_manualPcbOverrideCtrl.text.trim().isEmpty &&
        _hwPcbCodeCtrl.text.trim().isEmpty &&
        _selectedBoard != null) {
      return _selectedBoard;
    }

    final base = _selectedBoard ?? r.detectedBoards.first;
    final slug = RepairDataService.slugifyBoardCode(pcb);
    final shortName = base.displayName.contains('(')
        ? base.displayName.substring(0, base.displayName.indexOf('(')).trim()
        : base.displayName.trim();
    return DetectedBoard(
      id: '${slug}_pcb_final',
      displayName: _selectedBoard != null
          ? '$pcb — $shortName'
          : '$pcb (manual PCB)',
      boardCode: pcb,
      identificationTip: base.identificationTip,
      variants: base.variants,
    );
  }

  void _clearAiState() {
    _aiResearch = null;
    _selectedBoard = null;
    _variantSelections.clear();
    _manualPcbOverrideCtrl.clear();
    _clearHardwareFinalFields();
  }

  Future<void> _openManualMode() async {
    final cat = _deviceCategoryCtrl.text.trim();
    final brand = _brandCtrl.text.trim();
    final model = _modelNameCtrl.text.trim();
    if (cat.isEmpty || brand.isEmpty || model.isEmpty) return;

    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text('Manual board entry'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Skip AI lookup. Enter the board ID from your unit; you can '
                  'continue to the interactive assistant after confirming variants.',
                  style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: idCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Board ID',
                    hintText: 'e.g. silkscreen / sticker code',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Label (optional)',
                    hintText: 'Friendly name for this board',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                if (idCtrl.text.trim().isEmpty) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Use this board'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      final result = RepairDataService.manualBoardResearch(
        deviceCategory: cat,
        brand: brand,
        modelName: model,
        boardIdRaw: idCtrl.text,
        displayNameOverride:
            nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
      );
      setState(() {
        _aiLookupLoading = false;
        _aiResearch = result;
        _selectedBoard = null;
        _variantSelections.clear();
        _manualPcbOverrideCtrl.clear();
        _clearHardwareFinalFields();
      });
    } on RepairDataException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      idCtrl.dispose();
      nameCtrl.dispose();
    }
  }

  Future<void> _runAiLookup({bool showBlockingDialog = false}) async {
    final cat = _deviceCategoryCtrl.text.trim();
    final brand = _brandCtrl.text.trim();
    final model = _modelNameCtrl.text.trim();
    if (cat.isEmpty || brand.isEmpty || model.isEmpty) return;

    if (showBlockingDialog && mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF2A2A2A),
            content: Row(
              children: [
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    'AI lookup…\n$cat · $brand · $model',
                    style: const TextStyle(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!showBlockingDialog) {
      setState(() => _aiLookupLoading = true);
    }

    try {
      final result = await RepairDataService.fetchBoardDataForDevice(
        deviceCategory: cat,
        brand: brand,
        modelName: model,
      );
      if (!mounted) return;
      setState(() {
        _aiResearch = result;
        _selectedBoard = null;
        _variantSelections.clear();
        _manualPcbOverrideCtrl.clear();
        _clearHardwareFinalFields();
        _aiLookupLoading = false;
      });
    } on RepairDataException catch (e) {
      if (mounted) {
        setState(() => _aiLookupLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _aiLookupLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Board lookup failed: $e')),
        );
      }
    } finally {
      if (showBlockingDialog && mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _scheduleAiLookup() {
    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(const Duration(milliseconds: 500), () async {
      final cat = _deviceCategoryCtrl.text.trim();
      final brand = _brandCtrl.text.trim();
      final model = _modelNameCtrl.text.trim();

      if (cat.isEmpty || brand.isEmpty || model.length < 3) {
        if (mounted) {
          setState(() {
            _aiLookupLoading = false;
            _clearAiState();
          });
        }
        return;
      }

      await _runAiLookup(showBlockingDialog: false);
    });
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _deviceCategoryCtrl.dispose();
    _brandCtrl.dispose();
    _modelNameCtrl.dispose();
    _boardCodeCtrl.dispose();
    _chatCtrl.dispose();
    _manualPcbOverrideCtrl.dispose();
    _hwPcbCodeCtrl.dispose();
    _hwCpuGenerationCtrl.dispose();
    _hwPcbFocusNode.dispose();
    super.dispose();
  }

  void _openIdentifyHelp() {
    setState(() {
      _identifyHelpOpen = true;
      if (_chatMessages.isEmpty) {
        _chatMessages.add((
          role: 'assistant',
          text:
              'Ask where to read the board ID on ${_effectiveBoard?.displayName ?? 'this board'} — '
              'I will point you to silkscreen vs sticker first.',
        ));
      }
    });
  }

  void _closeIdentifyHelp() {
    setState(() => _identifyHelpOpen = false);
  }

  void _sendChat() {
    final t = _chatCtrl.text.trim();
    if (t.isEmpty) return;
    _chatCtrl.clear();
    setState(() {
      _chatMessages.add((role: 'user', text: t));
      _chatMessages.add((role: 'assistant', text: _simulatedReply(t)));
    });
  }

  String _simulatedReply(String userText) {
    final lower = userText.toLowerCase();
    if (lower.contains('sticker') || lower.contains('ram')) {
      return 'Start with the white sticker near the RAM slots — compare the '
          'printed string to your selected board (${_effectiveBoard?.displayName ?? '…'}). '
          'Then confirm the same code appears in nearby silkscreen if present.';
    }
    if (lower.contains('lan') || lower.contains('intel') || lower.contains('realtek')) {
      return 'For LAN, inspect the PHY package near the RJ-45 jack: Intel and '
          'Realtek use different package outlines — match to your variant choice.';
    }
    return 'Use the visual aid area as a rough map: board IDs are often near '
        'RAM or along the board edge on this chassis family.';
  }

  bool get _step0Valid {
    return _deviceCategoryCtrl.text.trim().isNotEmpty &&
        _brandCtrl.text.trim().isNotEmpty &&
        _modelNameCtrl.text.trim().isNotEmpty;
  }

  bool get _step1Valid {
    final r = _aiResearch;
    if (r == null || r.detectedBoards.isEmpty) return false;
    if (_manualPcbOverrideCtrl.text.trim().isNotEmpty) return true;
    return _selectedBoard != null;
  }

  bool get _stepHardwareValid {
    return _hwPcbSeen &&
        _hwEthernetChoice != null &&
        _hwPcbCodeCtrl.text.trim().isNotEmpty &&
        _hwCpuGenerationCtrl.text.trim().isNotEmpty;
  }

  bool get _stepVariantValid {
    final board = _effectiveBoard;
    if (board == null) return false;
    for (final v in board.variants) {
      final c = _variantSelections[v.id];
      if (c == null || c.isEmpty) return false;
    }
    return true;
  }

  void _onStepContinue() {
    if (_step == 0 && !_step0Valid) return;
    if (_step == 1 && !_step1Valid) return;
    if (_step == 2 && !_stepHardwareValid) return;
    if (_step < 3) {
      setState(() {
        if (_step == 1) {
          _hwPcbCodeCtrl.text = _resolvedPcbCode;
        }
        _step += 1;
      });
    }
  }

  void _onStepCancel() {
    if (_step > 0) {
      setState(() => _step -= 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  List<CriticalChipEntry> _collectComponents() {
    final r = _aiResearch;
    final board = _effectiveBoard;
    final out = <CriticalChipEntry>[
      CriticalChipEntry(
        label: 'AI lookup summary',
        value: r?.summaryLine ?? '',
      ),
    ];
    if (board != null) {
      out.add(
        CriticalChipEntry(
          label: 'Selected board',
          value: board.displayName,
        ),
      );
      out.add(
        CriticalChipEntry(
          label: 'Board code (final)',
          value: _finalPcbSilkScreen,
        ),
      );
      out.add(
        CriticalChipEntry(
          label: 'CPU generation (final)',
          value: _hwCpuGenerationCtrl.text.trim(),
        ),
      );
      for (final v in board.variants) {
        final choice = _variantSelections[v.id];
        if (choice != null && choice.isNotEmpty) {
          out.add(CriticalChipEntry(label: v.title, value: choice));
        }
      }
      final cpuFinal = _hwCpuGenerationCtrl.text.trim();
      final pcbSaved = _finalPcbSilkScreen;
      final ethSaved = _hwEthernetChoice ?? '';
      out.add(
        CriticalChipEntry(
          label: 'Hardware confirmation',
          value:
              'PCB silk-screen verified: $pcbSaved; Ethernet PHY: $ethSaved; CPU: $cpuFinal',
        ),
      );
    }
    return out;
  }

  Future<void> _submit() async {
    if (!_step0Valid ||
        !_step1Valid ||
        !_stepHardwareValid ||
        !_stepVariantValid ||
        _saving) {
      return;
    }
    setState(() => _saving = true);

    final pcbFinal = _finalPcbSilkScreen;
    _boardCodeCtrl.text = pcbFinal;

    final project = RepairProject(
      id: RepairStorage.instance.newRepairId(),
      deviceCategory: _deviceCategoryCtrl.text.trim(),
      brand: _brandCtrl.text.trim(),
      modelName: _modelNameCtrl.text.trim(),
      boardModelCode: pcbFinal,
      components: _collectComponents(),
      createdAt: DateTime.now(),
    );

    await RepairStorage.instance.saveRepair(project);
    if (!mounted) return;
    setState(() => _saving = false);

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => DiagnosticDashboardScreen(repair: project),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('New repair · step ${_step + 1} of 4'),
        backgroundColor: const Color(0xFF1F1F1F),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: List.generate(4, (i) {
                final active = i <= _step;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: active ? 1 : 0,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade800,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: Stepper(
              type: StepperType.vertical,
              currentStep: _step,
              onStepTapped: (index) {
                if (index < _step) {
                  setState(() => _step = index);
                } else if (index == _step + 1) {
                  _onStepContinue();
                }
              },
              onStepContinue: _onStepContinue,
              onStepCancel: _onStepCancel,
              controlsBuilder: (context, details) {
                final isLast = _step == 3;
                final canContinue = switch (_step) {
                  0 => _step0Valid && _aiResearch != null && !_aiLookupLoading,
                  1 => _step1Valid,
                  2 => _stepHardwareValid,
                  _ => _stepVariantValid,
                };
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      if (isLast)
                        FilledButton(
                          onPressed: (_stepVariantValid && !_saving)
                              ? _submit
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Create repair & open assistant',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        )
                      else if (_step == 2)
                        FilledButton(
                          onPressed:
                              canContinue ? details.onStepContinue : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Start Project'),
                        )
                      else
                        FilledButton(
                          onPressed:
                              canContinue ? details.onStepContinue : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Continue'),
                        ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: Text(_step == 0 ? 'Cancel' : 'Back'),
                      ),
                    ],
                  ),
                );
              },
              steps: [
                Step(
                  title: const Text('Model entry'),
                  subtitle: const Text('AI lookup runs after you enter the model'),
                  isActive: _step >= 0,
                  state: _step > 0 ? StepState.complete : StepState.indexed,
                  content: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Enter device context. When the model name is complete, '
                            'an AI lookup loads detected boards automatically.',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _deviceCategoryCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Urządzenie / kategoria',
                              hintText: 'np. konsola, sterownik, sprzęt RTV',
                              border: OutlineInputBorder(),
                            ),
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) {
                              setState(() {});
                              _scheduleAiLookup();
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _brandCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Brand',
                              hintText: 'e.g. HP',
                              border: OutlineInputBorder(),
                            ),
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) {
                              setState(() {});
                              _scheduleAiLookup();
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _modelNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Model urządzenia',
                              hintText: 'np. nazwa handlowa lub platformy',
                              border: OutlineInputBorder(),
                            ),
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) {
                              setState(() {});
                              _scheduleAiLookup();
                            },
                            onEditingComplete: () {
                              if (_step0Valid) _scheduleAiLookup();
                            },
                          ),
                          if (_aiLookupLoading) ...[
                            const SizedBox(height: 20),
                            const Row(
                              children: [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.orange,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'AI is researching boards for this model…',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (!_aiLookupLoading && _aiResearch != null) ...[
                            const SizedBox(height: 20),
                            Card(
                              color: const Color(0xFF2C2C2C),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.smart_toy_outlined,
                                          color: Colors.orange,
                                          size: 22,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'AI lookup complete',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _aiResearch!.summaryLine,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        height: 1.35,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${_aiResearch!.detectedBoards.length} '
                                      'board(s) detected — next step: choose the '
                                      'board that matches your unit.',
                                      style: const TextStyle(
                                        color: Colors.orangeAccent,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (!_aiLookupLoading &&
                              _step0Valid &&
                              _modelNameCtrl.text.trim().length >= 3 &&
                              _aiResearch == null)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'Waiting for AI lookup…',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _step0Valid
                                ? () => _runAiLookup(showBlockingDialog: true)
                                : null,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh AI lookup'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _step0Valid ? _openManualMode : null,
                            icon: const Icon(Icons.edit_note),
                            label: const Text('Manual Mode'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Step(
                  title: const Text('Board selection'),
                  subtitle: const Text('Pick the board that matches your unit'),
                  isActive: _step >= 1,
                  state: _step > 1 ? StepState.complete : StepState.indexed,
                  content: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: _buildBoardSelectionContent(),
                    ),
                  ),
                ),
                Step(
                  title: const Text('Hardware Confirmation'),
                  subtitle: const Text('Step 3: verify PCB before continuing'),
                  isActive: _step >= 2,
                  state: _step > 2 ? StepState.complete : StepState.indexed,
                  content: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: _buildHardwareConfirmationBody(),
                    ),
                  ),
                ),
                Step(
                  title: const Text('Variant confirmation'),
                  subtitle: const Text('Confirm options, then create the repair'),
                  isActive: _step >= 3,
                  state: StepState.indexed,
                  content: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      height: _identifyHelpOpen ? 480 : null,
                      child: _identifyHelpOpen
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: SingleChildScrollView(
                                    child: _buildVariantConfirmationBody(),
                                  ),
                                ),
                                const VerticalDivider(width: 1),
                                Expanded(
                                  flex: 4,
                                  child: _IdentifyHelpChat(
                                    messages: _chatMessages,
                                    inputController: _chatCtrl,
                                    onSend: _sendChat,
                                    onClose: _closeIdentifyHelp,
                                  ),
                                ),
                              ],
                            )
                          : ListView(
                              shrinkWrap: true,
                              physics: const ClampingScrollPhysics(),
                              children: [
                                _buildVariantConfirmationBody(),
                              ],
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

  Widget _buildBoardSelectionContent() {
    final r = _aiResearch;
    if (r == null) {
      return const Text(
        'Complete Step 1 and wait for AI lookup to finish.',
        style: TextStyle(color: Colors.grey),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Detected boards for this model',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          r.summaryLine,
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 16),
        ...r.detectedBoards.map(_buildDetectedBoardCard),
        const SizedBox(height: 20),
        const Text(
          'None of these? Enter PCB code manually',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _manualPcbOverrideCtrl,
          decoration: const InputDecoration(
            labelText: 'PCB silk-screen code (overrides card selection)',
            hintText: 'e.g. 6050A2860101-MB-A01',
            border: OutlineInputBorder(),
            helperText: 'If set, this code is used as the board ID for the repair.',
          ),
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) {
            setState(() {
              _hwPcbCodeCtrl.clear();
              _hwCpuGenerationCtrl.clear();
              _resetHardwareChecklist();
            });
          },
        ),
      ],
    );
  }

  Widget _buildHardwareConfirmationBody() {
    if (_resolvedPcbCode.isEmpty) {
      return const Text(
        'Go back and select or enter a PCB code first.',
        style: TextStyle(color: Colors.grey),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Step 3: Hardware Confirmation',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Edit any value below if the AI was wrong — these become the final '
          'record for this repair.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 16),
        const Text(
          'PCB silk-screen code (saved as board ID)',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _hwPcbCodeCtrl,
          focusNode: _hwPcbFocusNode,
          decoration: InputDecoration(
            hintText: 'e.g. 6050A2860101-mb-a01',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Edit PCB code',
              icon: const Icon(Icons.edit),
              onPressed: () {
                _hwPcbFocusNode.requestFocus();
              },
            ),
          ),
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _hwPcbSeen,
          onChanged: (v) {
            setState(() => _hwPcbSeen = v ?? false);
          },
          title: const Text(
            'I see the code in the field above printed on the PCB.',
          ),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),
        const Text(
          'The board has an Ethernet PHY — select which matches your unit:',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              ['Intel', 'Realtek'].map((label) {
            final selected = _hwEthernetChoice == label;
            return ChoiceChip(
              label: Text(label),
              selected: selected,
              selectedColor: Colors.orange.withValues(alpha: 0.35),
              checkmarkColor: Colors.orange,
              labelStyle: TextStyle(
                color: selected ? Colors.white : Colors.grey.shade300,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
              onSelected: (_) {
                setState(() => _hwEthernetChoice = label);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        const Text(
          'CPU generation',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _hwCpuGenerationCtrl,
          decoration: const InputDecoration(
            hintText: 'e.g. i5 6th Gen — change to i3 6th Gen if that is what you see',
            border: OutlineInputBorder(),
            helperText:
                'Type the exact CPU generation you confirm on the unit; overrides any AI guess.',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        if (!_stepHardwareValid)
          const Text(
            'Fill PCB code and CPU, confirm the checkbox, pick Ethernet, '
            'then “Start Project” unlocks.',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
          ),
      ],
    );
  }

  Widget _buildDetectedBoardCard(DetectedBoard board) {
    final selected = _selectedBoard?.id == board.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _selectedBoard = board;
              _variantSelections.clear();
              _boardCodeCtrl.text = board.boardCode;
              _hwPcbCodeCtrl.clear();
              _hwCpuGenerationCtrl.clear();
              _resetHardwareChecklist();
            });
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? Colors.orange : Colors.white12,
                width: selected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      selected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: selected ? Colors.orange : Colors.grey,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        board.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: selected ? Colors.white : Colors.grey.shade200,
                        ),
                      ),
                    ),
                    if (selected)
                      const Text(
                        'SELECTED',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 18,
                      color: Colors.amber.shade200,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        board.identificationTip,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVariantConfirmationBody() {
    final r = _aiResearch;
    final board = _effectiveBoard;
    if (r == null || board == null) {
      return const Text(
        'Select or enter a board in the previous steps first.',
        style: TextStyle(color: Colors.grey),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Board: ${board.displayName}',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Code: ${board.boardCode}',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        const Text(
          'Confirm variants',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        ...board.variants.map(_buildVariantQuestion),
        const SizedBox(height: 20),
        const Text(
          'Visual aid — board ID location',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        _buildBoardIdPlaceholder(r),
        const SizedBox(height: 16),
        if (!_stepVariantValid)
          const Text(
            'Answer each question above to enable “Create repair”.',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openIdentifyHelp,
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('I don\'t know, help me identify'),
        ),
        if (_identifyHelpOpen) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _closeIdentifyHelp,
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Hide assistant'),
          ),
        ],
      ],
    );
  }

  Widget _buildVariantQuestion(AiCriticalVariant v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        color: const Color(0xFF252525),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                v.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                v.label,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: v.options.map((opt) {
                  final selected = _variantSelections[v.id] == opt;
                  return ChoiceChip(
                    label: Text(opt),
                    selected: selected,
                    selectedColor: Colors.orange.withValues(alpha: 0.35),
                    checkmarkColor: Colors.orange,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : Colors.grey.shade300,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    onSelected: (_) {
                      setState(() => _variantSelections[v.id] = opt);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBoardIdPlaceholder(AiBoardResearchResult r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Icon(
            Icons.photo_camera_outlined,
            size: 42,
            color: Colors.grey.shade600,
          ),
          const SizedBox(height: 8),
          Text(
            r.visualAidCaption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            r.boardIdLocationHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF151515),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Center(
              child: Text(
                'Image placeholder\n(board photo / diagram for this model)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentifyHelpChat extends StatelessWidget {
  const _IdentifyHelpChat({
    required this.messages,
    required this.inputController,
    required this.onSend,
    required this.onClose,
  });

  final List<({String role, String text})> messages;
  final TextEditingController inputController;
  final VoidCallback onSend;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A1A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
            child: Row(
              children: [
                const Icon(Icons.smart_toy_outlined, color: Colors.orange),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Identify assistant',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (context, i) {
                final m = messages[i];
                final isUser = m.role == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    constraints: const BoxConstraints(maxWidth: 280),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Colors.orange.shade900
                          : const Color(0xFF2E2E2E),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      m.text,
                      style: const TextStyle(height: 1.35),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: inputController,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Ask what to check…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: onSend,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

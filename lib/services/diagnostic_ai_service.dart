import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../models/diagnostic_profile.dart';
import '../models/repair_project.dart';
import 'diagnostic_templates.dart';
import 'repair_data_service.dart';

/// Loads a [DiagnosticProfile] from Groq, or falls back to generic templates.
abstract final class DiagnosticAiService {
  static const String _groqChatCompletionsUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  /// Fetches AI diagnostics for [repair], or returns a category template if API fails.
  static Future<DiagnosticProfile> loadProfileForRepair(RepairProject repair) async {
    final key = RepairDataService.resolveGroqApiKey();
    if (key.isEmpty) {
      debugPrint('=== DiagnosticAiService: no GROQ_API_KEY — generic template ===');
      return DiagnosticTemplates.forDeviceCategory(repair.deviceCategory).copyWith(
        source: DiagnosticProfileSource.noApiKey,
      );
    }

    final uri = Uri.parse(_groqChatCompletionsUrl);
    final boardId = repair.boardModelCode.trim();
    final model = repair.modelName.trim();
    final brand = repair.brand.trim();
    final cat = repair.deviceCategory.trim();

    final prompt = '''
You are an expert board-level repair diagnostician. The technician confirmed a PCB and device — propose a measurement and bring-up plan.

Return ONE JSON object only (no markdown). Use exactly these keys:

- "main_power_rails": array of 4 to 6 objects. Each object MUST have "name" (net/signal to probe — use schematic rail names), "description" (one short sentence what it feeds), optional "measurement_hint" (expected V range, diode expectation, or Ω check — not guesses for unknown boards).

- "common_faults": array of 3 to 5 short strings: typical failure modes for THIS architecture (not generic marketing fluff).

- "startup_sequence": array of 3 to 5 objects in order, each with "signal" (name) and "description" (what to verify and why).

- "confidence": string: "high" | "medium" | "low" — how specific you are to this exact board ID.

Context (use all of it):
- device_category: $cat
- brand: $brand
- model: $model
- confirmed_board_id (PCB silk-screen / manufacturer code): $boardId

If the board ID is unfamiliar, still pick rails appropriate for device_category (embedded/PCB vs phone vs tablet) and set confidence to "low". Do not invent fake vendor-specific net names. For larger embedded/mainboard-class PCBs use typical naming (standby 3V3, input VIN, core bucks, memory rails); for phones use PMIC/VBAT/VDD_MAIN style naming.
''';

    final body = {
      'model': 'llama-3.3-70b-versatile',
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'response_format': {'type': 'json_object'},
    };

    try {
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '=== DiagnosticAiService: HTTP ${response.statusCode} ===\n${response.body}',
        );
        return _fallback(repair, DiagnosticProfileSource.groqFallback);
      }

      final outer = jsonDecode(response.body) as Map<String, dynamic>;
      if (outer['error'] != null) {
        debugPrint('=== DiagnosticAiService: error field: ${outer['error']} ===');
        return _fallback(repair, DiagnosticProfileSource.groqFallback);
      }

      final choices = outer['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        return _fallback(repair, DiagnosticProfileSource.groqFallback);
      }

      final msg =
          (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      final raw = msg?['content'];
      final text = raw is String ? raw : raw?.toString();
      if (text == null || text.trim().isEmpty) {
        return _fallback(repair, DiagnosticProfileSource.groqFallback);
      }

      final cleaned = RepairDataService.cleanJsonFenceTags(text.trim());
      final decoded = jsonDecode(cleaned) as Map<String, dynamic>;
      final profile = _parseProfile(decoded, DiagnosticProfileSource.groq);

      if (profile.mainPowerRails.isEmpty ||
          profile.startupSequence.isEmpty) {
        return _fallback(repair, DiagnosticProfileSource.groqFallback);
      }

      return profile;
    } catch (e, st) {
      debugPrint('=== DiagnosticAiService: $e ===\n$st');
      return _fallback(repair, DiagnosticProfileSource.groqFallback);
    }
  }

  static DiagnosticProfile _fallback(
    RepairProject repair,
    DiagnosticProfileSource source,
  ) {
    return DiagnosticTemplates.forDeviceCategory(repair.deviceCategory).copyWith(
      source: source,
    );
  }

  static DiagnosticProfile _parseProfile(
    Map<String, dynamic> json,
    DiagnosticProfileSource source,
  ) {
    final railsRaw = json['main_power_rails'] as List<dynamic>? ?? [];
    final faultsRaw = json['common_faults'] as List<dynamic>? ?? [];
    final seqRaw = json['startup_sequence'] as List<dynamic>? ?? [];
    final conf = json['confidence']?.toString() ?? 'medium';

    final rails = <MainPowerRail>[];
    for (final e in railsRaw) {
      if (e is String) {
        rails.add(MainPowerRail(name: e.trim()));
      } else if (e is Map) {
        final m = Map<String, dynamic>.from(e);
        final name = (m['name'] ?? m['label'] ?? m['rail'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        rails.add(
          MainPowerRail(
            name: name,
            description: (m['description'] ?? m['notes'] ?? '').toString().trim(),
            measurementHint: _optionalString(m['measurement_hint'] ?? m['expected']),
          ),
        );
      }
    }

    final faults = <String>[];
    for (final e in faultsRaw) {
      final s = e.toString().trim();
      if (s.isNotEmpty) faults.add(s);
    }

    final steps = <StartupStep>[];
    for (final e in seqRaw) {
      if (e is String) {
        steps.add(StartupStep(signal: e.trim()));
      } else if (e is Map) {
        final m = Map<String, dynamic>.from(e);
        final sig = (m['signal'] ?? m['name'] ?? m['step'] ?? '').toString().trim();
        if (sig.isEmpty) continue;
        steps.add(
          StartupStep(
            signal: sig,
            description:
                (m['description'] ?? m['detail'] ?? '').toString().trim(),
          ),
        );
      }
    }

    return DiagnosticProfile(
      mainPowerRails: rails,
      commonFaults: faults,
      startupSequence: steps,
      confidence: conf,
      source: source,
    );
  }

  static String? _optionalString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

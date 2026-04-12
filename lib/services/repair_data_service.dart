import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/ai_board_research_result.dart';
import 'repair_storage.dart';

/// Thrown when Groq returns an error or JSON cannot be mapped.
class RepairDataException implements Exception {
  RepairDataException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Board identification: `package:http` POST to Groq OpenAI-compatible API.
class RepairDataService {
  RepairDataService._();

  /// Zmień przy istotnej zmianie promptu / formatu `variants`, żeby odświeżyć cache SQLite.
  static const String _boardLookupPromptVersion = 'v3';

  static const String _groqChatCompletionsUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  /// Loads motherboard candidates from Groq for the given device context.
  /// Same normalized model + local calendar day uses SQLite cache.
  static Future<AiBoardResearchResult> fetchBoardDataForDevice({
    required String deviceCategory,
    required String brand,
    required String modelName,
  }) async {
    final device = deviceCategory.trim();
    final b = brand.trim();
    final m = modelName.trim();
    final combined = '$device $b $m'.trim();
    if (combined.isEmpty) {
      throw RepairDataException('Device, brand, and model are required.');
    }

    final modelKey = '${normalizeModelKey(combined)}|$_boardLookupPromptVersion';
    final today = _todayLocalDateString();
    final cached = await RepairStorage.instance.getBoardLookupCache(
      modelKey,
      today,
    );
    if (cached != null) {
      return cached;
    }

    final apiKey = resolveGroqApiKey();
    if (apiKey.isEmpty) {
      throw RepairDataException(
        'Missing GROQ_API_KEY. Set it in assets/env/gemini.env or run with '
        '--dart-define=GROQ_API_KEY=your_key',
      );
    }

    final uri = Uri.parse(_groqChatCompletionsUrl);

    // ignore: avoid_print
    print('DEBUG URL: $_groqChatCompletionsUrl');

    final userContent = '''
You are a board-level repair technician. I need the PCB model code printed directly on the silk-screen — not retail FRU/SKU unless that is the silk-screen code. Focus on OEM/ODM manufacturer codes (Inventec, Quanta, Foxconn, etc.).

You must be factually accurate. 6050A codes are Inventec-class projects. DA0 codes are Quanta-class. Prioritize the exact silk-screen code in board_id; do not invent whimsical project nicknames. board_name: only if you are confident; else neutral PCB-family wording.

Device context: $device $b $m.

Manufacturer patterns (examples — any OEM/ODM): 6050A…, DA0…, 820-XXXX on silk-screen.

Respond with JSON only (json_object). Include an array of boards (e.g. under "boards"). Each item MUST have:
- board_id: exact silk-screen / manufacturer PCB code (real codes for this model, not placeholders).
- board_name: internal platform name if known, else short neutral label.
- id_location: where the code is usually printed on the PCB.

CRITICAL — "variants" for the repair wizard UI (technicians are NOT engineers; all user-facing text in POLISH):
- variants MUST be an ARRAY OF OBJECTS (not bare strings like "UMA" or "DIS").
- Each object MUST have:
  - "question": one clear Polish question (what must the user decide?) e.g. "Jaki procesor jest na tej płycie w Twoim egzemplarzu?" or "Jaka jest konfiguracja grafiki?".
  - "hint": optional Polish sentence — WHERE to look (silkscreen near CPU socket, sticker, area next to GPU/heatsink, etc.).
  - "options": array of 2–6 Polish choices the user taps — FULL PHRASES, not abbreviations alone.
    Examples of GOOD options: "Intel Core i3 (szósta generacja)", "Intel Core i5 (szósta generacja)", "Inny CPU / nie wiem".
    For graphics: use plain Polish like "Tylko grafika w procesorze (bez osobnego układu GPU)" vs "Jest osobny chip graficzny (np. obok procesora)" vs "Nie wiem — sprawdzę na płycie".
    NEVER output options that are only "UMA" or "DIS" without explaining meaning.
- Include separate questions when both CPU tier AND graphics type differ between revisions for this board_id. Skip irrelevant questions for this device category.

Raw JSON only, no markdown.''';

    final body = {
      'model': 'llama-3.3-70b-versatile',
      'messages': [
        {
          'role': 'user',
          'content': userContent,
        },
      ],
      'response_format': {'type': 'json_object'},
    };

    http.Response response;
    try {
      response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
    } catch (e, stack) {
      debugPrint('=== RepairDataService: http.post threw (no response body) ===');
      debugPrint('$e');
      debugPrint('$stack');
      throw RepairDataException('Network error calling Groq: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _printExactResponseBody('HTTP ${response.statusCode}', response);
      throw RepairDataException(
        'Groq HTTP ${response.statusCode}. See console for full response body.',
      );
    }

    Map<String, dynamic> outer;
    try {
      outer = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      _printExactResponseBody('jsonDecode(response.body) failed', response);
      throw RepairDataException('Response was not JSON: $e');
    }

    if (outer['error'] != null) {
      _printExactResponseBody('API returned error field', response);
      throw RepairDataException('Groq API error: ${outer['error']}');
    }

    final choices = outer['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      _printExactResponseBody('no choices', response);
      throw RepairDataException('Groq returned no choices.');
    }

    final message =
        (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
    final contentRaw = message?['content'];
    final text = contentRaw is String ? contentRaw : contentRaw?.toString();
    if (text == null || text.trim().isEmpty) {
      _printExactResponseBody('empty assistant content', response);
      throw RepairDataException('Groq returned empty message content.');
    }

    AiBoardResearchResult parsed;
    try {
      parsed = _parseModelJsonToCards(
        text,
        summaryFallback: '$b $m — motherboard candidates',
      );
    } catch (e) {
      debugPrint('=== RepairDataService: model text parse failed; raw text below ===');
      debugPrint(text);
      debugPrint('=== parse error: $e ===');
      rethrow;
    }

    await RepairStorage.instance.saveBoardLookupCache(
      modelKey,
      today,
      parsed,
    );
    return parsed;
  }

  /// Prints the **exact** HTTP response body for debugging.
  static void _printExactResponseBody(String reason, http.Response response) {
    debugPrint('=== RepairDataService FAILURE ($reason) — EXACT response.body ===');
    debugPrint(response.body);
    debugPrint('=== END response.body (length=${response.body.length}) ===');
  }

  /// Stable id slug for a PCB code (e.g. UI / override ids).
  static String slugifyBoardCode(String rawBoardId) {
    return _safeId(rawBoardId, 'board', 0);
  }

  /// Skip the API: one detected board from a user-entered board ID (Manual Mode).
  static AiBoardResearchResult manualBoardResearch({
    required String deviceCategory,
    required String brand,
    required String modelName,
    required String boardIdRaw,
    String? displayNameOverride,
  }) {
    final boardId = boardIdRaw.trim();
    if (boardId.isEmpty) {
      throw RepairDataException('Board ID is required.');
    }
    final slug = _safeId(boardId, 'manual', 0);
    final label = displayNameOverride?.trim();
    final displayName = (label != null && label.isNotEmpty)
        ? '$label ($boardId)'
        : '$boardId (manual)';
    final board = DetectedBoard(
      id: slug,
      displayName: displayName,
      boardCode: boardId,
      identificationTip:
          'Entered manually — verify this code on silkscreen or service sticker.',
      variants: [
        AiCriticalVariant(
          id: '${slug}_confirm',
          title: 'Dopasowanie płyty',
          label: 'Czy ten Board ID zgadza się z kodem na Twoim laminacie?',
          options: ['Tak', 'Nie / nie jestem pewien'],
        ),
      ],
    );
    return AiBoardResearchResult(
      summaryLine:
          '${brand.trim()} ${modelName.trim()} — manual board entry',
      visualAidCaption: 'Board ID — verify on physical board',
      boardIdLocationHint: board.identificationTip,
      detectedBoards: [board],
    );
  }

  /// Stable cache key: lowercase, trimmed, single spaces.
  static String normalizeModelKey(String model) {
    return model
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _todayLocalDateString() {
    final n = DateTime.now();
    final y = n.year.toString().padLeft(4, '0');
    final mo = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '$y-$mo-$d';
  }

  /// Groq API key from `--dart-define` or `GROQ_API_KEY` in dotenv.
  static String resolveGroqApiKey() {
    final fromDefine = ApiConfig.groqApiKeyFromDefine.trim();
    if (fromDefine.isNotEmpty) return fromDefine;
    final fromEnv = dotenv.env['GROQ_API_KEY']?.trim() ?? '';
    return fromEnv;
  }

  /// Removes ```json / ``` fence wrappers if the model adds them, before [jsonDecode].
  static String cleanJsonFenceTags(String s) {
    var t = s.trim();
    for (var i = 0; i < 8; i++) {
      if (!t.startsWith('```')) break;
      t = t.replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
      final end = t.lastIndexOf('```');
      if (end != -1) {
        t = t.substring(0, end).trim();
      } else {
        break;
      }
    }
    return t.trim();
  }

  /// Maps model JSON text → [AiBoardResearchResult] / Step 2 cards.
  static AiBoardResearchResult _parseModelJsonToCards(
    String raw, {
    required String summaryFallback,
  }) {
    final sanitized = cleanJsonFenceTags(raw.trim());
    final extracted = _extractJsonPayload(sanitized);
    final forDecode = cleanJsonFenceTags(extracted);
    dynamic decoded;
    try {
      decoded = jsonDecode(forDecode);
    } catch (e) {
      throw RepairDataException(
        'Could not decode JSON from model: $e',
      );
    }

    List<dynamic> boardList;
    if (decoded is List<dynamic>) {
      boardList = decoded;
    } else if (decoded is Map<String, dynamic>) {
      if (decoded['boards'] is List<dynamic>) {
        boardList = decoded['boards'] as List<dynamic>;
      } else if (decoded['board_id'] != null || decoded['board_name'] != null) {
        boardList = [decoded];
      } else {
        List<dynamic>? anyList;
        for (final v in decoded.values) {
          if (v is List<dynamic>) {
            anyList = v;
            break;
          }
        }
        if (anyList != null) {
          boardList = anyList;
        } else {
          throw RepairDataException(
            'Expected JSON array of boards or board-shaped object; keys: '
            '${decoded.keys.join(", ")}',
          );
        }
      }
    } else {
      throw RepairDataException('Expected JSON array or object.');
    }

    if (boardList.isEmpty) {
      throw RepairDataException('AI returned an empty board list.');
    }

    final detected = <DetectedBoard>[];
    String? firstLocation;

    for (var i = 0; i < boardList.length; i++) {
      final item = boardList[i];
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);

      final boardId = _readString(map, const ['board_id', 'boardId', 'id']);
      final boardName = _readString(map, const ['board_name', 'boardName', 'name']);
      final idLocation = _readString(map, const ['id_location', 'idLocation', 'location']);

      if (boardId == null ||
          boardId.isEmpty ||
          boardName == null ||
          boardName.isEmpty) {
        continue;
      }

      firstLocation ??= idLocation;

      final slug = _safeId(boardId, 'board', i);
      final displayName = '$boardName ($boardId)';
      var variants = _parseVariantsField(slug, map['variants']);

      if (variants.isEmpty) {
        variants.add(
          AiCriticalVariant(
            id: '${slug}_confirm',
            title: 'Dopasowanie płyty',
            label: 'Czy ta karta odpowiada Twojej fizycznej płycie (kod laminatu / rewizja)?',
            options: ['Tak', 'Nie / nie jestem pewien'],
          ),
        );
      }

      detected.add(
        DetectedBoard(
          id: slug,
          displayName: displayName,
          boardCode: boardId,
          identificationTip: idLocation ??
              'Locate board number on silkscreen or service sticker per documentation.',
          variants: variants,
        ),
      );
    }

    if (detected.isEmpty) {
      throw RepairDataException(
        'No valid boards (need board_id and board_name per item).',
      );
    }

    return AiBoardResearchResult(
      summaryLine: summaryFallback,
      visualAidCaption: 'Board ID — typical location for this family',
      boardIdLocationHint: firstLocation ?? detected.first.identificationTip,
      detectedBoards: detected,
    );
  }

  /// Nowy format: lista obiektów {question, hint, options[]} po polsku; stary: stringi lub "A vs B".
  static List<AiCriticalVariant> _parseVariantsField(
    String boardSlug,
    dynamic raw,
  ) {
    if (raw == null) return [];
    if (raw is String && raw.trim().isNotEmpty) {
      return _chipStringsToVariants(boardSlug, [raw]);
    }
    if (raw is! List) return [];

    final out = <AiCriticalVariant>[];
    final list = raw;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e is Map) {
        final v = _structuredVariantFromMap(
          boardSlug,
          i,
          Map<String, dynamic>.from(e),
        );
        if (v != null) out.add(v);
      } else {
        final s = e?.toString().trim() ?? '';
        if (s.isNotEmpty) {
          out.addAll(_chipStringsToVariants('${boardSlug}_s$i', [s]));
        }
      }
    }
    return out;
  }

  static AiCriticalVariant? _structuredVariantFromMap(
    String boardSlug,
    int index,
    Map<String, dynamic> m,
  ) {
    final q = _readString(m, const [
      'question',
      'question_pl',
      'pytanie',
      'title',
    ]);
    if (q == null || q.isEmpty) return null;

    final hint = _readString(m, const [
      'hint',
      'help',
      'podpowiedz',
      'opis',
      'label',
      'description',
    ]);

    final optsRaw = m['options'];
    final options = <String>[];
    if (optsRaw is List) {
      for (final o in optsRaw) {
        final t = o?.toString().trim() ?? '';
        if (t.isNotEmpty) options.add(t);
      }
    }
    if (options.length < 2) {
      options
        ..clear()
        ..add('Tak — pasuje do mojego egzemplarza')
        ..add('Nie / inaczej / nie wiem');
    }

    final id = _readString(m, const ['id', 'key']) ?? '${boardSlug}_q_$index';

    return AiCriticalVariant(
      id: id,
      title: q,
      label: (hint != null && hint.isNotEmpty)
          ? hint
          : 'Wybierz opcję zgodną z tym, co widzisz na płycie, naklejkach lub w dokumentacji.',
      options: options,
    );
  }

  /// Legacy: każdy string → wariant (split na " vs " → dwie opcje).
  static List<AiCriticalVariant> _chipStringsToVariants(
    String boardSlug,
    List<String> chips,
  ) {
    final out = <AiCriticalVariant>[];
    for (var i = 0; i < chips.length; i++) {
      final s = chips[i].trim();
      if (s.isEmpty) continue;

      final vsSplit = s.split(RegExp(r'\s+vs\s+', caseSensitive: false));
      if (vsSplit.length >= 2) {
        final a = vsSplit.first.trim();
        final rest = vsSplit.sublist(1).join(' vs ').trim();
        out.add(
          AiCriticalVariant(
            id: '${boardSlug}_chip_$i',
            title: 'Wybór ${i + 1}',
            label: s,
            options: [a, rest],
          ),
        );
      } else {
        out.add(
          AiCriticalVariant(
            id: '${boardSlug}_chip_$i',
            title: 'Oznaczenie ${i + 1}',
            label:
                'Na płycie / w opisie występuje: „$s” — czy u Ciebie tak jest?',
            options: ['Tak, pasuje', 'Nie / u mnie inaczej'],
          ),
        );
      }
    }
    return out;
  }

  static String? _readString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null) {
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return null;
  }

  static String _extractJsonPayload(String raw) {
    var s = raw.trim();
    s = _stripMarkdownFence(s);

    final arrOpen = s.indexOf('[');
    final objOpen = s.indexOf('{');
    if (arrOpen != -1 && (objOpen == -1 || arrOpen < objOpen)) {
      final close = _matchingBracket(s, arrOpen, '[', ']');
      if (close != -1) return s.substring(arrOpen, close + 1);
    }
    if (objOpen != -1) {
      final close = _matchingBracket(s, objOpen, '{', '}');
      if (close != -1) return s.substring(objOpen, close + 1);
    }

    return s;
  }

  static int _matchingBracket(String s, int openIdx, String open, String close) {
    if (openIdx < 0 || openIdx >= s.length) return -1;
    var depth = 0;
    final o = open.codeUnitAt(0);
    final c = close.codeUnitAt(0);
    for (var i = openIdx; i < s.length; i++) {
      final ch = s.codeUnitAt(i);
      if (ch == o) {
        depth++;
      } else if (ch == c) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static String _stripMarkdownFence(String s) {
    var t = s.trim();
    if (!t.startsWith('```')) return t;
    t = t.replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '');
    t = t.replaceFirst(RegExp(r'\s*```\s*$'), '');
    return t.trim();
  }

  static String _safeId(String rawBoardId, String prefix, int index) {
    final t = rawBoardId.trim();
    final slug = t
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isNotEmpty) return slug;
    return '${prefix}_$index';
  }
}

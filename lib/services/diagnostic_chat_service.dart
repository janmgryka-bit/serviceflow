import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../models/diagnostic_chat_message.dart';
import '../models/repair_project.dart';
import 'diagnostic_image_loader.dart';
import 'repair_data_service.dart';

/// One turn from Groq (JSON object mode).
class DiagnosticChatTurn {
  const DiagnosticChatTurn({
    required this.nextQuestion,
    required this.technicalPreview,
    required this.checklistAdd,
    required this.sessionComplete,
    required this.showTechnicalDrawer,
  });

  final String nextQuestion;
  final String technicalPreview;
  final List<String> checklistAdd;
  final bool sessionComplete;

  /// When true, UI should open the technical [Drawer] (pinouts, locations, steps).
  final bool showTechnicalDrawer;
}

/// Multi-turn Groq chat — dynamic, Polish-only assistant text; vision when microscope photos are present.
abstract final class DiagnosticChatService {
  static const String _url =
      'https://api.groq.com/openai/v1/chat/completions';

  static const String _textModel = 'llama-3.3-70b-versatile';

  /// Groq multimodal (vision + JSON mode supported).
  static const String _visionModel =
      'meta-llama/llama-4-scout-17b-16e-instruct';

  /// Shown in chat and sent to the model with the JPEG (English, per product spec).
  static const String kMicroscopeAnalysisPrompt =
      'User just sent a microscope photo of the PCB. Analyze the components near the missing pads.';

  /// Podgląd na żywo z panelu bocznego — dowód wizualny dla bieżącego kroku (polski + treść dla modelu).
  static const String kVisualEvidencePrompt =
      '[Dowód wizualny] Przesłano klatkę z podglądu kamery na żywo. '
      'Przeanalizuj obraz jako dowód wizualny dla bieżącego kroku naprawy: widoczne elementy, pady, stan obwodu, zgodność z wcześniejszą rozmową. '
      'Odpowiedź w polsku w polach JSON.';

  /// Sent only on the wire — not shown in the chat UI. Ensures Board ID reaches Groq every turn.
  static String _boardIdPrefix(RepairProject r) {
    final bid = r.boardModelCode.trim();
    if (bid.isEmpty) return '';
    return '[Identyfikator płyty PCB (Board ID): $bid]\n\n';
  }

  static String _intakeNotes(RepairProject r) {
    if (r.components.isEmpty) {
      return '(brak — wnioskuj z kategorii urządzenia i Board ID.)';
    }
    return r.components.map((c) => '${c.label}: ${c.value}').join('\n');
  }

  /// Marketing / device line for prompts (e.g. "HP ProBook G3").
  static String _boardProductLine(RepairProject r) {
    final b = r.brand.trim();
    final m = r.modelName.trim();
    if (b.isEmpty && m.isEmpty) return 'nieznany laptop / płyta';
    if (b.isEmpty) return m;
    if (m.isEmpty) return b;
    return '$b $m';
  }

  /// Core persona + board anchor — included on every API call via the system message.
  static String _coreTechnicianAndBoardContext(RepairProject r) {
    final line = _boardProductLine(r);
    final bid = r.boardModelCode.trim().isEmpty ? '(brak Board ID)' : r.boardModelCode.trim();
    return '''
You are an expert laptop repair technician. The current board is $line ($bid). Use your knowledge of this specific board's schematics, typical placement, and signal/power paths for this PCB code.

To samo po polsku (obowiązuje w rozumowaniu): Jesteś ekspertem od naprawy laptopów na poziomie serwisu ze schematami. Aktualna płyta to: $line (Board ID / kod PCB: $bid). Korzystaj z wiedzy o tej konkretnej płycie i typowych schematach dla tego oznaczenia PCB — nie traktuj jej jak „anonimowej” płyty ogólnej.
''';
  }

  static String _systemPrompt(RepairProject r) {
    final intake = _intakeNotes(r);
    final bid = r.boardModelCode.trim();
    final line = _boardProductLine(r);
    return '''
${_coreTechnicianAndBoardContext(r)}

JĘZYK — ODPOWIEDZI DO UŻYTKOWNIKA (OBOWIĄZKOWE):
- W polach JSON widocznych użytkownikowi ("next_question", "technical_preview", "checklist_add") używaj WYŁĄCZNIE języka polskiego. Żadnego angielskiego w treściach dla użytkownika.

PAMIĘĆ I HISTORIA:
- W żądaniu API pole "messages" zawiera PEŁNĄ historię tej rozmowy (wszystkie wcześniejsze wiadomości user i assistant w kolejności). Musisz z niej aktywnie korzystać: pamiętaj ustalenia sprzed kilku minut, wcześniejsze designatory i kontekst naprawy. Nie resetuj się jak bot bez pamięci.

IDENTYFIKACJA PŁYTY (dane sesji):
- Produkt / platforma: $line
- Board ID (kod PCB): ${bid.isEmpty ? '(nie podano)' : bid}
- Kategoria urządzenia: ${r.deviceCategory}

INTAKE / SYMPTOMY:
$intake

DESIGNATORY KOMPONENTÓW (X400, L400, Q12, R203, C88, U42 itd.):
- Gdy użytkownik podaje KONKRETNY designator (np. litera + numer jak X400, L400), ZAKAZ odpowiadania ogólnikami w stylu „sprawdź oznaczenia na silkscreen”, „poszukaj etykiet Rxxx/Cxxx na płycie” albo „obejrzyj płytę pod kątem napisów” — to traktuj jako błąd w tej sytuacji.
- Zamiast tego: podaj NAJBARDZIEJ PRAWDOPODOBNĄ identyfikację elementu dla tej płyty ($bid) — np. kwarc/rezonator (często 25 MHz przy torze Ethernet), dławik w torze DC-DC, MOSFET w gałęzi zasilania itd. — na podstawie typowych konwencji (X = rezonator/kwarc, L = indukcyjność/dławik, Q = tranzystor, U = IC, R = rezystor, C = kondensator) oraz typowej roli przy tym kodzie PCB.
- Jeśli bez pełnego schematu nie da się jednoznacznie stwierdzić wartości/roli, napisz to krótko, ale ZAWSZE podaj konkretną hipoteżę (np. „X400 zwykle jest rezonatorem przy PHY”) zamiast odsyłać użytkownika do „sprawdzenia napisów”.

ZASADY DODATKOWE:
- Bez linków zakupowych, cen, sklepów.
- Odpowiadaj w kontekście tej płyty ($line, $bid) — nie używaj bezpłciowych porad „dla każdego laptopa”, jeśli pytanie dotyczy konkretnego miejsca lub designatora.
- Jeśli użytkownik przesłał zdjęcie z mikroskopu, analizuj je szczegółowo (komponenty, pady, ślady).
- Jeśli wiadomość zaczyna się od „[Dowód wizualny]”, traktuj załączone zdjęcie jako dowód wizualny dla bieżącego etapu diagnozy — powiąż analizę z wcześniejszymi ustaleniami w czacie, nie tylko ogólny opis zdjęcia.

FORMAT WYJŚCIA — JEDEN obiekt JSON (bez markdown). Klucze po angielsku, WARTOŚCI tekstowe dla użytkownika po polsku:
- "next_question" (string): pytanie lub podsumowanie kończące, jeśli session_complete.
- "technical_preview" (string): szczegóły techniczne (piny, oznaczenia, kroki pomiaru) albo pusty string.
- "show_technical_drawer" (boolean): true tylko gdy technical_preview zawiera realne detale (lokalizacja, piny, kroki); false jeśli pusto lub tylko czat.
- "checklist_add" (tablica stringów): 0–3 krótkie punkty po polsku.
- "session_complete" (boolean): true gdy kończysz pomoc w tej turze.

''';
  }

  static String _startUserMessage(RepairProject r) {
    return '${_boardIdPrefix(r)}'
        'Rozpocznij sesję diagnostyczną. Odpowiedz wyłącznie JSON według schematu. '
        'Pierwsze pytanie dostosuj do kontekstu urządzenia i intake — naturalnie możesz zacząć od zasilania/objawów, ale nie wymuszaj sztywnego scenariusza. '
        'Pola tekstowe po polsku. session_complete: false.';
  }

  /// First assistant turn (no user answers yet).
  static Future<DiagnosticChatTurn> startSession(RepairProject repair) async {
    return _send(repair, const [], null, null);
  }

  /// [history] = pełna historia czatu **bez** bieżącej wypowiedzi użytkownika.
  /// [microscopeImagePath]: plik JPEG z mikroskopu — wysyłany do Groq jako obraz + [userReply].
  static Future<DiagnosticChatTurn> continueSession(
    RepairProject repair,
    List<DiagnosticChatMessage> history,
    String userReply, {
    String? microscopeImagePath,
  }) async {
    final trimmed = userReply.trim();
    if (trimmed.isEmpty && microscopeImagePath == null) {
      return const DiagnosticChatTurn(
        nextQuestion: 'Wpisz odpowiedź.',
        technicalPreview: '',
        checklistAdd: [],
        sessionComplete: false,
        showTechnicalDrawer: false,
      );
    }
    final effective = trimmed.isEmpty && microscopeImagePath != null
        ? kMicroscopeAnalysisPrompt
        : trimmed;
    return _send(repair, history, effective, microscopeImagePath);
  }

  static bool _needsVisionModel(
    List<DiagnosticChatMessage> historyBeforeUser,
    String? microscopeImagePath,
  ) {
    if (microscopeImagePath != null) return true;
    return historyBeforeUser.any(
      (m) => m.isUser && (m.localImagePath != null && m.localImagePath!.isNotEmpty),
    );
  }

  static Object _historyUserContent(DiagnosticChatMessage m) {
    final path = m.localImagePath;
    if (path != null && path.isNotEmpty) {
      final dataUrl = jpegFileToDataUrl(path);
      if (dataUrl != null) {
        return [
          {'type': 'text', 'text': m.text},
          {
            'type': 'image_url',
            'image_url': {'url': dataUrl},
          },
        ];
      }
    }
    return m.text;
  }

  static Object _currentUserContent(
    RepairProject r,
    String userMessage,
    String? microscopeImagePath,
  ) {
    final prefixed = '${_boardIdPrefix(r)}$userMessage';
    if (microscopeImagePath != null && microscopeImagePath.isNotEmpty) {
      final dataUrl = jpegFileToDataUrl(microscopeImagePath);
      if (dataUrl != null) {
        return [
          {'type': 'text', 'text': prefixed},
          {
            'type': 'image_url',
            'image_url': {'url': dataUrl},
          },
        ];
      }
    }
    return prefixed;
  }

  static Future<DiagnosticChatTurn> _send(
    RepairProject repair,
    List<DiagnosticChatMessage> historyBeforeUser,
    String? userMessage,
    String? microscopeImagePath,
  ) async {
    final key = RepairDataService.resolveGroqApiKey();
    if (key.isEmpty) {
      return _offlineNoKeyTurn(repair);
    }

    final useVision =
        _needsVisionModel(historyBeforeUser, microscopeImagePath);

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt(repair)},
    ];

    if (historyBeforeUser.isEmpty && userMessage == null) {
      messages.add({'role': 'user', 'content': _startUserMessage(repair)});
    } else {
      for (final m in historyBeforeUser) {
        if (m.isUser) {
          messages.add({
            'role': 'user',
            'content': _historyUserContent(m),
          });
        } else {
          messages.add({
            'role': 'assistant',
            'content': m.text,
          });
        }
      }
      if (userMessage != null) {
        messages.add({
          'role': 'user',
          'content': _currentUserContent(
            repair,
            userMessage,
            microscopeImagePath,
          ),
        });
      }
    }

    final body = <String, dynamic>{
      'model': useVision ? _visionModel : _textModel,
      'messages': messages,
      'temperature': 0.35,
      // Dłuższe odpowiedzi przy identyfikacji elementów (X400, L400, itd.).
      'max_tokens': 2048,
      'response_format': const {'type': 'json_object'},
    };

    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'DiagnosticChatService HTTP ${response.statusCode}: '
          '${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
        );
        return _parseFailureTurn();
      }

      final outer = jsonDecode(response.body) as Map<String, dynamic>;
      if (outer['error'] != null) {
        debugPrint('DiagnosticChatService error field: ${outer['error']}');
        return _parseFailureTurn();
      }

      final choices = outer['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return _parseFailureTurn();

      final content = (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>?;
      final raw = content?['content'];
      final text = raw is String ? raw : raw?.toString();
      if (text == null || text.trim().isEmpty) return _parseFailureTurn();

      return _parseAssistantPayload(text.trim());
    } catch (e, st) {
      debugPrint('DiagnosticChatService: $e\n$st');
      return _parseFailureTurn();
    }
  }

  static DiagnosticChatTurn _parseAssistantPayload(String raw) {
    try {
      final cleaned = RepairDataService.cleanJsonFenceTags(raw);
      final map = jsonDecode(cleaned) as Map<String, dynamic>;
      return _parseTurnJson(map);
    } catch (_) {
      return DiagnosticChatTurn(
        nextQuestion: raw.length > 4000 ? '${raw.substring(0, 4000)}…' : raw,
        technicalPreview: '',
        checklistAdd: const [],
        sessionComplete: false,
        showTechnicalDrawer: false,
      );
    }
  }

  static DiagnosticChatTurn _parseTurnJson(Map<String, dynamic> map) {
    final q = (map['next_question'] ?? map['question'] ?? '').toString().trim();
    final tp =
        (map['technical_preview'] ?? map['technical_hint'] ?? '').toString().trim();
    final rawList = map['checklist_add'] ?? map['checklist'] ?? [];
    final add = <String>[];
    if (rawList is List) {
      for (final e in rawList) {
        final s = e.toString().trim();
        if (s.isNotEmpty) add.add(s);
      }
    }
    final done = map['session_complete'] == true;
    final rawDrawer = map['show_technical_drawer'];
    var showDrawer = rawDrawer == true;
    if (rawDrawer == null && tp.isNotEmpty) {
      showDrawer = _heuristicShowDrawer(tp);
    }
    return DiagnosticChatTurn(
      nextQuestion: q.isEmpty
          ? 'Co dokładnie mierzysz lub obserwujesz na tej płycie? Opisz jednym zdaniem.'
          : q,
      technicalPreview: tp,
      checklistAdd: add,
      sessionComplete: done,
      showTechnicalDrawer: showDrawer,
    );
  }

  /// Heurystyka gdy model nie poda flagi — oznaczenia i słowa pomiarowe (PL/EN).
  static bool _heuristicShowDrawer(String tp) {
    final s = tp.trim();
    if (s.length < 10) return false;
    if (RegExp(r'\b([A-Z]{0,3}\d{2,5}[A-Z]?)\b').hasMatch(s)) return true;
    final l = s.toLowerCase();
    if (l.contains('measure') ||
        l.contains('probe') ||
        l.contains('pin ') ||
        l.contains('ohm') ||
        l.contains('diode') ||
        l.contains('pomiar') ||
        l.contains('sonda') ||
        l.contains('pad') ||
        l.contains(' styk') ||
        l.contains('multimetr')) {
      return true;
    }
    return false;
  }

  static DiagnosticChatTurn _parseFailureTurn() {
    return const DiagnosticChatTurn(
      nextQuestion:
          'Nie udało się połączyć z modelem AI. Sprawdź sieć i klucz GROQ_API_KEY w pliku env lub --dart-define, potem spróbuj ponownie.',
      technicalPreview: '',
      checklistAdd: [],
      sessionComplete: false,
      showTechnicalDrawer: false,
    );
  }

  /// Brak klucza — jedna informacja po polsku, bez udawania analizy.
  static DiagnosticChatTurn _offlineNoKeyTurn(RepairProject repair) {
    final bid = repair.boardModelCode.trim();
    return DiagnosticChatTurn(
      nextQuestion:
          'Asystent wymaga działającego połączenia z API Groq. Ustaw zmienną GROQ_API_KEY '
          '(np. w assets/env/gemini.env) lub uruchom z --dart-define=GROQ_API_KEY=… '
          'Wtedy odpowiedzi będą generowane dynamicznie na podstawie Twojej historii '
          'i Board ID${bid.isNotEmpty ? ' ($bid)' : ''}.',
      technicalPreview: '',
      checklistAdd: [
        if (bid.isNotEmpty) 'Board ID sesji: $bid',
        'Skonfiguruj GROQ_API_KEY',
      ],
      sessionComplete: false,
      showTechnicalDrawer: false,
    );
  }
}

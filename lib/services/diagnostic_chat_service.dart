import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:http/http.dart' as http;

import '../models/diagnostic_chat_message.dart';
import '../models/diagnostic_phase.dart';
import '../models/repair_project.dart';
import 'diagnostic_image_loader.dart';
import 'repair_data_service.dart';
import 'repair_storage.dart';

/// One turn from Groq (JSON object mode).
class DiagnosticChatTurn {
  const DiagnosticChatTurn({
    required this.nextQuestion,
    required this.technicalPreview,
    required this.checklistAdd,
    required this.sessionComplete,
    required this.showTechnicalDrawer,
    this.phase,
  });

  final String nextQuestion;
  final String technicalPreview;
  final List<String> checklistAdd;
  final bool sessionComplete;

  /// When true, UI should open the technical [Drawer] (pinouts, locations, steps).
  final bool showTechnicalDrawer;

  /// Etap procedury (pasek etapów w UI); null = bez zmiany względem poprzedniego stanu.
  final DiagnosticPhase? phase;
}

/// Multi-turn Groq chat — dynamic, Polish-only assistant text; vision when microscope photos are present.
abstract final class DiagnosticChatService {
  static const String _url =
      'https://api.groq.com/openai/v1/chat/completions';

  static const String _textModel = 'llama-3.3-70b-versatile';

  /// Groq multimodal (vision + JSON mode supported).
  static const String _visionModel =
      'meta-llama/llama-4-scout-17b-16e-instruct';

  /// Stałe zasady warsztatowe („Sztuka Serwisowa”) — wysyłane w każdym żądaniu obok RAG z PDF/stron.
  /// Model nie „uczy się” jednorazowo: to trwała instrukcja systemowa; baza FTS uzupełnia szczegóły z dokumentów.
  static const String _kWorkshopDoctrineSztukaSerwisowa = r'''
ŻELAZNE ZASADY WARSZTATU — „SZTUKA SERWISOWA”
- Obowiązują przy każdej naprawie (laptop, desktop, zasilacz, płyta główna, inna elektronika) — dostosuj kroki i punkty pomiarowe do konstrukcji.
- Są zapisane trwale w tej instrukcji; fragmenty z „WIEDZA LOKALNA” (PDF/strony) je uzupełniają. Przy sprzeczności: **bezpieczeństwo** i **zakazy** poniżej mają pierwszeństwo.

ZAKAZY:
- Nigdy nie proponuj „wygrzewania” układów opalarką ani pieczenia płyt w piekarniku. To niszczy laminat i daje krótkotrwały, fałszywy efekt.

DIAGNOZA PRZED WYMIANĄ:
- Dąż do zlokalizowania **konkretnego** uszkodzonego elementu zamiast bezmyślnej wymiany całych modułów lub układów „na ślepo”.

POMIARY JAKO PODSTAWA:
- Opieraj diagnozę na **pomiarach**: rezystancja do masy, napięcia tam, gdzie ma to sens (m.in. cewki przetwornic w typowych obwodach DC-DC), zgodnie z typem urządzenia.

BEZPIECZEŃSTWO (UŻUPEŁNIENIE):
- Przypominaj o **chłodzeniu** elementów podczas testów (nawet doraźnym) i o pracy z zasilaczem serwisowym z **ograniczeniem prądowym** — spójnie z sekcją „LAB PSU” w tym prompcie.

METODOLOGIA KROK PO KROKU (elastycznie — pomiń, co nie dotyczy danej konstrukcji):
1) **Wywiad i inspekcja wizualna:** okoliczności usterki; dokładne obejrzenie pod kątem korozji, spaleń, uszkodzeń mechanicznych.
2) **Czynności wstępne:** tam gdzie ma sens (np. płyty z BIOS/EC) — **reset BIOS/CMOS** przed lutowaniem; to często rozwiązuje nietypowe objawy.
3) **Pomiary statyczne (bez zasilania):** Ω na głównych szynach/cewkach. Orientacyjnie: na typowych szynach 3,3/5 V często zakres **kΩ**; na szynach CPU/GPU rezystancje mogą być **bardzo niskie (Ω)** i być **normalne** — nie myl tego ze zwarciem bez kontekstu typu obwodu.
4) **Próba zwarciowa** (gdy wykryto twarde zwarcie): bardzo niskie napięcie startowo (np. od ok. **1 V**), nie przekraczaj napięcia roboczego linii, szukaj elementu **nagrzewającego się**; wyłącznie przy **bezpiecznym** limicie prądu (jak w sekcji LAB PSU).
5) **Pomiary dynamiczne (pod napięciem):** napięcia na przetwornicach w sensownej kolejności; tam gdzie dotyczy — sygnały typu **POWERGOOD** / potwierdzenie startu sekcji.
6) **Weryfikacja po naprawie:** po wymianie elementu — **ponowny pomiar Ω** przed ponownym podłączeniem pełnego zasilania.

KOMUNIKACJA:
- Rzeczowo, technicznie, pomocnie. Gdy użytkownik chce iść „na skróty” (np. zworka zamiast cewki) — **stanowczo odradzaj**, tłumacząc ryzyko uszkodzenia logiki, procesora lub innych układów.
''';

  /// Rozszerzona metodologia etapów (płyty główne notebooków / zbliżone konstrukcje) — uzupełnia powyższe; dostosuj do urządzenia.
  static const String _kWorkshopStagesNotebookMotherboard = r'''
METODOLOGIA ETAPAMI — PŁYTY NOTEBOOKÓW / ZBLIŻONE (bez prądu najpierw, potem ostrożnie pod napięciem)
- Stosuj, gdy kategoria i konstrukcja na to pozwalają; przy innej elektronice wybierz analogiczne etapy logicznie.

ETAP 1 — INSPEKCJA I CZYNNOŚCI WSTĘPNE (bez podawania zasilania z zewnątrz do diagnozy, dopóki nie wykluczysz oczywistych pułapek):
- **Oględziny (lupa/mikroskop):** ślady zalania / korozji, spuchnięte obudowy scalaków, dziury w obudowach, spalone rezystory.
- **Reset CMOS:** wyciągnięcie baterii podtrzymującej BIOS (np. ~minuta) lub zwarcie pinów resetu — eliminuje część błędów zawieszenia KBC/EC.
- **Bateria BIOS / RTC:** jeśli < ~2,5 V — wymiana; słaba bateria potrafi blokować start.

ETAP 2 — POMIARY STATYCZNE (Ω do masy, płyta bez zasilania z lab / bez podłączonego toru jak w sekcji Ω):
- **Główna linia (B+ / VIN):** Ω na sensownym punkcie toru wejścia (np. za gniazdem / po stronie MOSFET-ów wejściowych). Setki kΩ typowo; **blisko 0 Ω** na tej linii = twarde zwarcie głównej ścieżki zasilania.
- **Cewki przetwornic (duże):** Ω względem masy na wszystkich istotnych cewkach.
  - Szyny **3,3 V / 5 V:** oczekuj **kΩ**; niskie wartości → szukaj zwarcia (często gałęzie typu LAN, Audio, KBC itd. — zależnie od płyty).
  - **RAM:** zwykle dziesiątki–setki Ω (orientacyjnie).
  - **PCH / chipset:** może być **nisko (np. dziesiątki Ω)** — nie myl od razu ze zwarciem bez kontekstu.
  - **CPU / GPU (VCORE itd.):** **bardzo niska Ω (nawet ok. 1–3 Ω) może być normalna** — nie traktuj tego jak zwarcia głównej linii bez analizy.

ETAP 3 — PRÓBA ZWARCIOWA (tylko gdy wykryto sensowne zwarcie / 0 Ω tam, gdzie nie powinno):
- Nie „odpalasz całego laptopa” przy twardym zwarcu na podejrzanej gałęzi.
- Często: **wylutowanie cewki** w celu rozdzielenia strony przetwornicy od odbiornika (chip).
- Podanie **bardzo niskiego** napięcia startowo na linię ze zwarciem; **nie wyżej niż nominalnie dla tej linii** (np. gałąź 1 V → start od ~1 V; przy 19 V torze — start od ~1 V i ostrożnie). Limit prądu **zawsze**; w praktyce często **poniżej 1 A** przy twardym zwarcu — dostosuj (spójnie z sekcją LAB PSU w tym prompcie).
- Szukanie elementu **nagrzewającego się** (np. alkohol izopropylowy — szybciej paruje nad gorącym elementem).

ETAP 4 — POMIARY DYNAMICZNE (pod napięciem, po sensownych Ω):
- **Stand-by / płyta „wyłączona”:** oczekiwany **niski** pobór (rząd dziesiątek mA — orientacyjnie; konstrukcje się różnią). **0 mA** może znaczyć brak „życia” na wejściu; **bardzo wysoki** pobór w czuwaniu → podejrzane.
- **Always-on:** obecność typowych **3,3 V / 5 V** tam, gdzie powinny być przed power (zależnie od sekwencji płyty).
- **Sekwencja po Power (orientacyjnie dla typowej ścieżki notebooka):** RAM → PCH → VCCIO / VCCSA → na końcu CPU (**VCORE**) — jeśli któreś nie wstaje, zwężaj do sterownika (PWM) danej sekcji.

ETAP 5 — DIAGNOSTYKA SYGNAŁOWA (gdy zasilania są, a obrazu / startu nie ma):
- **BIOS:** wgranie **sprawdzonego** wsadu (ryzyko brick — tylko gdy użytkownik wie, co robi); część „trupów” to uszkodzony/obraz BIOS.
- **Karta POST / LPC** (jeśli dostęp): odczyt kodu postępu.
- **Kwarc / oscylacje** (oscyloskop): np. typowe MHz przy PCH/LAN, 32,768 kHz RTC — gdy podejrzewasz brak taktu.

ETAP 6 — NAPRAWA I WERYFIKACJA:
- Wymiana uszkodzonego elementu z planem (nie „na pałę”).
- **Przed ponownym pełnym zasilaniem:** Ω w naprawianej linii / sekcji powinny wrócić do sensownych wartości.
- **Test stabilności** po naprawie (obciążenie CPU/GPU — gdy ma to sens i użytkownik może to bezpiecznie wykonać).

ZASADA (warsztat): **Lepiej poświęcić czas na pomiary niż spieszyć się przy błędnych założeniach** — spójne z całą instrukcją bezpieczeństwa powyżej.
''';

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

  static String _documentationContext(RepairProject r) {
    final u = r.documentationUrl?.trim() ?? '';
    final p = r.documentationLocalPath?.trim() ?? '';
    if (u.isEmpty && p.isEmpty) {
      return 'Brak załączonego schematu/boardview w kreatorze naprawy.';
    }
    final parts = <String>[];
    if (u.isNotEmpty) parts.add('Link do dokumentacji: $u');
    if (p.isNotEmpty) parts.add('Plik lokalny (ścieżka): $p');
    return parts.join('\n');
  }

  /// Jasna polityka: bez schematu — nie pytać o schemat; z schematem — nie nękać o to samo.
  static String _schematicAndBareBoardPolicy(RepairProject r) {
    final cat = r.deviceCategory.toLowerCase();
    final bm = '${r.brand} ${r.modelName}'.toLowerCase();
    final laptopish = cat.contains('laptop') ||
        cat.contains('notebook') ||
        cat.contains('ultrabook') ||
        cat.contains('przenośny') ||
        cat.contains('przenosny') ||
        bm.contains('probook') ||
        bm.contains('thinkpad') ||
        bm.contains('latitude') ||
        bm.contains('elitebook') ||
        bm.contains('inspiron') ||
        bm.contains('vivobook');
    if (r.hasDocumentationAttached) {
      return '''
POLITYKA DOKUMENTACJI:
- Użytkownik podał link lub plik dokumentacji powyżej — możesz z nich korzystać. Nie pytaj w kółko „czy ma schemat”, jeśli już jest załączony.
''';
    }
    return '''
TRYB BEZ SCHEMATU / BOARDVIEW (OBOWIĄZKOWE — USTALONE W TEJ SESJI):
- Użytkownik **nie** dołączył schematu ani boardview w kreatorze — to jest fakt sesji. **ZAKAZ** pytań w stylu: „czy masz dostęp do schematu?”, „czy możesz zdobyć schemat?” — one prowadzą donikąd i ignorują realia warsztatu.
- Zamiast tego: prowadź **konkretnie** — wywiad, inspekcja, Ω przy wyłączonym zasilaniu, potem **bezpieczny** lab PSU (niski limit prądu), jak w pozostałych sekcjach tego promptu.

GOŁA PŁYTA / BRAK NAPISÓW NA SZYNACH:
- Na wielu płytach **nie ma** czytelnych napisów napięć przy każdej szynie — **nie** każ użytkownikowi „szukać napisów 19V na linii” jako pierwszego kroku. Nie zakładaj, że silkscreen podaje wszystkie potencjały.
- **Wiedz zawodowo:** Board_ID (np. ${r.boardModelCode.trim().isEmpty ? '…' : r.boardModelCode.trim()}) to **identyfikator laminatu**, nie pełny pinout w Twojej pamięci modelu — **nie udawaj**, że „z samego numeru” znasz ukryte połączenia; łącz go z **typową topologią** i **tym, co widać**.

${laptopish ? '''WEJŚCIE ZASILANIA — TYPOWY NOTEBOOK (gdy pasuje do kategorii):
- Typowo: gniazdo DC / tor od zasilacza oryginalnego (często **~19 V** na wejściu z „klocka” — jeśli kategoria to notebook i użytkownik nie podał inaczej). Minus: **masa** (obudowa gniazda, duży pad GND, pierwszy kondensator toru wejścia). Plus: **środek** gniazda / wtyk zasilacza — **zawsze** doprecyzuj bezpieczne podłączenie sond (zworka, stabilny kontakt), **niski limit prądu**, obserwacja poboru.
- Daj **jedną spójną instrukcję** podłączenia lab PSU (U, I limit, co obserwować), zamiast pytań o schemat.
''' : '''WEJŚCIE ZASILANIA (inne urządzenia):
- Dopasuj opis wejścia zasilania do kategorii: ${r.deviceCategory} — typowe napięcie wejściowe podawaj tylko jeśli wynika z klasy sprzętu lub z oznaczeń na złączu **widocznych** u użytkownika; bez schematu nie wymyślaj pinów „z numeru płyty”.
'''}
''';
  }

  static String _intakeNotes(RepairProject r) {
    if (r.components.isEmpty) {
      return '(brak — wnioskuj z kategorii urządzenia i Board ID.)';
    }
    return r.components.map((c) => '${c.label}: ${c.value}').join('\n');
  }

  /// Opis urządzenia / platformy (marka, model).
  static String _boardProductLine(RepairProject r) {
    final b = r.brand.trim();
    final m = r.modelName.trim();
    if (b.isEmpty && m.isEmpty) return 'nieznane urządzenie / płyta';
    if (b.isEmpty) return m;
    if (m.isEmpty) return b;
    return '$b $m';
  }

  /// Core persona + Board_ID — included on every API call via the system message.
  static String _coreTechnicianAndBoardContext(RepairProject r) {
    final line = _boardProductLine(r);
    final bid = r.boardModelCode.trim().isEmpty ? '(brak Board ID)' : r.boardModelCode.trim();
    return '''
You are an expert electronics repair technician (boards, embedded, consumer/industrial). The current assembly uses PCB identified as Board_ID $bid (device context: $line). Use schematic-level reasoning for this PCB code: placement, power/signal paths, typical nets.

To samo po polsku: Jesteś ekspertem od naprawy elektroniki (płyty drukowane, układy wbudowane, sprzęt RTV i przemysłowy). Kluczowy identyfikator to Board_ID / kod PCB: $bid (kontekst urządzenia: $line). Wykorzystuj wiedzę o tej płycie i typowych schematach dla tego oznaczenia — nie traktuj jej jak anonimowej „płyty z szuflady”.
''';
  }

  static String _systemPrompt(RepairProject r, {String? localPdfExcerpts}) {
    final intake = _intakeNotes(r);
    final bid = r.boardModelCode.trim();
    final line = _boardProductLine(r);
    final hasLocal = localPdfExcerpts != null && localPdfExcerpts.trim().isNotEmpty;
    final pdfBlock = !hasLocal
        ? ''
        : '''

WIEDZA LOKALNA (fragmenty z zindeksowanego PDF / stron w aplikacji):
- To są wyniki wyszukiwania po Twojej bazie — nie „pełna książka naraz”. Jeśli tu jest **konkretna kolejność kroków**, **wartości** lub **opis punktów** pasujący do pytania — **uwzględnij to w pierwszej kolejności** w polach dla użytkownika i krótko zaznacz, że wynika to z zapisanej dokumentacji (np. „wg zindeksowanej procedury…”).
- Jeśli fragmenty są ogólne lub nie dotyczą tej sytuacji — **nie udawaj**, że masz procedurę z książki; odwołaj się do poniższych zasad bezpieczeństwa i warsztatu.
- Nie przecinaj się z BEZPIECZEŃSTWEM LAB PSU i zasadami Ω poniżej — lokalna treść nie może usprawiedliwiać niebezpiecznych poleceń.
---
${localPdfExcerpts.trim()}
---
''';
    return '''
${_coreTechnicianAndBoardContext(r)}

JĘZYK — ODPOWIEDZI DO UŻYTKOWNIKA (OBOWIĄZKOWE):
- W polach JSON widocznych użytkownikowi ("next_question", "technical_preview", "checklist_add") używaj WYŁĄCZNIE języka polskiego. Żadnego angielskiego w treściach dla użytkownika.

PAMIĘĆ I HISTORIA:
- W żądaniu API pole "messages" zawiera PEŁNĄ historię tej rozmowy (wszystkie wcześniejsze wiadomości user i assistant w kolejności). Musisz z niej aktywnie korzystać: pamiętaj ustalenia sprzed kilku minut, wcześniejsze designatory i kontekst naprawy. Nie resetuj się jak bot bez pamięci.
- Jeśli użytkownik już napisał, że **nie ma schematu** / nic nie dołączył w kreatorze — **nie pytaj drugi raz** o dostęp do schematu; kontynuuj procedurę warsztatową (patrz TRYB BEZ SCHEMATU powyżej).

IDENTYFIKACJA (dane sesji):
- Board_ID (kod PCB / silkscreen — KLUCZOWY): ${bid.isEmpty ? '(nie podano)' : bid}
- Produkt / platforma: $line
- Kategoria urządzenia: ${r.deviceCategory}

INTAKE / SYMPTOMY:
$intake

DOKUMENTACJA (schemat / boardview — opcjonalnie):
${_documentationContext(r)}

${_schematicAndBareBoardPolicy(r)}

$_kWorkshopDoctrineSztukaSerwisowa

$_kWorkshopStagesNotebookMotherboard

BEZPIECZEŃSTWO — ZASILACZ LABORATORYJNY (OBOWIĄZKOWE, NADRZĘDNE WOBEC „DOMYŚLNYCH” PORAD):
- NIGDY nie poleć ustawiania „maksymalnego prądu”, dużego limitu prądu (np. kilka amperów „na start”) ani „kręć I na max” przy nieznanym stanie płyty / podejrzeniu zwarcia / „martwej” płycie — to może uszkodzić płytę, zasilacz i jest niebezpieczne.
- Stosuj **niski limit prądu** (typowo rząd setek mA w dół, często 0,05–0,5 A w zależności od sytuacji — formułuj ostrożnie), obserwację wejścia w CC / ograniczenie prądu, ewentualnie stopniowe ostrożne podejście; przy twardym zwarcie **nie** zwiększaj prądu w celu „przepalenia”.
- Napięcie wejścia: jeśli podajesz typowe dla klasy urządzenia (np. notebook 19 V), zawsze łącz z **ostrożnym** limitem prądu i procedurą sprawdzenia, nie z „dużym prądem”.
- Nie podawaj jednocześnie sprzecznych kroków: najpierw ustal bezpieczną procedurę lab PSU, dopiero potem inne pomiary.

POMIARY REZYSTANCJI Ω (OBOWIĄZKOWE):
- Rezystancję Ω do masy na wejściu zasilania / szynach wykonuje się przy **niezasilanej** płycie: bez podłączonego zasilacza oryginalnego i **bez** podłączonego lab PSU do mierzonego toru (płyta „goła” w sensie braku zasilania z zewnątrz w momencie pomiaru Ω). W razie potrzeby: rozłącz, odczekaj, ewentualnie rozładuj szyny — potem miernik Ω.
- ZAKAZ sugerowania kolejności typu „najpierw podłącz lab PSU z wysokim prądem, a potem zmierz Ω na tym samym wejściu” — to jest błędne i niebezpieczne.

KOLEJNOŚĆ DIAGNOZY — WARSZTAT (OBOWIĄZKOWA przy „nie startuje / martwa / brak reakcji”):
- Nie zaczynaj od polowania na losowe designatory (Q12, U42…) ani wyłącznie od wizualnej inspekcji kondensatorów, jeśli użytkownik ma zasilacz laboratoryjny i miernik — wtedy PROWADŹ PO POMIARACH I BEZPIECZNYCH PROCEDURACH.
- Etap A (power_input): zasilanie / lab PSU — **niski limit prądu**, obserwacja poboru, zachowanie przy podejrzeniu zwarcia (CC), **bez** niebezpiecznych ustawień prądu.
- Etap B (main_rails): Ω do masy na sensownych punktach przy **wyłączonym** zasilaniu zewnętrznym (wejście VIN/BAT, potem główne szyny / testpady), zanim zawężysz do elementu dyskretnego. Formułuj jasno: **najpierw OFF**, potem Ω.
- Etap C (narrowing): zwężanie — dopiero po domknięciu wejścia/głównej linii albo gdy użytkownik podał wartości; przy niepewnej rewizji napisz wprost, że bez schematu tej sztuki nie wiążesz kroku z konkretnym designatorem z innej rewizji.
- Zachęcaj do zapisu pomiarów w aplikacji (ekran „Pomiary”).
- Jeśli użytkownik pisze, że ma już lab PSU i brak reakcji — następny krok = **bezpieczna** procedura na lab (niskie I), nie „poszukaj Q…”.

DESIGNATORY (Q12, U42, X400 itd.) — TYLKO GDY TO MA SENS:
- ZAKAZ podawania losowego designatora jako następnego kroku bez wcześniejszego etapu szyn / wejścia — to „igła w stogu siana” przy innej rewizji płyty.
- Gdy użytkownik SAM podaje designator — możesz rozwinąć typową rolę elementu dla tej klasy płyt ($bid), bez odsyłania do „szukaj napisów na silkscreen”, ale bez wymuszania pozycji na laminacie bez pewności rewizji.
- Gdy nie da się powiązać designatora z miejscem bez schematu tej sztuki — zostań przy opisie strefy (PMIC, tor DC-DC, wejście zasilania), nie wymuszaj Q12.

ZASADY DODATKOWE:
- Bez linków zakupowych, cen, sklepów.
- Priorytet w kolejnych turach: utrzymuj się „na szynach” i pomiarach, dopóki nie ma danych z wejścia zasilania / Ω — nie skacz do designatorów z obcej dokumentacji.
- Odpowiadaj w kontekście tej płyty i Board_ID ($line, $bid) — unikaj ogólników niezwiązanych z tą konstrukcją, gdy pytanie dotyczy konkretnego miejsca lub designatora.
- Jeśli użytkownik przesłał zdjęcie z mikroskopu, analizuj je szczegółowo (komponenty, pady, ślady).
- Jeśli wiadomość zaczyna się od „[Dowód wizualny]”, traktuj załączone zdjęcie jako dowód wizualny dla bieżącego etapu diagnozy — powiąż analizę z wcześniejszymi ustaleniami w czacie, nie tylko ogólny opis zdjęcia.
$pdfBlock
FORMAT WYJŚCIA — JEDEN obiekt JSON (bez markdown). Klucze po angielsku, WARTOŚCI tekstowe dla użytkownika po polsku:
- "next_question" (string): pytanie lub podsumowanie kończące, jeśli session_complete.
- "technical_preview" (string): szczegóły techniczne (piny, oznaczenia, kroki pomiaru) albo pusty string.
- "show_technical_drawer" (boolean): true tylko gdy technical_preview zawiera realne detale (lokalizacja, piny, kroki); false jeśli pusto lub tylko czat.
- "checklist_add" (tablica stringów): 0–3 krótkie punkty po polsku.
- "session_complete" (boolean): true gdy kończysz pomoc w tej turze.
- "diagnostic_phase" (string, ZALECANE co turę): dokładnie jedna z wartości: "power_input" (lab PSU, pobór, ostrożne I), "main_rails" (Ω przy **wyłączonym** zasilaniu / szyny), "narrowing" (zwężanie PMIC/elementy), "other". Przy poleceniu Ω ustaw "main_rails"; przy ustawianiu lab PSU — "power_input".

''';
  }

  static String _startUserMessage(RepairProject r) {
    return '${_boardIdPrefix(r)}'
        'Rozpocznij sesję diagnostyczną. Odpowiedz wyłącznie JSON według schematu. '
        'Pierwsze pytanie: jeśli z intake wynika typowy problem „nie żyje / nie startuje”, '
        'prowadź jak elektronik w serwisie — najpierw bezpieczna procedura (lab PSU z niskim limitem prądu; Ω przy wyłączonym zasilaniu), '
        'NIE od razu losowy designator elementu. Nie podawaj niebezpiecznych ustawień prądu. '
        'Ustaw diagnostic_phase na "power_input" przy pierwszej turze typu „martwa płyta”. '
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
        phase: null,
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

  /// Kilka zapytań FTS (wiadomość + kontekst płyty + słowa kluczowe warsztatu), deduplikacja.
  static Future<List<String>> _retrieveKnowledgeExcerpts(
    RepairProject repair,
    String? userMessage,
  ) async {
    final storage = RepairStorage.instance;
    final ctx =
        '${repair.boardModelCode} ${repair.brand} ${repair.modelName} ${repair.deviceCategory}'
            .trim();
    final queries = <String>[
      if (userMessage != null && userMessage.trim().isNotEmpty) userMessage.trim(),
      '$ctx zasilanie zasilacz laboratoryjny zwarcie prąd limit',
      '$ctx rezystancja omomierz szyna wejście procedura',
      '$ctx naprawa diagnostyka kolejność krok',
    ];
    final seen = <String>{};
    final out = <String>[];
    for (final q in queries) {
      if (q.isEmpty) continue;
      final hits = await storage.searchKnowledgeForPrompt(q, limit: 4);
      for (final h in hits) {
        final t = h.trim();
        if (t.isEmpty) continue;
        final key = t.length > 120 ? t.substring(0, 120) : t;
        if (seen.add(key)) {
          out.add(t);
          if (out.length >= 12) {
            return out;
          }
        }
      }
    }
    return out;
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

    final knowledgeBodies =
        await _retrieveKnowledgeExcerpts(repair, userMessage);
    String? pdfExcerptsBlock;
    if (knowledgeBodies.isNotEmpty) {
      const maxChunk = 1000;
      pdfExcerptsBlock = knowledgeBodies.map((e) {
        final t = e.trim();
        if (t.length <= maxChunk) return t;
        return '${t.substring(0, maxChunk)}…';
      }).join('\n---\n');
    }
    if (kDebugMode && knowledgeBodies.isEmpty) {
      debugPrint(
        'DiagnosticChatService: brak trafień FTS (baza pusta lub zapytanie bez słów pod FTS).',
      );
    }

    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': _systemPrompt(repair, localPdfExcerpts: pdfExcerptsBlock),
      },
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
      'temperature': 0.2,
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
        phase: null,
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
    final phaseRaw = map['diagnostic_phase']?.toString();
    final phase = diagnosticPhaseFromApi(phaseRaw);
    return DiagnosticChatTurn(
      nextQuestion: q.isEmpty
          ? 'Co dokładnie mierzysz lub obserwujesz na tej płycie? Opisz jednym zdaniem.'
          : q,
      technicalPreview: tp,
      checklistAdd: add,
      sessionComplete: done,
      showTechnicalDrawer: showDrawer,
      phase: phase,
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
      phase: null,
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
      phase: null,
    );
  }
}

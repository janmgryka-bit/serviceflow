# ServiceFlow AI

Krótki opis aplikacji (np. do wklejenia w **Google Gemini** lub innym czacie jako kontekst projektu):

> **ServiceFlow AI** to aplikacja desktopowa (Flutter) dla **serwisu elektroniki ogólnej** (płyty, moduły, urządzenia embedded). Łączy lokalną bazę napraw z **Board_ID** jako głównym identyfikatorem płyty, kreator weryfikacji z wyszukiwaniem kodów PCB przez AI (Groq), interaktywny czat diagnostyczny z analizą obrazu (mikroskop / kamera UVC) oraz **szybkie logowanie pomiarów** (napięcie, rezystancja, prąd). Lista napraw na ekranie głównym korzysta z lekkich zapytań (bez pełnego JSON na wiersz); szczegóły projektu i historia czatu są w SQLite.

---

## Czym jest ta aplikacja?

**ServiceFlow AI** wspiera technika w warsztacie przy identyfikacji PCB (kod silkscreen / ODM), zapisie kontekstu naprawy (marka, model, **Board_ID**, komponenty krytyczne) oraz prowadzeniu **sesji diagnostycznej** z modelem językowym. Aplikacja nie jest sklepem — skupia się na diagnozie elektrycznej i szybkim wpisywaniu pomiarów, bez linków zakupowych.

## Stack techniczny

- **Flutter** (Dart SDK ^3.11), UI ciemny z akcentami pomarańczowymi  
- **SQLite** (`sqflite` / `sqflite_common_ffi` na desktopie) — naprawy (kolumny indeksowane m.in. `board_id`), log pomiarów `measurement_logs`, cache wyszukiwań płyt, stan czatu diagnostycznego  
- **Groq API** (OpenAI-compatible) — czat diagnostyczny, profile diagnostyczne, research kodów płyt  
- **Kamera / mikroskop** — pakiet `camera` + `camera_desktop` (Linux: GStreamer + v4l2 / UVC)  
- **Zmienne środowiskowe** — `flutter_dotenv`, plik `assets/env/gemini.env` (m.in. `GROQ_API_KEY`)

> **Uwaga:** W nazwie pliku występuje „gemini”, ale **główna integracja AI w czacie i researchu płyt to Groq**. Klucz API konfiguruje się jako `GROQ_API_KEY`.

## Główne funkcjonalności (stan na dziś)

1. **Ekran główny / lista napraw**  
   - Tworzenie i wybór projektów: kategoria urządzenia, marka, model, **Board_ID** (kod PCB / silkscreen), komponenty krytyczne. Lista ładuje podsumowania bez pełnego dekodowania JSON każdej naprawy.

2. **Pomiary (ekran „Pomiary”)**  
   - Szybki zapis napięcia, rezystancji i prądu z wyborem jednostki i etykietą sieci; ostatnie wpisy pod polem — pod kątem pracy „na stojaku” z minimalną liczbą dotknięć.

3. **Kreator weryfikacji płyty (wizard)**  
   - Wyszukiwanie propozycji płyt przez **Groq** na podstawie urządzenia (z cache w SQLite).  
   - Możliwość ręcznego wpisania kodu płyty i kontynuacji do asystenta.

4. **Asystent diagnostyczny (czat)**  
   - Wieloturowa rozmowa z modelem; **pełna historia** wysyłana w każdym żądaniu.  
   - Kontekst płyty: marka, model, Board_ID, intake — odpowiedzi **po polsku** (JSON z polami dla UI).  
   - Tryb wizji: zdjęcia (np. z kamery) analizowane modelem multimodalnym (Groq), w tym **dowód wizualny** z panelu bocznego.  
   - Lista kontrolna generowana z odpowiedzi asystenta.  
   - Panel techniczny (szczegóły pomiarów / lokalizacji) w szufladzie po prawej.

5. **Podgląd na żywo w panelu bocznym**  
   - Lista urządzeń wideo (UVC), podgląd strumienia, przycisk **„Przechwyć obraz”** — klatka trafia do czatu i jest automatycznie analizowana jako dowód wizualny dla bieżącego kroku naprawy.

6. **Persystencja**  
   - Zapis stanu czatu i checklisty per naprawa.

## Konfiguracja

- Skopiuj lub utwórz `assets/env/gemini.env` i ustaw np.:  
  `GROQ_API_KEY=twoj_klucz`  
  Alternatywa: `flutter run --dart-define=GROQ_API_KEY=...`

## Linux (kamera w panelu)

Plugin `camera_desktop` wymaga m.in. bibliotek **GStreamer** (np. Debian/Ubuntu: pakiety `libgstreamer1.0-dev`, `libgstreamer-plugins-base1.0-dev`, `gstreamer1.0-plugins-good`). Tylko jeden program naraz może zająć dane `/dev/video*` — zamknij np. guvcview, jeśli kamera jest zajęta.

## Uruchomienie

```bash
flutter pub get
flutter run -d linux   # lub windows / macos / chrome wg potrzeb
```

---

## Licencja / repo

Szczegóły w repozytorium autora (jeśli dodane).

import '../models/diagnostic_profile.dart';

/// Offline fallbacks when Groq is unavailable or returns nothing useful.
abstract final class DiagnosticTemplates {
  static String normalizeDeviceKind(String deviceCategory) {
    final s = deviceCategory.trim().toLowerCase();
    if (s.contains('phone') || s.contains('iphone') || s.contains('android phone')) {
      return 'phone';
    }
    if (s.contains('tablet') || s.contains('ipad')) {
      return 'tablet';
    }
    return 'embedded';
  }

  static DiagnosticProfile forDeviceCategory(String deviceCategory) {
    switch (normalizeDeviceKind(deviceCategory)) {
      case 'phone':
        return _genericPhone();
      case 'tablet':
        return _genericTablet();
      default:
        return _genericEmbeddedBoard();
    }
  }

  /// Płyty główne / embedded / przemysł — większe PCB i moduły.
  static DiagnosticProfile _genericEmbeddedBoard() {
    return const DiagnosticProfile(
      mainPowerRails: [
        MainPowerRail(
          name: 'Wejście zasilania / VIN',
          description: 'DC jack, USB-PD, zasilacz przed przetwornicami',
          measurementHint: 'V: obecność; Ω: zwarcie na wejściu',
        ),
        MainPowerRail(
          name: '+3.3 V (logika / standby)',
          description: 'Często pierwsza szyna z LDO lub PMIC',
          measurementHint: '~3.3 V przy włączonym obwodzie',
        ),
        MainPowerRail(
          name: '+5 V / pośrednie',
          description: 'USB, silniki, wentylatory — zależnie od projektu',
          measurementHint: '~5 V gdy włączone',
        ),
        MainPowerRail(
          name: 'Rdzeń SoC / MCU / CPU',
          description: 'Główny buck — napięcie zależne od obciążenia',
          measurementHint: 'Sprawdź nazwę sieci na schemacie',
        ),
        MainPowerRail(
          name: 'Pamięć',
          description: 'DDR / SRAM / flash supply',
          measurementHint: 'Typowo 1.2–1.5 V wg standardu',
        ),
        MainPowerRail(
          name: 'LDO pomocnicze',
          description: '1.0–2.5 V dla peryferiów',
          measurementHint: 'Porównaj z BOM',
        ),
      ],
      commonFaults: [
        'Brak napięcia wejściowego lub zwarcie na VIN',
        'Brak szyn pomocniczych — sekwencja PMIC/LDO',
        'Niestabilna przetwornica — MOSFET, dławik, kondensatory',
        'Uszkodzona ścieżka lub słabe GND',
        'Przegrzanie — zwarcie pod obciążeniem',
      ],
      startupSequence: [
        StartupStep(
          signal: 'Wejście zasilania',
          description: 'Potwierdź napięcie i pobór prądu',
        ),
        StartupStep(
          signal: 'Szyny 3V3 / 1V8',
          description: 'Pierwsze napięcia po PMIC lub LDO',
        ),
        StartupStep(
          signal: 'Reset / zegar',
          description: 'RESET, kwarc, ewentualnie PLL',
        ),
        StartupStep(
          signal: 'Główne przetwornice',
          description: 'Włączenie bucków pod kontrolą MCU',
        ),
        StartupStep(
          signal: 'Peryferia / interfejsy',
          description: 'Po stabilizacji rdzenia',
        ),
      ],
      confidence: 'low',
      source: DiagnosticProfileSource.genericTemplate,
    );
  }

  static DiagnosticProfile _genericPhone() {
    return const DiagnosticProfile(
      mainPowerRails: [
        MainPowerRail(
          name: 'VBAT / BATTERY',
          description: 'Cell or connector voltage',
          measurementHint: '3.7–4.4 V typical',
        ),
        MainPowerRail(
          name: 'VDD_MAIN / VDD_BOOST',
          description: 'Main system rail from PMIC',
          measurementHint: 'Often 3.8–4.5 V domain',
        ),
        MainPowerRail(
          name: 'VDD_CPU / SOC',
          description: 'SoC core supply',
          measurementHint: 'Low voltage, high current',
        ),
        MainPowerRail(
          name: 'VDD_GPU / MEM',
          description: 'Graphics / memory rail if separate',
        ),
        MainPowerRail(
          name: 'LDO peripherals',
          description: '1.8 V / 2.8 V camera, NFC, etc.',
        ),
      ],
      commonFaults: [
        'No boot — PMIC or battery detect',
        'Boot loop — CPU power collapse',
        'No display — backlight boost / Tigris line',
        'No charge — Tristar / Tigris / dock flex',
        'Baseband / RF — separate buck tree; check shorts',
      ],
      startupSequence: [
        StartupStep(
          signal: 'Battery / VBUS',
          description: 'Confirm fuel gauge and charger handshake',
        ),
        StartupStep(
          signal: 'PMIC power-on sequence',
          description: 'First enables after button or auto-boot',
        ),
        StartupStep(
          signal: 'VDD_MAIN',
          description: 'Main distribution up',
        ),
        StartupStep(
          signal: 'CPU reset release',
          description: 'AP reset line timing',
        ),
        StartupStep(
          signal: 'Clocks (32 kHz / BB)',
          description: 'Reference oscillators running',
        ),
      ],
      confidence: 'low',
      source: DiagnosticProfileSource.genericTemplate,
    );
  }

  static DiagnosticProfile _genericTablet() {
    return const DiagnosticProfile(
      mainPowerRails: [
        MainPowerRail(
          name: 'VBAT / DCIN',
          description: 'Battery or dock input',
        ),
        MainPowerRail(
          name: 'System 3V3 / 5V',
          description: 'Main PMIC outputs',
        ),
        MainPowerRail(
          name: 'SoC core',
          description: 'Application processor rail',
        ),
        MainPowerRail(
          name: 'DRAM',
          description: 'Memory supply',
        ),
        MainPowerRail(
          name: 'Display / backlight',
          description: 'Boost for panel (if separate)',
        ),
      ],
      commonFaults: [
        'No power — dock/charge port or PMIC',
        'Stuck logo — eMMC/UFS or RAM',
        'Touch dead — digitizer supply or connector',
        'No WiFi — RF section or enable GPIO',
      ],
      startupSequence: [
        StartupStep(
          signal: 'Input power',
          description: 'Adapter or battery present',
        ),
        StartupStep(
          signal: 'PMIC sequence',
          description: 'Ordered enables',
        ),
        StartupStep(
          signal: 'SoC power good',
          description: 'Core rails stable',
        ),
        StartupStep(
          signal: 'Reset / clock',
          description: 'Out of reset, clocks OK',
        ),
      ],
      confidence: 'low',
      source: DiagnosticProfileSource.genericTemplate,
    );
  }
}

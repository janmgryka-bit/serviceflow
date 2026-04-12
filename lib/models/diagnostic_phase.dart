/// Etap procedury warsztatowej — synchronizowany z polem JSON z asystenta.
enum DiagnosticPhase {
  /// Wejście zasilania, lab PSU, zwarcie / pobór prądu.
  powerInput,

  /// Szyny główne — Ω do masy, kolejno typowe punkty.
  mainRails,

  /// Zwężanie: PMIC, MOSFET-y, konkretne gałęzie.
  narrowing,

  /// Inne lub nie do zaklasyfikowania w tej turze.
  other,
}

DiagnosticPhase? diagnosticPhaseFromApi(String? raw) {
  if (raw == null) return null;
  switch (raw.trim().toLowerCase()) {
    case 'power_input':
    case 'power':
    case 'wejscie':
      return DiagnosticPhase.powerInput;
    case 'main_rails':
    case 'rails':
    case 'szyny':
      return DiagnosticPhase.mainRails;
    case 'narrowing':
    case 'zwezanie':
    case 'detail':
      return DiagnosticPhase.narrowing;
    case 'other':
    case 'inne':
      return DiagnosticPhase.other;
    default:
      return null;
  }
}

String diagnosticPhaseToApi(DiagnosticPhase p) {
  switch (p) {
    case DiagnosticPhase.powerInput:
      return 'power_input';
    case DiagnosticPhase.mainRails:
      return 'main_rails';
    case DiagnosticPhase.narrowing:
      return 'narrowing';
    case DiagnosticPhase.other:
      return 'other';
  }
}

extension DiagnosticPhaseX on DiagnosticPhase {
  String get labelPl {
    switch (this) {
      case DiagnosticPhase.powerInput:
        return 'PSU / pobór';
      case DiagnosticPhase.mainRails:
        return 'Ω (płyta OFF)';
      case DiagnosticPhase.narrowing:
        return 'Zwężanie';
      case DiagnosticPhase.other:
        return 'Inne';
    }
  }

  String get hintPl {
    switch (this) {
      case DiagnosticPhase.powerInput:
        return 'Lab: niski limit I, obserwacja CC / zwarcia — bez „max A”';
      case DiagnosticPhase.mainRails:
        return 'Ω do GND przy wyłączonym zasilaniu (goła płytа)';
      case DiagnosticPhase.narrowing:
        return 'PMIC, MOSFET, węższy obszar po szynach';
      case DiagnosticPhase.other:
        return 'Poza standardową ścieżką';
    }
  }
}

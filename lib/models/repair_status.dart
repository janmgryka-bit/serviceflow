/// Status naprawy w warsztacie (persistowany w SQLite + JSON projektu).
enum RepairStatus {
  /// Utworzono projekt; formalne potwierdzenie płyty jeszcze nie zakończone.
  open,

  /// Potwierdzona płytka — diagnoza / naprawa w toku.
  inDiagnosis,

  /// Naprawa zakończona pozytywnie.
  resolved,

  /// Nieopłacalna / nie do uratowania — decyzja warsztatu.
  noFix,

  /// Wstrzymane (części, klient, itp.).
  onHold,
}

RepairStatus? repairStatusFromStorage(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final v in RepairStatus.values) {
    if (v.name == raw) return v;
  }
  return null;
}

extension RepairStatusX on RepairStatus {
  /// Krótka etykieta PL do list i menu.
  String get labelPl {
    switch (this) {
      case RepairStatus.open:
        return 'Otwarta';
      case RepairStatus.inDiagnosis:
        return 'W diagnozie';
      case RepairStatus.resolved:
        return 'Naprawione';
      case RepairStatus.noFix:
        return 'Bez naprawy';
      case RepairStatus.onHold:
        return 'Wstrzymane';
    }
  }
}

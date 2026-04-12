import '../models/repair_project.dart';
import 'diagnostic_templates.dart';

/// Szablon kolejności pracy — lista kontrolna na start sesji (VIN → szyny → …).
abstract final class DiagnosticWorkflowTemplate {
  /// Propozycje punktów (nie zastępują odpowiedzi AI — są scalane na początku listy).
  static List<String> seedChecklist(RepairProject r) {
    final kind = DiagnosticTemplates.normalizeDeviceKind(r.deviceCategory);
    switch (kind) {
      case 'phone':
        return _phoneRails();
      case 'tablet':
        return _tabletRails();
      default:
        return _embeddedMainboardRails();
    }
  }

  static List<String> _embeddedMainboardRails() {
    return [
      '[Szablon] Wejście zasilania (VIN/BAT): zachowanie zasilacza lab. (limity U/I, czy wchodzi w CC / twarde zwarcie)',
      '[Szablon] Rezystancja Ω do masy na wejściu zasilania (przed mostkiem / przy złączu)',
      '[Szablon] Szyny „wysokie” / pośrednie — kolejno typowe testpady (np. standby 3V3, główne bucki)',
      '[Szablon] Dopiero po wykluczeniu zwarcia na głównej ścieżce — zwężanie (PMIC, MOSFET w gałęzi CPU/RAM)',
    ];
  }

  static List<String> _phoneRails() {
    return [
      '[Szablon] Bateria / VBAT: pobór, brak twardego zwarcia na gnieździe',
      '[Szablon] Ω do masy na głównych szynach po PMIC (VBAT → VDD_MAIN / typowe)',
      '[Szablon] Kolejne szyny systemowe przed szukaniem pojedynczych elementów',
    ];
  }

  static List<String> _tabletRails() {
    return [
      '[Szablon] Wejście zasilania / ładowanie: pobór i zwarcie',
      '[Szablon] Ω na głównych szynach zasilania',
      '[Szablon] Zwężanie po wykluczeniu zwarć na szynach',
    ];
  }
}

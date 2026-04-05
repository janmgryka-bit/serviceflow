/// Persisted workspace state for [DiagnosticDashboardScreen] (per repair id).
class DiagnosticSessionState {
  const DiagnosticSessionState({
    required this.aiRailOhm,
    required this.aiRailVolt,
    required this.startupChecked,
    required this.customMeasurements,
    required this.quickNotes,
  });

  final List<String> aiRailOhm;
  final List<String> aiRailVolt;
  final List<bool> startupChecked;
  final List<CustomMeasurementSnapshot> customMeasurements;
  final String quickNotes;

  static const int currentSchemaVersion = 1;

  Map<String, dynamic> toJson() => {
        'schemaVersion': currentSchemaVersion,
        'aiRailOhm': aiRailOhm,
        'aiRailVolt': aiRailVolt,
        'startupChecked': startupChecked,
        'customMeasurements': customMeasurements.map((e) => e.toJson()).toList(),
        'quickNotes': quickNotes,
      };

  factory DiagnosticSessionState.fromJson(Map<String, dynamic> json) {
    final ver = json['schemaVersion'] as int? ?? 1;
    if (ver != currentSchemaVersion) {
      // Forward-compatible: still parse fields we know.
    }
    final ohm = (json['aiRailOhm'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    final volt = (json['aiRailVolt'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    final start = (json['startupChecked'] as List<dynamic>?)
            ?.map((e) => e == true)
            .toList() ??
        <bool>[];
    final custom = (json['customMeasurements'] as List<dynamic>?)
            ?.map(
              (e) => CustomMeasurementSnapshot.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList() ??
        <CustomMeasurementSnapshot>[];
    return DiagnosticSessionState(
      aiRailOhm: ohm,
      aiRailVolt: volt,
      startupChecked: start,
      customMeasurements: custom,
      quickNotes: json['quickNotes'] as String? ?? '',
    );
  }

  /// Empty shell; caller merges lengths with live profile.
  factory DiagnosticSessionState.empty() {
    return const DiagnosticSessionState(
      aiRailOhm: [],
      aiRailVolt: [],
      startupChecked: [],
      customMeasurements: [],
      quickNotes: '',
    );
  }
}

class CustomMeasurementSnapshot {
  const CustomMeasurementSnapshot({
    required this.id,
    required this.name,
    required this.value,
    required this.unit,
  });

  final String id;
  final String name;
  final String value;

  /// `V` | `Ohm` | `Diode`
  final String unit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'value': value,
        'unit': unit,
      };

  factory CustomMeasurementSnapshot.fromJson(Map<String, dynamic> json) {
    return CustomMeasurementSnapshot(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      value: json['value'] as String? ?? '',
      unit: json['unit'] as String? ?? 'V',
    );
  }
}

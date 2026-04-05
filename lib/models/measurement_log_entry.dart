import 'package:uuid/uuid.dart';

/// Rodzaj pomiaru w dzienniku serwisowym.
enum MeasurementKind {
  voltage,
  resistance,
  current,
}

/// Zapisany pomiar (napięcie, rezystancja lub prąd) powiązany z naprawą / Board_ID.
class MeasurementLogEntry {
  MeasurementLogEntry({
    required this.id,
    required this.repairId,
    required this.measuredAt,
    required this.kind,
    required this.value,
    required this.unit,
    this.netLabel = '',
    this.note = '',
  });

  final String id;
  final String repairId;
  final DateTime measuredAt;
  final MeasurementKind kind;

  /// Wartość liczbowa w jednostce bazowej: V, Ω, A.
  final double value;
  final String unit;
  final String netLabel;
  final String note;

  factory MeasurementLogEntry.create({
    required String repairId,
    required MeasurementKind kind,
    required double value,
    required String unit,
    String netLabel = '',
    String note = '',
  }) {
    return MeasurementLogEntry(
      id: Uuid().v4(),
      repairId: repairId,
      measuredAt: DateTime.now(),
      kind: kind,
      value: value,
      unit: unit,
      netLabel: netLabel,
      note: note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'repairId': repairId,
        'measuredAt': measuredAt.toIso8601String(),
        'kind': kind.name,
        'value': value,
        'unit': unit,
        'netLabel': netLabel,
        'note': note,
      };

  factory MeasurementLogEntry.fromJson(Map<String, dynamic> json) {
    return MeasurementLogEntry(
      id: json['id'] as String,
      repairId: json['repairId'] as String,
      measuredAt: DateTime.parse(json['measuredAt'] as String),
      kind: MeasurementKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => MeasurementKind.voltage,
      ),
      value: (json['value'] as num).toDouble(),
      unit: json['unit'] as String? ?? '',
      netLabel: json['netLabel'] as String? ?? '',
      note: json['note'] as String? ?? '',
    );
  }

  String get kindLabelPl {
    switch (kind) {
      case MeasurementKind.voltage:
        return 'U';
      case MeasurementKind.resistance:
        return 'R';
      case MeasurementKind.current:
        return 'I';
    }
  }

  String get displayLine {
    final net = netLabel.trim().isEmpty ? '' : '$netLabel · ';
    return '$net$unit ($kindLabelPl)';
  }
}

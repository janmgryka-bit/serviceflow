import 'critical_chip_entry.dart';

class RepairProject {
  RepairProject({
    required this.id,
    required this.deviceCategory,
    required this.brand,
    required this.modelName,
    required this.boardModelCode,
    required this.components,
    required this.createdAt,
  });

  /// Stable unique identifier (e.g. UUID v4).
  final String id;
  final String deviceCategory;
  final String brand;
  final String modelName;
  final String boardModelCode;
  final List<CriticalChipEntry> components;
  final DateTime createdAt;

  String get displayTitle {
    final b = brand.trim();
    final m = modelName.trim();
    if (b.isEmpty) return m.isEmpty ? 'Repair' : m;
    return m.isEmpty ? b : '$b $m';
  }

  String get summaryLine => '$displayTitle · $boardModelCode';

  Map<String, dynamic> toJson() => {
        'schemaVersion': 2,
        'id': id,
        'deviceCategory': deviceCategory,
        'brand': brand,
        'modelName': modelName,
        'boardModelCode': boardModelCode,
        'components': components.map((c) => c.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory RepairProject.fromJson(Map<String, dynamic> json) {
    final ver = json['schemaVersion'] as int? ?? 1;
    if (ver >= 2) {
      final list = json['components'] as List<dynamic>? ?? [];
      return RepairProject(
        id: json['id'] as String,
        deviceCategory: json['deviceCategory'] as String? ?? '',
        brand: json['brand'] as String? ?? '',
        modelName: json['modelName'] as String? ?? '',
        boardModelCode: json['boardModelCode'] as String? ?? '',
        components: list
            .map(
              (e) => CriticalChipEntry.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
    }
    return RepairProject.fromLegacyJson(json);
  }

  /// v1 stored flat cpu/ethernet/revision fields.
  factory RepairProject.fromLegacyJson(Map<String, dynamic> json) {
    final components = <CriticalChipEntry>[
      CriticalChipEntry(
        label: 'CPU',
        value: (json['cpuModel'] as String?)?.trim() ?? '',
      ),
      CriticalChipEntry(
        label: 'Ethernet',
        value: (json['ethernetChip'] as String?)?.trim() ?? '',
      ),
      CriticalChipEntry(
        label: 'Revision',
        value: (json['revision'] as String?)?.trim() ?? '',
      ),
    ].where((c) => c.value.isNotEmpty).toList();

    return RepairProject(
      id: json['id'] as String,
      deviceCategory: 'Unknown',
      brand: '',
      modelName: (json['deviceModel'] as String?)?.trim() ?? '',
      boardModelCode: (json['boardModelCode'] as String?)?.trim() ?? '',
      components: components,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

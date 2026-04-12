import 'critical_chip_entry.dart';
import 'repair_status.dart';

class RepairProject {
  RepairProject({
    required this.id,
    required this.deviceCategory,
    required this.brand,
    required this.modelName,
    required this.boardModelCode,
    required this.components,
    required this.createdAt,
    this.repairStatus = RepairStatus.open,
    this.boardIdentityConfirmed = false,
    this.documentationUrl,
    this.documentationLocalPath,
  });

  /// Stable unique identifier (e.g. UUID v4).
  final String id;
  final String deviceCategory;
  final String brand;
  final String modelName;
  final String boardModelCode;
  final List<CriticalChipEntry> components;
  final DateTime createdAt;

  /// Status biznesowy naprawy (lista, raporty).
  final RepairStatus repairStatus;

  /// Formalne potwierdzenie: ta sama płytka / rewizja / krytyczne układy co na stole.
  final bool boardIdentityConfirmed;

  /// Opcjonalny link do schematu / boardview (wklejony przez technika lub z AI).
  final String? documentationUrl;

  /// Ścieżka do pliku lokalnego (PDF, obraz) — wybór z dysku.
  final String? documentationLocalPath;

  /// Kluczowy identyfikator płyty (kod PCB / silkscreen) — alias [boardModelCode].
  String get boardId => boardModelCode;

  String get displayTitle {
    final b = brand.trim();
    final m = modelName.trim();
    if (b.isEmpty) return m.isEmpty ? 'Repair' : m;
    return m.isEmpty ? b : '$b $m';
  }

  String get summaryLine => '$displayTitle · $boardModelCode';

  bool get hasDocumentationAttached {
    final u = documentationUrl?.trim() ?? '';
    final p = documentationLocalPath?.trim() ?? '';
    return u.isNotEmpty || p.isNotEmpty;
  }

  RepairProject copyWith({
    String? id,
    String? deviceCategory,
    String? brand,
    String? modelName,
    String? boardModelCode,
    List<CriticalChipEntry>? components,
    DateTime? createdAt,
    RepairStatus? repairStatus,
    bool? boardIdentityConfirmed,
    String? documentationUrl,
    String? documentationLocalPath,
    bool clearDocumentationUrl = false,
    bool clearDocumentationLocalPath = false,
  }) {
    return RepairProject(
      id: id ?? this.id,
      deviceCategory: deviceCategory ?? this.deviceCategory,
      brand: brand ?? this.brand,
      modelName: modelName ?? this.modelName,
      boardModelCode: boardModelCode ?? this.boardModelCode,
      components: components ?? this.components,
      createdAt: createdAt ?? this.createdAt,
      repairStatus: repairStatus ?? this.repairStatus,
      boardIdentityConfirmed: boardIdentityConfirmed ?? this.boardIdentityConfirmed,
      documentationUrl:
          clearDocumentationUrl ? null : (documentationUrl ?? this.documentationUrl),
      documentationLocalPath: clearDocumentationLocalPath
          ? null
          : (documentationLocalPath ?? this.documentationLocalPath),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 3,
        'id': id,
        'deviceCategory': deviceCategory,
        'brand': brand,
        'modelName': modelName,
        'boardModelCode': boardModelCode,
        'components': components.map((c) => c.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'repairStatus': repairStatus.name,
        'boardIdentityConfirmed': boardIdentityConfirmed,
        'documentationUrl': documentationUrl,
        'documentationLocalPath': documentationLocalPath,
      };

  factory RepairProject.fromJson(Map<String, dynamic> json) {
    final ver = json['schemaVersion'] as int? ?? 1;
    if (ver >= 2) {
      final list = json['components'] as List<dynamic>? ?? [];
      final legacy = ver < 3;
      final rs = repairStatusFromStorage(json['repairStatus'] as String?) ??
          (legacy ? RepairStatus.inDiagnosis : RepairStatus.open);
      final bic = json['boardIdentityConfirmed'] as bool? ?? legacy;
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
        repairStatus: rs,
        boardIdentityConfirmed: bic,
        documentationUrl: json['documentationUrl'] as String?,
        documentationLocalPath: json['documentationLocalPath'] as String?,
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
      repairStatus: RepairStatus.inDiagnosis,
      boardIdentityConfirmed: true,
      documentationUrl: null,
      documentationLocalPath: null,
    );
  }
}

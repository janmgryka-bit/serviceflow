import 'repair_status.dart';

/// Lightweight row for list views — minimal JSON decode when status columns exist.
class RepairSummary {
  const RepairSummary({
    required this.id,
    required this.boardId,
    required this.deviceLabel,
    required this.createdAt,
    this.repairStatus = RepairStatus.inDiagnosis,
    this.boardIdentityConfirmed = true,
  });

  final String id;

  /// Kluczowy identyfikator płyty (kod PCB / silkscreen) — to samo co [RepairProject.boardModelCode].
  final String boardId;

  /// Krótki opis urządzenia (marka / model / nazwa).
  final String deviceLabel;

  final DateTime createdAt;

  final RepairStatus repairStatus;

  /// Czy przeszło formalne potwierdzenie płyty przed diagnozą.
  final bool boardIdentityConfirmed;
}

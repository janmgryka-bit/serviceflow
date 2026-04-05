/// Lightweight row for list views — no JSON decode of full [RepairProject] payload.
class RepairSummary {
  const RepairSummary({
    required this.id,
    required this.boardId,
    required this.deviceLabel,
    required this.createdAt,
  });

  final String id;

  /// Kluczowy identyfikator płyty (kod PCB / silkscreen) — to samo co [RepairProject.boardModelCode].
  final String boardId;

  /// Krótki opis urządzenia (marka / model / nazwa).
  final String deviceLabel;

  final DateTime createdAt;
}

/// Response from the AI board identification lookup (mock or real API).
class AiBoardResearchResult {
  const AiBoardResearchResult({
    required this.summaryLine,
    required this.detectedBoards,
    required this.visualAidCaption,
    required this.boardIdLocationHint,
  });

  final String summaryLine;
  final List<DetectedBoard> detectedBoards;

  /// Shown above the image placeholder (e.g. typical print location).
  final String visualAidCaption;

  /// Longer hint for where to look for the board ID on this model family.
  final String boardIdLocationHint;

  Map<String, dynamic> toJson() => {
        'summaryLine': summaryLine,
        'visualAidCaption': visualAidCaption,
        'boardIdLocationHint': boardIdLocationHint,
        'detectedBoards': detectedBoards.map((b) => b.toJson()).toList(),
      };

  factory AiBoardResearchResult.fromJson(Map<String, dynamic> json) {
    final boards = json['detectedBoards'] as List<dynamic>? ?? [];
    return AiBoardResearchResult(
      summaryLine: json['summaryLine'] as String? ?? '',
      visualAidCaption: json['visualAidCaption'] as String? ?? '',
      boardIdLocationHint: json['boardIdLocationHint'] as String? ?? '',
      detectedBoards: boards
          .map((e) => DetectedBoard.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

/// One OEM / ODM board candidate for the typed model.
class DetectedBoard {
  const DetectedBoard({
    required this.id,
    required this.displayName,
    required this.boardCode,
    required this.identificationTip,
    required this.variants,
  });

  final String id;
  final String displayName;

  /// Stored on the repair (schematic / service tag style code).
  final String boardCode;

  /// Short tip for finding silkscreen / sticker (shown on the card).
  final String identificationTip;

  /// Shown in Step 3 after this board is selected.
  final List<AiCriticalVariant> variants;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'boardCode': boardCode,
        'identificationTip': identificationTip,
        'variants': variants.map((v) => v.toJson()).toList(),
      };

  factory DetectedBoard.fromJson(Map<String, dynamic> json) {
    final vars = json['variants'] as List<dynamic>? ?? [];
    return DetectedBoard(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      boardCode: json['boardCode'] as String,
      identificationTip: json['identificationTip'] as String,
      variants: vars
          .map(
            (e) => AiCriticalVariant.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
    );
  }
}

class AiCriticalVariant {
  const AiCriticalVariant({
    required this.id,
    required this.title,
    required this.label,
    required this.options,
  });

  final String id;
  final String title;
  final String label;
  final List<String> options;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'label': label,
        'options': options,
      };

  factory AiCriticalVariant.fromJson(Map<String, dynamic> json) {
    final opts = json['options'] as List<dynamic>? ?? [];
    return AiCriticalVariant(
      id: json['id'] as String,
      title: json['title'] as String,
      label: json['label'] as String,
      options: opts.map((e) => e.toString()).toList(),
    );
  }
}

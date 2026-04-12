import 'diagnostic_chat_message.dart';

/// Persisted UI state for [DiagnosticDashboardScreen] chat mode.
class DiagnosticChatSnapshot {
  const DiagnosticChatSnapshot({
    required this.messages,
    required this.checklist,
    required this.technicalPreview,
    required this.chatMode,
    required this.sessionComplete,
    this.diagnosticPhase,
  });

  final List<DiagnosticChatMessage> messages;
  final List<String> checklist;
  final String technicalPreview;
  final bool chatMode;
  final bool sessionComplete;

  /// Wartość z [diagnosticPhaseToApi] — etap procedury warsztatowej.
  final String? diagnosticPhase;

  static const int schemaVersion = 2;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'messages': messages.map((m) => m.toJson()).toList(),
        'checklist': checklist,
        'technicalPreview': technicalPreview,
        'chatMode': chatMode,
        'sessionComplete': sessionComplete,
        if (diagnosticPhase != null) 'diagnosticPhase': diagnosticPhase,
      };

  factory DiagnosticChatSnapshot.fromJson(Map<String, dynamic> json) {
    final msgList = json['messages'] as List<dynamic>? ?? [];
    return DiagnosticChatSnapshot(
      messages: msgList
          .map(
            (e) => DiagnosticChatMessage.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(),
      checklist: (json['checklist'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      technicalPreview: json['technicalPreview'] as String? ?? '',
      chatMode: json['chatMode'] as bool? ?? true,
      sessionComplete: json['sessionComplete'] as bool? ?? false,
      diagnosticPhase: json['diagnosticPhase'] as String?,
    );
  }

  factory DiagnosticChatSnapshot.fresh() {
    return const DiagnosticChatSnapshot(
      messages: [],
      checklist: [],
      technicalPreview: '',
      chatMode: true,
      sessionComplete: false,
      diagnosticPhase: null,
    );
  }
}

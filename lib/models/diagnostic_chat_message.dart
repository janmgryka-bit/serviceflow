/// One line in the interactive diagnostic chat.
class DiagnosticChatMessage {
  const DiagnosticChatMessage({
    required this.isUser,
    required this.text,
    this.localImagePath,
  });

  final bool isUser;
  final String text;

  /// Optional JPEG on disk (microscope capture). User messages only.
  final String? localImagePath;

  Map<String, dynamic> toJson() => {
        'isUser': isUser,
        'text': text,
        if (localImagePath != null) 'localImagePath': localImagePath,
      };

  factory DiagnosticChatMessage.fromJson(Map<String, dynamic> json) {
    return DiagnosticChatMessage(
      isUser: json['isUser'] as bool? ?? false,
      text: json['text'] as String? ?? '',
      localImagePath: json['localImagePath'] as String?,
    );
  }
}

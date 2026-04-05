/// AI- or template-generated diagnostic plan for a specific repair / board.
class DiagnosticProfile {
  const DiagnosticProfile({
    required this.mainPowerRails,
    required this.commonFaults,
    required this.startupSequence,
    this.confidence = 'low',
    this.source = DiagnosticProfileSource.genericTemplate,
  });

  final List<MainPowerRail> mainPowerRails;
  final List<String> commonFaults;
  final List<StartupStep> startupSequence;

  /// e.g. high | medium | low (from model, informational only).
  final String confidence;

  final DiagnosticProfileSource source;

  /// True only when JSON came from Groq and was parsed successfully.
  bool get isAiGenerated => source == DiagnosticProfileSource.groq;

  DiagnosticProfile copyWith({
    List<MainPowerRail>? mainPowerRails,
    List<String>? commonFaults,
    List<StartupStep>? startupSequence,
    String? confidence,
    DiagnosticProfileSource? source,
  }) {
    return DiagnosticProfile(
      mainPowerRails: mainPowerRails ?? this.mainPowerRails,
      commonFaults: commonFaults ?? this.commonFaults,
      startupSequence: startupSequence ?? this.startupSequence,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
    );
  }
}

enum DiagnosticProfileSource {
  groq,
  groqFallback,
  genericTemplate,
  noApiKey,
}

/// One row in LISTA POMIARÓW (Ω / V).
class MainPowerRail {
  const MainPowerRail({
    required this.name,
    this.description = '',
    this.measurementHint,
  });

  final String name;
  final String description;

  /// Optional expected range / diode note from AI.
  final String? measurementHint;
}

/// One ordered step in the bring-up checklist.
class StartupStep {
  const StartupStep({
    required this.signal,
    this.description = '',
  });

  final String signal;
  final String description;
}

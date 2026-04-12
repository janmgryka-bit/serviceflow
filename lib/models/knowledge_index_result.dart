/// Wynik indeksacji lokalnego PDF (baza wiedzy RAG).
class KnowledgeIndexResult {
  const KnowledgeIndexResult({
    required this.success,
    this.chunkCount = 0,
    this.message,
  });

  final bool success;
  final int chunkCount;

  /// Komunikat błędu lub informacja (np. brak tekstu w skanie).
  final String? message;
}

/// Metadane ostatnio zindeksowanego pliku (SQLite `knowledge_meta`).
class KnowledgeSourceMeta {
  const KnowledgeSourceMeta({
    required this.sourcePath,
    required this.indexedAt,
    required this.chunkCount,
  });

  final String sourcePath;
  final DateTime indexedAt;
  final int chunkCount;
}

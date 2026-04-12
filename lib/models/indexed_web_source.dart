/// Zindeksowany adres WWW (treść w FTS, metadane tutaj).
class IndexedWebSource {
  const IndexedWebSource({
    required this.id,
    required this.url,
    required this.title,
    required this.indexedAt,
    required this.chunkCount,
  });

  final String id;
  final String url;
  final String title;
  final DateTime indexedAt;
  final int chunkCount;
}

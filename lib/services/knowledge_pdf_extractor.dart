import 'package:pdfrx/pdfrx.dart';

/// Wyciąga zwykły tekst ze wszystkich stron PDF (Pdfium / pdfrx).
Future<String> extractPdfPlainText(String absolutePath) async {
  final doc = await PdfDocument.openFile(absolutePath);
  try {
    final buf = StringBuffer();
    for (final page in doc.pages) {
      final raw = await page.loadText();
      if (raw != null && raw.fullText.trim().isNotEmpty) {
        buf.writeln(raw.fullText);
      }
    }
    return buf.toString();
  } finally {
    await doc.dispose();
  }
}

/// Dzieli tekst na fragmenty pod FTS / RAG (~ [maxChars] znaków, łamanie przy spacji).
List<String> chunkPlainText(String text, {int maxChars = 1400}) {
  final t = text.replaceAll('\r', '').trim();
  if (t.isEmpty) return [];
  final chunks = <String>[];
  var i = 0;
  while (i < t.length) {
    var end = i + maxChars;
    if (end > t.length) end = t.length;
    if (end < t.length) {
      final slice = t.substring(i, end);
      final lastSpace = slice.lastIndexOf(' ');
      if (lastSpace > maxChars ~/ 2) {
        end = i + lastSpace;
      }
    }
    final piece = t.substring(i, end).trim();
    if (piece.isNotEmpty) chunks.add(piece);
    i = end;
  }
  return chunks;
}

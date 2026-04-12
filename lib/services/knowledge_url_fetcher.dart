import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class FetchedPageText {
  const FetchedPageText({required this.text, required this.title});

  final String text;
  final String title;
}

/// Pobiera stronę i wyciąga tekst widoczny (bez skryptów/styli).
Future<FetchedPageText> fetchUrlPlainText(String url) async {
  final uri = Uri.parse(url);
  final resp = await http.get(
    uri,
    headers: {
      'User-Agent':
          'Mozilla/5.0 (compatible; ServiceFlowAI/1.0; +https://example.local)',
      'Accept': 'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.8',
    },
  );
  if (resp.statusCode < 200 || resp.statusCode >= 300) {
    throw Exception('HTTP ${resp.statusCode}');
  }
  final body = resp.body;
  final ct = (resp.headers['content-type'] ?? '').toLowerCase();
  final looksHtml =
      ct.contains('text/html') ||
      ct.contains('application/xhtml') ||
      body.trimLeft().startsWith('<');
  if (!looksHtml) {
    return FetchedPageText(
      text: body.replaceAll(RegExp(r'\s+'), ' ').trim(),
      title: uri.host,
    );
  }
  final doc = html_parser.parse(body);
  doc
      .querySelectorAll('script,style,noscript,iframe,svg')
      .forEach((e) => e.remove());
  var title = doc.querySelector('title')?.text.trim() ?? '';
  if (title.isEmpty) {
    title = uri.host;
  }
  final bodyText = doc.body?.text ?? doc.documentElement?.text ?? '';
  final collapsed = bodyText.replaceAll(RegExp(r'\s+'), ' ').trim();
  return FetchedPageText(text: collapsed, title: title);
}

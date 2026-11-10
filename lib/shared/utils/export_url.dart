import 'dart:convert';

import '../../core/serialization/tryton_serializer.dart';

// URL export of the CSV export dialog (spec 11.9; Python client
// gui/window/win_export.py `WinExport.get_url`): the server's
// `/<db>/data/<model>` route with the export as query string, built
// character for character like the Python client.

/// The export URL (Python `get_url`): [domain] is the list of ids
/// (selected records) or the search domain; [limit]/[page] (`s`/`p`) only
/// for a search within the search limit; [order] gives one `o` per
/// expression (`field,ASC`); [context] (`c`) only when not empty; one `f`
/// per field in the chosen order; `enc` when set, `dl`, `qc`, `h=0`
/// without header, `loc=1` with the locale format. JSON as Python's
/// `json.dumps(…, separators=(',', ':'))` (ASCII only), the query as
/// `urllib.parse.urlencode`.
String exportUrl({
  required String baseUrl,
  required String database,
  required String model,
  required List<dynamic> domain,
  int? limit,
  int? page,
  List<dynamic> order = const [],
  Map<String, dynamic> context = const {},
  required List<String> fields,
  String? encoding,
  required String delimiter,
  required String quote,
  bool header = true,
  bool localeFormat = false,
}) {
  final query = <(String, String)>[
    ('d', pythonJson(domain)),
    if (limit != null && page != null) ...[
      ('s', '$limit'),
      ('p', '$page'),
    ],
    for (final expr in order)
      if (expr is List)
        ('o', [for (final e in expr) if (e != null && e != '') '$e'].join(',')),
    if (context.isNotEmpty) ('c', pythonJson(context)),
    for (final f in fields) ('f', f),
    if (encoding != null && encoding.isNotEmpty) ('enc', encoding),
    ('dl', delimiter),
    ('qc', quote),
    if (!header) ('h', '0'),
    if (localeFormat) ('loc', '1'),
  ];
  final queryString =
      [for (final (k, v) in query) '${quotePlus(k)}=${quotePlus(v)}'].join('&');
  return '${_origin(baseUrl)}/$database/data/$model?$queryString';
}

/// Scheme and host of [baseUrl] like Python `get_url`: the port is left
/// out only for http:80 and https:445 (sic, Python client 8.0); a path
/// of the base (reverse proxy) is kept.
String _origin(String baseUrl) {
  final uri = Uri.parse(baseUrl);
  final scheme = uri.scheme == 'https' ? 'https' : 'http';
  final port = uri.port;
  final netloc = (scheme == 'https' && port == 445) ||
          (scheme == 'http' && port == 80)
      ? uri.host
      : '${uri.host}:$port';
  final path = uri.path.endsWith('/')
      ? uri.path.substring(0, uri.path.length - 1)
      : uri.path;
  return '$scheme://$netloc$path';
}

/// [value] as Python `json.dumps(value, cls=JSONEncoder,
/// separators=(',', ':'))`: Tryton types as `__class__` objects, no
/// spaces, every non-ASCII character as `\uXXXX` (`ensure_ascii`).
String pythonJson(dynamic value) {
  final json = jsonEncode(TrytonSerializer.encode(value));
  final out = StringBuffer();
  for (final unit in json.codeUnits) {
    if (unit < 0x80) {
      out.writeCharCode(unit);
    } else {
      out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
    }
  }
  return out.toString();
}

/// Python `urllib.parse.quote_plus`: UTF-8, space as `+`, only
/// `A–Z a–z 0–9 _ . - ~` unescaped, `%XX` upper case.
String quotePlus(String text) {
  final out = StringBuffer();
  for (final byte in utf8.encode(text)) {
    final c = String.fromCharCode(byte);
    if (byte == 0x20) {
      out.write('+');
    } else if ((byte >= 0x30 && byte <= 0x39) ||
        (byte >= 0x41 && byte <= 0x5a) ||
        (byte >= 0x61 && byte <= 0x7a) ||
        c == '_' ||
        c == '.' ||
        c == '-' ||
        c == '~') {
      out.write(c);
    } else {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

import 'package:flutter_quill/quill_delta.dart';

// Rich text as stored by Tryton (spec 9.2.4, SAO `html_sanitizer.js`,
// Python `htmltextbuffer.py`): one `<div>` per line (`align` = left,
// center, right, justify), inline `<b>`, `<i>`, `<u>`, `<font color face
// size>`, `<br>` for an empty line. Only these tags and attributes are
// kept; other tags lose their markup but keep their text (`<script>` is
// dropped completely).

/// HTML `<font size>` (1–7) ↔ font size in px of the editor.
const htmlFontSizes = {
  '1': '10',
  '2': '13',
  '3': '16',
  '4': '18',
  '5': '24',
  '6': '32',
  '7': '48',
};

/// `<font face>` ↔ font family of the editor (Python `FAMILIES`).
const htmlFontFaces = {
  'sans': 'sans-serif',
  'serif': 'serif',
  'monospace': 'monospace',
};

const _aligns = {'left', 'center', 'right', 'justify'};

String _unescape(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&amp;', '&');

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll(' ', '&nbsp;');

Map<String, String> _attributes(String text) => {
      for (final m in RegExp(r'''([a-zA-Z-]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))''')
          .allMatches(text))
        m.group(1)!.toLowerCase(): _unescape(m.group(3) ?? m.group(4) ?? m.group(5) ?? ''),
    };

/// `#rgb`, `#rrggbb`, `#aarrggbb` → `#rrggbb`.
String? _hexColor(Object? value) {
  if (value is! String) return null;
  var v = value.trim().toLowerCase();
  if (!v.startsWith('#')) return v.isEmpty ? null : v;
  v = v.substring(1);
  if (v.length == 3) v = v.split('').map((c) => '$c$c').join();
  if (v.length == 8) v = v.substring(2);
  return v.length == 6 ? '#$v' : null;
}

/// The sanitized HTML of Tryton as editor delta.
Delta htmlToDelta(String? html) {
  final delta = Delta();
  final text = (html ?? '').replaceAll(RegExp(r'[\r\n]'), '').trim();
  if (text.isEmpty) return delta..insert('\n');

  // inline style stack: tag → attributes
  final stack = <(String, Map<String, dynamic>)>[];
  Map<String, dynamic> inline() {
    final a = <String, dynamic>{};
    for (final (_, attrs) in stack) {
      a.addAll(attrs);
    }
    return a;
  }

  String? align;
  var lineHasContent = false;
  var lineOpen = false;
  var skipDepth = 0; // inside <script>/<style>/<head>

  void endLine() {
    delta.insert('\n', align == null ? null : {'align': align});
    lineHasContent = false;
  }

  for (final m in RegExp(r'<(/?)([a-zA-Z0-9]+)([^>]*)>|([^<]+)').allMatches(text)) {
    final data = m.group(4);
    if (data != null) {
      if (skipDepth > 0) continue;
      final value = _unescape(data);
      if (value.isEmpty) continue;
      final attrs = inline();
      delta.insert(value, attrs.isEmpty ? null : attrs);
      lineHasContent = true;
      lineOpen = true;
      continue;
    }
    final closing = m.group(1) == '/';
    final tag = m.group(2)!.toLowerCase();
    final attrs = _attributes(m.group(3) ?? '');
    if (const {'script', 'style', 'head'}.contains(tag)) {
      skipDepth += closing ? -1 : 1;
      if (skipDepth < 0) skipDepth = 0;
      continue;
    }
    switch (tag) {
      case 'div':
        if (!closing) {
          // text before a div belongs to its own line
          if (lineOpen && lineHasContent) endLine();
          final a = attrs['align'];
          align = a != null && _aligns.contains(a) && a != 'left' ? a : null;
          lineOpen = true;
        } else {
          endLine();
          lineOpen = false;
          align = null;
        }
      case 'br':
        // <div><br></div> is an empty line (ended by </div>)
        if (lineHasContent) endLine();
      case 'b' || 'i' || 'u' || 'font':
        if (closing) {
          final i = stack.lastIndexWhere((e) => e.$1 == tag);
          if (i >= 0) stack.removeAt(i);
          break;
        }
        final style = <String, dynamic>{};
        if (tag == 'b') style['bold'] = true;
        if (tag == 'i') style['italic'] = true;
        if (tag == 'u') style['underline'] = true;
        if (tag == 'font') {
          final color = _hexColor(attrs['color']);
          if (color != null) style['color'] = color;
          final face = htmlFontFaces[attrs['face']];
          if (face != null) style['font'] = face;
          final size = htmlFontSizes[attrs['size']];
          if (size != null) style['size'] = size;
        }
        stack.add((tag, style));
      default:
        // other tags: only their text is kept
        break;
    }
  }
  if (lineOpen || delta.isEmpty) endLine();
  return delta;
}

/// The editor delta as sanitized Tryton HTML (Python
/// `htmltextbuffer.serialize` + `normalize_markup`): a `<div>` per line,
/// tags in alphabetical order (`b`, `font`, `i`, `u`).
String deltaToHtml(Delta delta) {
  final lines = <String>[];
  final line = StringBuffer();
  var empty = true;

  String open(Map<String, dynamic> a) {
    final out = StringBuffer();
    if (a['bold'] == true) out.write('<b>');
    final font = <String, String>{};
    final color = _hexColor(a['color']);
    if (color != null) font['color'] = color;
    final face = htmlFontFaces.entries
        .where((e) => e.value == a['font'])
        .map((e) => e.key)
        .firstOrNull;
    if (face != null) font['face'] = face;
    final px = a['size'] == null ? null : '${a['size']}';
    final size = htmlFontSizes.entries.where((e) => e.value == px).map((e) => e.key).firstOrNull;
    if (size != null) font['size'] = size;
    if (font.isNotEmpty) {
      final keys = font.keys.toList()..sort();
      out.write('<font${keys.map((k) => ' $k="${font[k]}"').join()}>');
    }
    if (a['italic'] == true) out.write('<i>');
    if (a['underline'] == true) out.write('<u>');
    return out.toString();
  }

  String close(Map<String, dynamic> a) {
    final out = StringBuffer();
    if (a['underline'] == true) out.write('</u>');
    if (a['italic'] == true) out.write('</i>');
    final hasFont = _hexColor(a['color']) != null ||
        htmlFontFaces.containsValue(a['font']) ||
        htmlFontSizes.containsValue(a['size'] == null ? null : '${a['size']}');
    if (hasFont) out.write('</font>');
    if (a['bold'] == true) out.write('</b>');
    return out.toString();
  }

  void finish(Map<String, dynamic>? attrs) {
    final align = attrs?['align'];
    final div = align is String && _aligns.contains(align) && align != 'left'
        ? '<div align="$align">'
        : '<div>';
    lines.add('$div${empty ? '<br>' : line}</div>');
    line.clear();
    empty = true;
  }

  for (final op in delta.toList()) {
    final data = op.data;
    if (data is! String) continue;
    final attrs = op.attributes ?? const <String, dynamic>{};
    final parts = data.split('\n');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isNotEmpty) {
        line.write('${open(attrs)}${_escape(part)}${close(attrs)}');
        empty = false;
      }
      if (i < parts.length - 1) finish(op.attributes);
    }
  }
  if (!empty) finish(null);
  // a single empty line is no content
  if (lines.length == 1 && lines.single == '<div><br></div>') return '';
  return lines.join();
}

/// Plain text of the HTML (readonly fallback, search).
String htmlToPlainText(String? html) {
  final buffer = StringBuffer();
  for (final op in htmlToDelta(html).toList()) {
    if (op.data is String) buffer.write(op.data);
  }
  return buffer.toString().replaceFirst(RegExp(r'\n$'), '');
}

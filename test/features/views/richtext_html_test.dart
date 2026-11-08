import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/views/richtext_html.dart';

/// Rich text HTML ↔ delta (SAO html_sanitizer.js, Python htmltextbuffer).
void main() {
  test('lines, alignment, inline tags and font attributes', () {
    final delta = htmlToDelta('<div align="center"><b>Bold</b> and '
        '<font color="#ff0000" face="monospace" size="5">red</font></div>\n'
        '<div><br></div><div><i><u>both</u></i></div>');
    expect(delta.toJson(), [
      {'insert': 'Bold', 'attributes': {'bold': true}},
      {'insert': ' and '},
      {
        'insert': 'red',
        'attributes': {'color': '#ff0000', 'font': 'monospace', 'size': '24'}
      },
      {'insert': '\n', 'attributes': {'align': 'center'}},
      {'insert': '\n'},
      {'insert': 'both', 'attributes': {'italic': true, 'underline': true}},
      {'insert': '\n'},
    ]);
  });

  test('round trip gives the normalized HTML (tags alphabetically)', () {
    const html = '<div align="center"><b>Bold</b> and '
        '<font color="#ff0000" size="5">red</font></div>'
        '<div><br></div><div><i><u>both</u></i></div>';
    expect(deltaToHtml(htmlToDelta(html)), html);
    // nested the other way round is normalized
    expect(deltaToHtml(htmlToDelta('<div><u><b>x</b></u></div>')),
        '<div><b><u>x</u></b></div>');
  });

  test('sanitizing: only whitelisted tags/attributes, script dropped', () {
    final html = deltaToHtml(htmlToDelta(
        '<div style="color:red" align="right" onclick="x()">'
        '<span>keep</span><script>alert(1)</script> <a href="h">link</a>'
        '</div><p>para</p>'));
    expect(html, '<div align="right">keep link</div><div>para</div>');
  });

  test('editor colors and escaping', () {
    final delta = Delta()
      ..insert('a<b & c', {'color': '#FF00FF00', 'bold': true})
      ..insert('\n', {'align': 'justify'});
    expect(deltaToHtml(delta),
        '<div align="justify"><b><font color="#00ff00">a&lt;b &amp; c</font></b></div>');
    expect(htmlToPlainText('<div>a &amp; b</div><div>c</div>'), 'a & b\nc');
  });

  test('empty values', () {
    expect(deltaToHtml(htmlToDelta('')), '');
    expect(deltaToHtml(htmlToDelta(null)), '');
    expect(deltaToHtml(htmlToDelta('<br>')), '');
    expect(deltaToHtml(htmlToDelta('plain text')), '<div>plain text</div>');
  });
}

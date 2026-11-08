import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/shared/utils/csv_format.dart';

/// CSV like Python's `csv` module and `WinExport.format_row` (spec 11.9).
void main() {
  test('rows: delimiter, quoting only when needed, \\r\\n', () {
    expect(csvText([
      ['a', 'b c', 1],
      ['x;y', 'say "hi"', null],
    ], delimiter: ';'), 'a;b c;1\r\n"x;y";"say ""hi""";\r\n');
    expect(csvRow(['multi\nline', 'b']), '"multi\nline",b');
    expect(csvRow(['']), '""', reason: 'single empty field stays a row');
    expect(csvRow(["it's"], quote: "'"), "'it''s'");
  });

  test('parse: quoted delimiters, quotes, line breaks; empty lines', () {
    final rows = parseCsv('Name,Note\r\n"A, B","say ""hi"""\n\n"x\ny",\n',
        delimiter: ',');
    expect(rows, [
      ['Name', 'Note'],
      ['A, B', 'say "hi"'],
      <String>[],
      ['x\ny', ''],
    ]);
    expect(parseCsv('a;b', delimiter: ';'), [
      ['a', 'b']
    ]);
  });

  test('header and indentation of the first column for paths', () {
    final header = formatCsvRow(['Name', 'Amount'], indent: 0);
    final child = formatCsvRow(['Child', 1.5], indent: 2);
    expect(header, ['Name', 'Amount']);
    expect(child, ['    Child', '1.5']);
    expect(csvText([header, child]), 'Name,Amount\r\n    Child,1.5\r\n');
    // only text is indented (with the locale format numbers are text)
    expect(formatCsvRow([5, 'x'], indent: 1, localeFormat: false), [5, 'x']);
    expect(formatCsvRow([5, 'x'], indent: 1), ['  5', 'x']);
  });

  test('locale format: decimal point, dates; without: raw values', () {
    final ctx = {'decimal_point': ',', 'date_format': '%d.%m.%Y'};
    expect(
        formatCsvRow([
          1234.5,
          const TrytonDecimal('10.50'),
          const TrytonDate(2026, 1, 2),
          true,
          3,
        ], context: ctx),
        ['1234,5', '10,5', '02.01.2026', '1', '3']);
    expect(
        formatCsvRow([
          1.0,
          true,
          const Duration(hours: 1),
          DateTime.utc(2026, 1, 2, 3, 4, 5),
          TrytonBytes('hi'.codeUnits),
        ], localeFormat: false),
        [1.0, 1, 3600.0, '2026-01-02 03:04:05', 'aGk=']);
    expect(csvRow([1.0, 3600.0]), '1.0,3600.0');
  });

  test('encodings: utf_8_sig writes and skips the BOM, ascii fails', () {
    final bytes = csvEncode('ä', 'utf_8_sig');
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    expect(csvDecode(bytes, 'utf_8_sig'), 'ä');
    expect(csvDecode(csvEncode('ä', 'latin_1'), 'latin_1'), 'ä');
    expect(() => csvEncode('ä', 'ascii'), throwsFormatException);
  });

  test('import values: locale numbers and dates, binary', () {
    final ctx = {'decimal_point': ',', 'thousands_sep': '.', 'date_format': '%d.%m.%Y'};
    expect(parseCsvValue('1.234', 'integer', context: ctx), 1234);
    expect(parseCsvValue('1.234,5', 'float', context: ctx), 1234.5);
    expect(parseCsvValue('10,50', 'numeric', context: ctx),
        const TrytonDecimal('10.50'));
    expect(parseCsvValue('02.01.2026', 'date', context: ctx),
        const TrytonDate(2026, 1, 2));
    expect((parseCsvValue('aGk=', 'binary') as TrytonBytes).bytes, 'hi'.codeUnits);
    expect(parseCsvValue('x', 'char', context: ctx), 'x');
    expect(parseCsvValue('1,5', 'float', localeFormat: false), '1,5');
    expect(() => parseCsvValue('abc', 'integer'), throwsFormatException);
  });
}

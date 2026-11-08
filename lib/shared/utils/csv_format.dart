import 'dart:convert';
import 'dart:typed_data';

import '../../core/domain/date_text.dart';
import '../../core/serialization/tryton_serializer.dart';

/// CSV like Python's `csv` module (dialect `excel`, QUOTE_MINIMAL,
/// `\r\n`) for the CSV export and import (spec 11.8, 11.9, Python
/// `win_csv.py`, `win_export.py`, `win_import.py`).

/// Encodings of the CSV dialogs (Python names; `utf_8_sig` writes and
/// skips the BOM).
const csvEncodings = ['utf_8_sig', 'utf_8', 'latin_1', 'ascii'];

/// One CSV row: fields with [delimiter], [quote] or a line break are
/// quoted, quotes inside doubled (Python `csv.writer`).
String csvRow(List<Object?> row, {String delimiter = ',', String quote = '"'}) {
  String cell(Object? v) {
    final s = v == null ? '' : '$v';
    if (s.contains(delimiter) ||
        s.contains(quote) ||
        s.contains('\n') ||
        s.contains('\r')) {
      return '$quote${s.replaceAll(quote, '$quote$quote')}$quote';
    }
    return s;
  }

  // a single empty field is written quoted (else the row is lost)
  if (row.length == 1 && cell(row.single).isEmpty) return '$quote$quote';
  return row.map(cell).join(delimiter);
}

/// The CSV text of [rows] (`\r\n` after each row).
String csvText(Iterable<List<Object?>> rows,
        {String delimiter = ',', String quote = '"'}) =>
    rows.map((r) => '${csvRow(r, delimiter: delimiter, quote: quote)}\r\n').join();

/// Rows of a CSV text (Python `csv.reader`): quoted fields may contain
/// delimiters, doubled quotes and line breaks; empty lines give `[]`.
List<List<String>> parseCsv(String text,
    {String delimiter = ',', String quote = '"'}) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  var started = false; // the row has content (else an empty line)
  var i = 0;
  void endCell() {
    row.add(cell.toString());
    cell.clear();
  }

  void endRow() {
    if (started || row.isNotEmpty) endCell();
    rows.add(row);
    row = <String>[];
    started = false;
  }

  while (i < text.length) {
    final c = text[i];
    if (quoted) {
      if (c == quote) {
        if (i + 1 < text.length && text[i + 1] == quote) {
          cell.write(quote);
          i += 2;
          continue;
        }
        quoted = false;
      } else {
        cell.write(c);
      }
      i++;
      continue;
    }
    if (c == quote && cell.isEmpty) {
      quoted = true;
      started = true;
    } else if (c == delimiter) {
      started = true;
      endCell();
    } else if (c == '\r' || c == '\n') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      started = true;
      cell.write(c);
    }
    i++;
  }
  if (started || row.isNotEmpty || cell.isNotEmpty) endRow();
  return rows;
}

/// Bytes of [text] in [encoding]; throws [FormatException] for characters
/// the encoding cannot store (Python `UnicodeEncodeError`).
Uint8List csvEncode(String text, String encoding) {
  try {
    return switch (encoding) {
      'utf_8_sig' =>
        Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]),
      'latin_1' => latin1.encode(text),
      'ascii' => ascii.encode(text),
      _ => utf8.encode(text),
    };
  } on ArgumentError catch (e) {
    throw FormatException('$encoding: ${e.message}');
  }
}

/// Text of CSV [bytes] in [encoding] (the BOM is skipped for UTF-8).
String csvDecode(List<int> bytes, String encoding) {
  switch (encoding) {
    case 'latin_1':
      return latin1.decode(bytes);
    case 'ascii':
      return ascii.decode(bytes);
    default:
      final start = bytes.length >= 3 &&
              bytes[0] == 0xEF &&
              bytes[1] == 0xBB &&
              bytes[2] == 0xBF
          ? 3
          : 0;
      return utf8.decode(bytes.sublist(start));
  }
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Python `str(datetime)` (`2026-01-02 03:04:05[.ffffff]`).
String _pythonDateTime(DateTime v) {
  final micro = v.millisecond * 1000 + v.microsecond;
  return '${v.year.toString().padLeft(4, '0')}-${_two(v.month)}-${_two(v.day)} '
      '${_two(v.hour)}:${_two(v.minute)}:${_two(v.second)}'
      '${micro == 0 ? '' : '.${micro.toString().padLeft(6, '0')}'}';
}

/// Python `locale.str` (`%.12g`, without grouping).
String _localeStr(double v) {
  if (!v.isFinite) return '$v';
  if (v == v.truncateToDouble() && v.abs() < 1e12) return v.toInt().toString();
  var s = v.toStringAsPrecision(12);
  if (s.contains('e')) return s;
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s;
}

/// A row of `export_data` for the CSV file (Python `WinExport.format_row`):
/// with [localeFormat] numbers get the decimal point of the preferences
/// ([context] `decimal_point`, no grouping like `locale.str`), dates the
/// `date_format` (datetime local + ` %X`), timedeltas the duration text;
/// without it timedeltas are seconds, booleans 0/1, datetimes UTC.
/// The first column is indented by two blanks per [indent] (hierarchical
/// paths), bytes are base64.
List<Object?> formatCsvRow(List<dynamic> line,
    {int indent = 0, bool localeFormat = true, Map? context}) {
  final point = context?['decimal_point'] is String &&
          (context!['decimal_point'] as String).isNotEmpty
      ? context['decimal_point'] as String
      : '.';
  final dateFormat = context?['date_format'] is String &&
          (context!['date_format'] as String).isNotEmpty
      ? context['date_format'] as String
      : '%x';
  final row = <Object?>[];
  for (var i = 0; i < line.length; i++) {
    Object? val = line[i];
    if (localeFormat) {
      if (val is bool) {
        // Python: bool is a Number → locale.str(True) = '1'
        val = val ? '1' : '0';
      } else if (val is num || val is TrytonDecimal) {
        val = _localeStr(val is num ? val.toDouble() : (val as TrytonDecimal).toDouble())
            .replaceAll('.', point);
      } else if (val is DateTime) {
        val = strftime(val.toLocal(), '$dateFormat %X');
      } else if (val is TrytonDate) {
        val = strftime(val.toDateTime(), dateFormat);
      } else if (val is Duration) {
        val = formatTimedelta(val, const {'s': 1, 'm': 60, 'h': 3600});
      }
    } else if (val is Duration) {
      val = val.inMicroseconds / 1e6;
    } else if (val is bool) {
      val = val ? 1 : 0;
    } else if (val is DateTime) {
      val = _pythonDateTime(val.toUtc());
    }
    if (i == 0 && indent > 0 && val is String) val = '${'  ' * indent}$val';
    if (val is TrytonBytes) val = base64.encode(val.bytes);
    row.add(val);
  }
  return row;
}

/// A CSV value for `import_data` (Python `WinImport.import_csv`): with
/// [localeFormat] numbers and dates are read in the format of the
/// preferences, binary from base64; else the text is sent unchanged.
Object? parseCsvValue(String val, String? type,
    {bool localeFormat = true, Map? context}) {
  if (!localeFormat || val.isEmpty) return val;
  final point = context?['decimal_point'] is String &&
          (context!['decimal_point'] as String).isNotEmpty
      ? context['decimal_point'] as String
      : '.';
  final sep = context?['thousands_sep'] is String
      ? context!['thousands_sep'] as String
      : '';
  final dateFormat = context?['date_format'] is String &&
          (context!['date_format'] as String).isNotEmpty
      ? context['date_format'] as String
      : '%x';
  String delocalize(String v) {
    var s = sep.isEmpty ? v : v.replaceAll(sep, '');
    if (point != '.') s = s.replaceAll(point, '.');
    return s.trim();
  }

  FormatException invalid() => FormatException('invalid $type: "$val"');
  switch (type) {
    case 'integer':
      return int.tryParse(delocalize(val)) ?? (throw invalid());
    case 'float':
      return double.tryParse(delocalize(val)) ?? (throw invalid());
    case 'numeric':
      final s = delocalize(val);
      if (num.tryParse(s) == null) throw invalid();
      return TrytonDecimal(s);
    case 'date':
      final d = strptime(val, dateFormat) ?? (throw invalid());
      return TrytonDate.fromDateTime(d);
    case 'datetime':
      return strptime(val, '$dateFormat %X') ?? (throw invalid());
    case 'binary':
      return TrytonBytes(base64.decode(val));
  }
  return val;
}

/// Search text ↔ domain (spec 03-pyson-domains.md 7.3): port of the Python
/// client's `tryton/common/domain_parser.py` 8.0 (the main reference),
/// checked against SAO's `Sao.common.DomainParser`. Function names follow
/// the Python module so both can be read side by side.
///
/// Syntax: `Label: value`, operators `= != < <= > >= !`, lists `a;b`,
/// ranges `a..b`, `|` (or), parentheses, free text → `rec_name ilike`.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../serialization/tryton_serializer.dart';
import 'date_text.dart';

const operators = ['!=', '<=', '>=', '=', '!', '<', '>'];

/// A nested group (Python: a generator / iterator).
class _Gen {
  final List<Object?> items;
  _Gen(this.items);
}

/// A clause (Python: a tuple) – distinct from nested lists.
class _Clause {
  final List<Object?> parts;
  _Clause(this.parts);
  int get length => parts.length;
  Object? operator [](int i) => parts[i];
}

class _NoClosingQuotation implements Exception {}

// ── Lexer (Python `shlex` in posix mode with the parser's wordchars) ───────

const _specials = {':', '>', '<', '=', '!', '"', ';', '(', ')'};
const _whitespace = {' ', '\t', '\r', '\n'};

/// Tokens of [input] (Python `udlex`). Throws [_NoClosingQuotation].
List<String> udlex(String input) {
  final tokens = <String>[];
  final chars = input.split('');
  var pos = 0;
  String? pushback;
  String read() {
    if (pushback != null) {
      final c = pushback!;
      pushback = null;
      return c;
    }
    return pos < chars.length ? chars[pos++] : '';
  }

  while (true) {
    var state = ' ';
    var token = '';
    var quoted = false;
    var escapedState = ' ';
    String? result;
    while (true) {
      final next = read();
      if (state == ' ') {
        if (next.isEmpty) break;
        if (_whitespace.contains(next)) {
          if (token.isNotEmpty || quoted) break;
          continue;
        }
        if (next == r'\') {
          escapedState = 'a';
          state = next;
        } else if (!_specials.contains(next)) {
          token = next;
          state = 'a';
        } else if (next == '"') {
          state = '"';
        } else {
          token = next;
          break;
        }
      } else if (state == '"') {
        quoted = true;
        if (next.isEmpty) throw _NoClosingQuotation();
        if (next == '"') {
          state = 'a';
        } else if (next == r'\') {
          escapedState = '"';
          state = next;
        } else {
          token += next;
        }
      } else if (state == r'\') {
        if (next.isEmpty) throw _NoClosingQuotation();
        if (escapedState == '"' && next != state && next != escapedState) {
          token += state;
        }
        token += next;
        state = escapedState;
      } else {
        // word
        if (next.isEmpty) break;
        if (_whitespace.contains(next)) {
          if (token.isNotEmpty || quoted) break;
          state = ' ';
          continue;
        }
        if (next == '"') {
          state = '"';
        } else if (next == r'\') {
          escapedState = 'a';
          state = next;
        } else if (!_specials.contains(next)) {
          token += next;
        } else {
          pushback = next;
          if (token.isNotEmpty || quoted) break;
          state = ' ';
        }
      }
    }
    result = token;
    if (!quoted && result.isEmpty) {
      if (pos >= chars.length && pushback == null) break;
      continue;
    }
    tokens.add(result);
  }
  return tokens;
}

// ── Helpers ────────────────────────────────────────────────────────────────

/// Groups `<`/`>`/`!` with a following `=` (Python `group_operator`).
List<String> groupOperator(List<String> tokens) {
  final out = <String>[];
  if (tokens.isEmpty) return out;
  String? cur = tokens.first;
  for (final nex in tokens.skip(1)) {
    if (nex == '=' && cur != null && cur.isNotEmpty &&
        operators.contains(cur + nex)) {
      out.add(cur + nex);
      cur = null;
    } else {
      if (cur != null) out.add(cur);
      cur = nex;
    }
  }
  if (cur != null) out.add(cur);
  return out;
}

/// Adds `%` when [value] has no wildcard (Python `likify`).
String likify(String? value, [String escape = r'\']) {
  if (value == null || value.isEmpty) return '%';
  final escaped =
      value.replaceAll('$escape%', '').replaceAll('${escape}_', '');
  if (escaped.contains('%') || escaped.contains('_')) return value;
  return '%$value%';
}

/// Python `value[1:-1]`.
String _inner(String value) =>
    value.length >= 2 ? value.substring(1, value.length - 1) : '';

bool isFullText(String value, [String escape = r'\']) {
  var escaped = value;
  if (escaped.startsWith('%') && escaped.endsWith('%') && escaped.length > 1) {
    escaped = escaped.substring(1, escaped.length - 1);
  } else if (escaped == '%') {
    escaped = '';
  }
  escaped = escaped.replaceAll('$escape%', '').replaceAll('${escape}_', '');
  if (escaped.contains('%') || escaped.contains('_')) return false;
  return value.startsWith('%') && value.endsWith('%');
}

bool isLike(String value, [String escape = r'\']) {
  final escaped =
      value.replaceAll('$escape%', '').replaceAll('${escape}_', '');
  return escaped.contains('%') || escaped.contains('_');
}

String unescape(String value, [String escape = r'\']) =>
    value.replaceAll('$escape%', '%').replaceAll('${escape}_', '_');

/// Quotes [value] when needed (Python `quote`); non-strings unchanged.
dynamic quote(dynamic value, {bool empty = false}) {
  if (value is! String) return value;
  if (empty && value == '') return '""';
  var v = value;
  if (v.contains(r'\')) v = v.replaceAll(r'\', r'\\');
  if (v.contains('"')) v = v.replaceAll('"', r'\"');
  for (final test in [':', ' ', '(', ')', ...operators]) {
    if (v.contains(test)) return '"$v"';
  }
  return v;
}

String _stripSlice(String s, int deep) {
  if (deep == 0) return s;
  final stop = -deep;
  if (stop < 0) return s.substring(0, math.max(0, s.length + stop));
  return s.substring(0, math.min(s.length, stop));
}

(dynamic, int) _endingClause(List domain, [int deep = 0]) {
  if (domain.isEmpty) return (null, deep);
  final last = domain.last;
  if (last is List) return _endingClause(last, deep + 1);
  return (last, deep);
}

List _replaceEndingClause(List domain, dynamic clause) => [
      ...domain.sublist(0, domain.length - 1),
      if (domain.last is List)
        _replaceEndingClause(domain.last as List, clause)
      else
        clause,
    ];

List _appendEndingClause(List domain, dynamic clause, int deep) {
  if (domain.isEmpty) return [clause];
  return [
    ...domain.sublist(0, domain.length - 1),
    if (domain.last is List)
      _appendEndingClause(domain.last as List, clause, deep - 1)
    else ...[
      domain.last,
      if (deep == 0) clause,
    ],
  ];
}

/// Default operator of a field (Python `default_operator`).
String defaultOperator(Map field) {
  const like = {
    'char', 'text', 'many2one', 'many2many', 'one2many', 'reference',
    'one2one'
  };
  if (like.contains(field['type'])) return 'ilike';
  if (field['type'] == 'multiselection') return 'in';
  return '=';
}

String? negateOperator(String operator) => switch (operator) {
      'ilike' => 'not ilike',
      '=' => '!=',
      'in' => 'not in',
      _ => null,
    };

String _timeFormat(Map field) {
  final format = field['format'];
  if (format is String) {
    try {
      final decoded = jsonDecode(format);
      if (decoded is String) return decoded;
    } catch (_) {
      return format;
    }
  }
  return '%H:%M:%S';
}

String _dateFormat(Map? context) {
  final f = context?['date_format'];
  return f is String && f.isNotEmpty ? f : '%x';
}

List<List<dynamic>> _selection(Map field) {
  final s = field['selection'];
  return [
    if (s is List)
      for (final e in s)
        if (e is List && e.length >= 2) [e[0], e[1]]
  ];
}

/// Splits a reference value `Model,text` into target and value (Python
/// `split_target_value`).
(dynamic, dynamic) splitTargetValue(Map field, dynamic value) {
  dynamic target;
  if (value is String) {
    for (final [key, text] in _selection(field)) {
      if (value.toLowerCase().startsWith('${'$text'.toLowerCase()},')) {
        target = key;
        value = (value as String).substring('$text'.length + 1);
        break;
      }
    }
  }
  return (target, value);
}

// ── Numbers with the locale of the preferences ─────────────────────────────

String _decimalPoint(Map? context) {
  final v = context?['decimal_point'];
  return v is String && v.isNotEmpty ? v : '.';
}

String _thousandsSep(Map? context) {
  final v = context?['thousands_sep'];
  return v is String ? v : '';
}

/// `locale.delocalize`: without grouping, decimal point → `.`.
String _delocalize(String value, Map? context) {
  var v = value;
  final sep = _thousandsSep(context);
  if (sep.isNotEmpty) v = v.replaceAll(sep, '');
  final point = _decimalPoint(context);
  if (point != '.') v = v.replaceAll(point, '.');
  return v;
}

double? _atof(String value, Map? context) {
  final v = _delocalize(value, context);
  if (!RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$').hasMatch(v) &&
      !RegExp(r'^[+-]?(inf|infinity|nan)$', caseSensitive: false)
          .hasMatch(v)) {
    return null;
  }
  return double.tryParse(v);
}

/// `locale.localize(text, grouping)`: decimal point and grouping.
String _localize(String text, Map? context) {
  var negative = text.startsWith('-');
  var t = negative ? text.substring(1) : text;
  final parts = t.split('.');
  var integer = parts[0];
  final sep = _thousandsSep(context);
  if (sep.isNotEmpty && integer.length > 3) {
    final buf = StringBuffer();
    for (var i = 0; i < integer.length; i++) {
      if (i > 0 && (integer.length - i) % 3 == 0) buf.write(sep);
      buf.write(integer[i]);
    }
    integer = buf.toString();
  }
  t = parts.length > 1 ? '$integer${_decimalPoint(context)}${parts[1]}' : integer;
  return negative ? '-$t' : t;
}

double _factor(Map field) =>
    double.tryParse('${field['factor'] ?? 1}') ?? 1;

/// Shortest decimal text of [value] (for Decimal results).
String _decimalText(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  var s = value.toString();
  if (s.contains('e')) s = value.toStringAsFixed(20);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

// ── convert_value / format_value / complete_value ─────────────────────────

/// Value of the search text [value] for [field] (Python `convert_value`).
dynamic convertValue(Map field, dynamic value, [Map? context]) {
  context ??= const {};
  switch (field['type']) {
    case 'boolean':
      if (value is String) {
        final lower = value.toLowerCase();
        return ['y', 'Yes', 'True', 't', '1']
            .any((test) => test.toLowerCase().startsWith(lower));
      }
      return null;
    case 'float':
      if (value is! String) return null;
      final f = _atof(value.replaceAll(' ', ''), context);
      return f == null ? null : f / _factor(field);
    case 'integer':
      if (value is! String) return null;
      final f = _atof(value.replaceAll(' ', ''), context);
      return f == null ? null : (f / _factor(field)).truncate();
    case 'numeric':
      if (value is! String) return null;
      final text = _delocalize(value.replaceAll(' ', ''), context);
      if (!RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$').hasMatch(text)) {
        return null;
      }
      final factor = _factor(field);
      if (factor == 1) return TrytonDecimal(text);
      return TrytonDecimal(_decimalText(double.parse(text) / factor));
    case 'selection' || 'multiselection':
      if (value is String) {
        for (final [key, text] in _selection(field)) {
          if (value.toLowerCase() == '$text'.toLowerCase()) return key;
        }
      }
      return value;
    case 'datetime' || 'timestamp':
      if (value is! String || value.isEmpty) return null;
      final dt = dateParse(
          value, '${_dateFormat(context)} ${_timeFormat(field)}');
      return dt?.toUtc();
    case 'date':
      if (value is! String || value.isEmpty) return null;
      final dt = dateParse(value, _dateFormat(context));
      return dt == null ? null : TrytonDate(dt.year, dt.month, dt.day);
    case 'time':
      if (value is! String || value.isEmpty) return null;
      final dt = dateParse(value);
      return dt == null
          ? null
          : TrytonTime(dt.hour, dt.minute, dt.second, dt.microsecond);
    case 'timedelta':
      final converter = context[field['converter']];
      return parseTimedelta(value is String ? value : null,
          converter is Map ? converter.cast<String, num>() : null);
    case 'many2one':
      return value == '' ? null : value;
    case 'reference':
      if (value == '') return null;
      return convertValue({...field, 'type': 'selection'}, value, context);
  }
  return value;
}

/// Search text of [value] for [field] (Python `format_value`).
String formatValue(Map field, dynamic value,
    {dynamic target, Map? context, bool quoteEmpty = false}) {
  context ??= const {};
  if (value is List) {
    return value
        .map((v) => formatValue(field, v, context: context, quoteEmpty: true))
        .join(';');
  }
  dynamic text;
  switch (field['type']) {
    case 'boolean':
      text = value == false ? 'False' : (value == null ? '' : 'True');
      if (value != false && value != null && !_truthy(value)) text = '';
    case 'integer':
      if (value is num && value is! bool) {
        text = '${(value * _factor(field)).truncate()}';
      } else {
        text = '';
      }
    case 'float' || 'numeric':
      text = _formatFloat(field, value, context);
    case 'selection' || 'multiselection':
      text = _formatSelection(field, value);
    case 'reference':
      if (!_truthy(target)) {
        text = _formatSelection(field, value);
      } else {
        final labels = {for (final [k, t] in _selection(field)) k: t};
        text = '${labels[target] ?? target},${value ?? ''}';
      }
    case 'datetime' || 'timestamp':
      if (!_truthy(value)) {
        text = '';
      } else {
        final DateTime time;
        if (value is TrytonDate) {
          time = DateTime(value.year, value.month, value.day);
        } else {
          time = (value as DateTime).toLocal();
        }
        var format = _dateFormat(context);
        if (time.hour != 0 || time.minute != 0 || time.second != 0 ||
            time.millisecond != 0 || time.microsecond != 0) {
          format += ' ${_timeFormat(field)}';
        }
        text = strftime(time, format);
      }
    case 'date':
      if (value is TrytonDate) {
        text = strftime(DateTime(value.year, value.month, value.day),
            _dateFormat(context));
      } else if (value is DateTime) {
        text = strftime(value, _dateFormat(context));
      } else {
        text = '';
      }
    case 'time':
      if (value is TrytonTime) {
        text = strftime(
            DateTime(2000, 1, 1, value.hour, value.minute, value.second, 0,
                value.microsecond),
            _timeFormat(field));
      } else {
        text = '';
      }
    case 'timedelta':
      if (value is Duration && value != Duration.zero) {
        final converter = context[field['converter']];
        text = formatTimedelta(value,
            converter is Map ? converter.cast<String, num>() : null);
      } else {
        text = '';
      }
    case 'many2one':
      text = value ?? '';
    default:
      text = value ?? '';
  }
  final quoted = quote(text, empty: quoteEmpty);
  return '${quoted ?? ''}';
}

bool _truthy(dynamic v) =>
    v != null && v != false && v != '' && v != 0 && !(v is List && v.isEmpty);

String _formatSelection(Map field, dynamic value) {
  final labels = {for (final [k, t] in _selection(field)) k: t};
  final result = labels.containsKey(value) ? labels[value] : value;
  return _truthy(result) ? '$result' : '';
}

String _formatFloat(Map field, dynamic value, Map? context) {
  final isNumber = value is num || value is TrytonDecimal;
  if (value is bool || !isNumber) return '';
  final double number;
  var digit = 0;
  String text;
  if (value is TrytonDecimal) {
    text = value.value;
    number = value.toDouble();
  } else {
    number = (value as num).toDouble();
    text = value is int ? '$value' : _pyRepr(number);
  }
  if (text.contains('e') || text.contains('E')) {
    final parts = text.toLowerCase().split('e');
    text = parts[0];
    digit -= int.parse(parts[1]);
  }
  if (text.contains('.')) {
    final decimals = text.replaceFirst(RegExp(r'0+$'), '').split('.');
    digit += decimals.length > 1 ? decimals[1].length : 0;
  }
  final factor = _factor(field);
  digit -= (math.log(factor) / math.ln10).round();
  digit = math.max(digit, 0);
  return _localize((number * factor).toStringAsFixed(digit), context);
}

/// Python `str(float)` (shortest repr, `1e-12`, `1.0`).
String _pyRepr(double value) {
  final s = value.toString();
  return s;
}

/// Completions of [value] for [field] (Python `complete_value`).
List<dynamic> completeValue(Map field, dynamic value) {
  switch (field['type']) {
    case 'boolean':
      if (value == null) return [true, false];
      return _truthy(value) ? [false] : [true];
    case 'selection' || 'multiselection':
      var test = value is List ? (value.last ?? '') : (value ?? '');
      test = '$test'.replaceAll(RegExp(r'^%+|%+$'), '');
      return [
        for (final [key, text] in _selection(field))
          if ('$text'.toLowerCase().startsWith('$test'.toLowerCase()))
            value is List ? [...value.sublist(0, value.length - 1), key] : key
      ];
    case 'reference':
      var test = value is List ? value.last : (value ?? '');
      test = '$test'.replaceAll(RegExp(r'^%+|%+$'), '');
      return [
        for (final [key, text] in _selection(field))
          if ('$text'.toLowerCase().startsWith('$test'.toLowerCase()))
            value is List
                ? [...value.sublist(0, value.length - 1), key]
                : likify('$key')
      ];
    case 'datetime' || 'timestamp':
      final now = DateTime.now();
      return [TrytonDate(now.year, now.month, now.day), now.toUtc()];
    case 'date':
      final now = DateTime.now();
      return [TrytonDate(now.year, now.month, now.day)];
    case 'time':
      final now = DateTime.now();
      return [TrytonTime(now.hour, now.minute, now.second, now.microsecond)];
  }
  return const [];
}

// ── Structure ──────────────────────────────────────────────────────────────

/// Nests tokens by parentheses (Python `parenthesize`).
List<Object?> parenthesize(List<Object?> tokens) {
  var i = 0;
  List<Object?> nest() {
    final out = <Object?>[];
    while (i < tokens.length) {
      final token = tokens[i++];
      if (token == '(') {
        out.add(_Gen(nest()));
      } else if (token == ')') {
        break;
      } else {
        out.add(token);
      }
    }
    return out;
  }

  return nest();
}

class _Stop implements Exception {}

/// Converts `|` (or `&`) into `OR`/`AND` groups (Python `operatorize`).
List<Object?> operatorize(List<Object?> tokens, [String operator = 'or']) {
  final symbol = operator == 'or' ? '|' : '&';
  bool isTest(Object? x) =>
      x == symbol ||
      (x is _Clause && x.length == 1 && x[0] == symbol);
  final op = operator.toUpperCase();
  final out = <Object?>[];
  var k = 0;
  Object? next() {
    if (k >= tokens.length) throw _Stop();
    return tokens[k++];
  }

  Object? sub(Object? x) => x is _Gen ? _Gen(operatorize(x.items, operator)) : x;

  Object? cur;
  try {
    cur = next();
    while (isTest(cur)) {
      cur = next();
    }
  } on _Stop {
    return out;
  }
  cur = sub(cur);
  Object? nex;
  while (k < tokens.length) {
    nex = sub(tokens[k++]);
    if (isTest(nex)) {
      try {
        nex = next();
        while (isTest(nex)) {
          nex = next();
        }
        nex = sub(nex);
        cur = _Gen([op, cur, nex]);
      } on _Stop {
        if (!isTest(cur)) {
          out.add(_Gen([op, cur]));
          cur = null;
        }
      }
      nex = null;
    } else {
      if (!isTest(cur)) out.add(cur);
      cur = nex;
    }
  }
  if (nex != null && !isTest(nex)) {
    out.add(nex);
  } else if (cur != null && !isTest(cur)) {
    out.add(cur);
  }
  return out;
}

/// Lists for nested groups, clauses stay [_Clause] (Python `rlist`).
List<Object?> _rlist(List<Object?> value) => [
      for (final x in value)
        if (x is _Gen) _rlist(x.items) else x
    ];

/// Removes double nesting (Python `simplify`).
dynamic _simplify(dynamic value) {
  if (value is List) {
    if (value.length == 1 && value[0] is List) return _simplify(value[0]);
    if (value.length == 2 &&
        (value[0] == 'AND' || value[0] == 'OR') &&
        value[1] is List) {
      return _simplify(value[1]);
    }
    if (value.length == 3 &&
        (value[0] == 'AND' || value[0] == 'OR') &&
        value[1] is List &&
        value[0] == (value[1] as List).first) {
      value = [...(_simplify(value[1]) as List), value[2]];
    }
    return [for (final x in value) _simplify(x)];
  }
  return value;
}

/// Clauses as lists (the public domain format).
dynamic _toDomain(dynamic value) {
  if (value is _Clause) return [for (final p in value.parts) p];
  if (value is List) return [for (final x in value) _toDomain(x)];
  return value;
}

// ── DomainParser ───────────────────────────────────────────────────────────

/// Parser of search texts for the fields of a view (Python
/// `DomainParser`). [fields] are field descriptions (`string`, `type`,
/// `selection`, `factor`, `format`, `converter`, `relation_fields`,
/// `searchable`); [context] holds `date_format`, `decimal_point`,
/// `thousands_sep` and timedelta converters.
class DomainParser {
  final LinkedHashMap<String, Map<String, dynamic>> fields =
      LinkedHashMap();
  final LinkedHashMap<String, Map<String, dynamic>> strings =
      LinkedHashMap();
  final Map? context;

  DomainParser(Map<String, dynamic> fields, [this.context]) {
    void update(Map fields, String prefix, String stringPrefix) {
      for (final MapEntry(:key, :value) in fields.entries) {
        if (value is! Map) continue;
        if (value['searchable'] == false) continue;
        final field = Map<String, dynamic>.from(value);
        final fullname = [if (prefix.isNotEmpty) prefix, '$key'].join('.');
        final string = [
          if (stringPrefix.isNotEmpty) stringPrefix,
          '${field['string'] ?? key}'
        ].join('.');
        field['string'] = string;
        field['name'] = fullname;
        this.fields[fullname] = field;
        strings[string.toLowerCase()] = field;
        final rfields = field['relation_fields'];
        if (rfields is Map && rfields.isNotEmpty) {
          update(rfields, fullname, string);
        }
      }
    }

    update(fields, '', '');
  }

  /// Domain of the search text (Python `parse`).
  List<dynamic> parse(String input) => _toDomain(_parse(input)) as List;

  List<dynamic> _parse(String input) {
    List<String> tokens;
    try {
      tokens = udlex(input);
    } on _NoClosingQuotation {
      return _parse('$input"');
    }
    final nested = parenthesize(groupOperator(tokens));
    final grouped = group(nested);
    final ored = operatorize(grouped, 'or');
    final anded = operatorize(ored, 'and');
    final clauses = parseClause(anded);
    return _simplify(_rlist(clauses)) as List;
  }

  /// Whether [domain] can be written as search text.
  bool stringable(List domain) {
    bool stringable_(dynamic clause) {
      if (clause is! List || clause.isEmpty) return true;
      if ((clause[0] == 'AND' || clause[0] == 'OR' || clause[0] is List) &&
          clause.skip(1).every((c) => c is List)) {
        return stringable(clause);
      }
      if (clause.length < 3) return false;
      var name = '${clause[0]}';
      final value = clause[2];
      if (name.endsWith('.rec_name') && _truthy(value)) {
        name = name.substring(0, name.length - '.rec_name'.length);
      }
      final field = fields[name];
      if (field != null) {
        final type = field['type'];
        if (const {'many2one', 'one2one', 'one2many', 'many2many'}
            .contains(type)) {
          bool ok(dynamic v) => v == null || v is String;
          return value is List ? value.every(ok) : ok(value);
        }
        if (type == 'multiselection') {
          return !_truthy(value) || value is List;
        }
        return true;
      }
      return name == 'rec_name';
    }

    if (domain.isEmpty) return true;
    final clauses = (domain[0] == 'AND' || domain[0] == 'OR')
        ? domain.sublist(1)
        : domain;
    return clauses.every(stringable_);
  }

  /// Search text of [domain] (Python `string`).
  String string(List domain) {
    String string_(dynamic clause) {
      if (clause is _Clause) clause = clause.parts;
      if (clause is! List || clause.isEmpty) return '';
      if (clause[0] is! String || clause[0] == 'AND' || clause[0] == 'OR') {
        return '(${string(clause)})';
      }
      var name = clause[0] as String;
      var operator = '${clause[1]}';
      dynamic value = clause[2];
      if (name.endsWith('.rec_name') &&
          (_truthy(value) || clause.length > 3)) {
        name = name.substring(0, name.length - 9);
      }
      final field = fields[name];
      if (field == null) {
        if (value is String && isFullText(value)) {
          value = _inner(value);
        }
        return '${quote(value) ?? ''}';
      }
      final target = clause.length > 3 ? clause[3] : null;
      if (operator.contains('ilike') && value is String) {
        if (isFullText(value)) {
          value = _inner(value);
        } else if (!isLike(value)) {
          operator = operator == 'ilike' ? '=' : '!';
          value = unescape(value);
        }
      }
      final defOperator = defaultOperator(field);
      if (defOperator == operator.trim()) {
        operator = '';
        if (operators.contains(value)) {
          // The value could be read as an operator: force the default one.
          operator = '"" ';
        }
      } else if (operator.contains(defOperator) &&
          (operator.contains('not') || operator.contains('!'))) {
        operator = _rstripChars(operator, defOperator)
            .replaceAll('not', '!')
            .trim();
      }
      if (operator.endsWith('in')) {
        if (value is List && value.length == 1) {
          operator = operator == 'not in' ? '!=' : '=';
        } else {
          operator = operator == 'not in' ? '!' : '';
        }
      }
      var formatted =
          formatValue(field, value, target: target, context: context);
      if (operators.contains(operator) &&
          const {'char', 'text', 'selection'}.contains(field['type']) &&
          value == '') {
        formatted = '""';
      }
      return '${quote(field['string'])}: $operator$formatted';
    }

    if (domain.isEmpty) return '';
    var nary = ' ';
    var clauses = domain;
    if (domain[0] == 'AND' || domain[0] == 'OR') {
      nary = domain[0] == 'AND' ? ' ' : ' | ';
      clauses = domain.sublist(1);
    }
    return clauses.map(string_).join(nary);
  }

  /// Python `str.rstrip(chars)`.
  static String _rstripChars(String s, String chars) {
    var end = s.length;
    while (end > 0 && chars.contains(s[end - 1])) {
      end--;
    }
    return s.substring(0, end);
  }

  /// Completions of the search text (Python `completion`).
  List<String> completion(String input) {
    final result = <String>[];
    final domain = _parse(input);
    var closing = 0;
    for (var i = 1; i < input.length; i++) {
      final c = input[input.length - i];
      if (c != ')' && c != ' ') break;
      if (c == ')') closing++;
    }
    final (ending, deepEnding) = _endingClause(domain);
    final deep = deepEnding - closing;
    final text = _stripSlice(string(domain), deep);
    if (text != input) result.add(text);
    if (ending != null && closing == 0) {
      for (final complete in _complete(ending as _Clause)) {
        result.add(_stripSlice(
            string(_replaceEndingClause(domain, complete)), deep));
      }
    }
    if (input.isNotEmpty) {
      if (input[input.length - 1] != ' ') return result;
      if (input.length >= 2 && input[input.length - 2] == ':') return result;
    }
    for (final field in strings.values) {
      final operator = defaultOperator(field);
      final value = operator.contains('ilike') ? likify('') : '';
      result.add(_stripSlice(
          string(_appendEndingClause(
              domain, _Clause([field['name'], operator, value]), deep)),
          deep));
    }
    return result;
  }

  /// Completions of one clause (Python `complete`).
  List<_Clause> _complete(_Clause clause) {
    String? name;
    String? operator;
    dynamic value;
    if (clause.length == 1) {
      name = clause[0] as String?;
    } else if (clause.length == 3) {
      name = clause[0] as String?;
      operator = clause[1] as String?;
      value = clause[2];
    } else {
      name = clause[0] as String?;
      operator = clause[1] as String?;
      value = clause[2];
      if (name != null && name.endsWith('.rec_name') && _truthy(value)) {
        name = name.substring(0, name.length - 9);
      }
      value = clause[3];
    }
    if (name == 'rec_name') {
      if (operator == 'ilike' && value is String) {
        final escaped = value.replaceAll('%%', '__');
        if (escaped.startsWith('%') && escaped.endsWith('%')) {
          value = _inner(value);
        } else if (!escaped.contains('%')) {
          value = value.replaceAll('%%', '%');
        }
        operator = null;
      }
      name = value is String ? value : '$value';
      value = '';
    }
    name ??= '';
    final out = <_Clause>[];
    if (!strings.containsKey(name.toLowerCase()) && !fields.containsKey(name)) {
      for (final field in strings.values) {
        if ('${field['string']}'.toLowerCase().startsWith(name.toLowerCase())) {
          final op = defaultOperator(field);
          out.add(_Clause([field['name'], op, op.contains('ilike') ? likify('') : '']));
        }
      }
      return out;
    }
    final field = fields[name] ?? strings[name.toLowerCase()]!;
    if (operator == null || operator.isEmpty) {
      final op = defaultOperator(field);
      out.add(_Clause([field['name'], op, op.contains('ilike') ? likify('') : '']));
    } else {
      for (final comp in completeValue(field, value)) {
        out.add(_Clause([field['name'], operator, comp]));
      }
    }
    return out;
  }

  /// Groups tokens into clauses (Python `group`).
  List<Object?> group(List<Object?> tokens) {
    Iterable<_Clause> groupParts(List<Object?> parts) sync* {
      var i = parts.indexOf(':');
      if (i < 0) {
        for (final part in parts) {
          yield _Clause([part]);
        }
        return;
      }
      for (var j = 0; j < i; j++) {
        final name = parts.sublist(j, i).join(' ');
        if (!strings.containsKey(name.toLowerCase())) continue;
        if (j > 0) {
          for (final part in parts.sublist(0, j)) {
            yield _Clause([part]);
          }
        } else {
          yield _Clause([null]);
        }
        List<Object?>? nameParts = [name];
        // empty string is also the default operator
        if (i + 1 < parts.length &&
            (operators.contains(parts[i + 1]) || parts[i + 1] == '')) {
          nameParts.add(parts[i + 1]);
          i += 1;
        } else {
          nameParts.add(null);
        }
        final lvalue = <Object?>[];
        while (i + 2 < parts.length) {
          if (parts[i + 2] == ';') {
            lvalue.add(parts[i + 1]);
            i += 2;
          } else {
            break;
          }
        }
        for (final part in groupParts(parts.sublist(i + 1))) {
          if (nameParts != null) {
            if (lvalue.isNotEmpty) {
              if (part[0] != null) lvalue.add(part[0]);
              yield _Clause([...nameParts, lvalue]);
            } else {
              yield _Clause([...nameParts, ...part.parts]);
            }
            nameParts = null;
          } else {
            yield part;
          }
        }
        if (nameParts != null) {
          yield _Clause([...nameParts, if (lvalue.isNotEmpty) lvalue else null]);
        }
        break;
      }
    }

    bool isNone(_Clause c) => c.length == 1 && c[0] == null;
    final out = <Object?>[];
    var parts = <Object?>[];
    for (final token in tokens) {
      if (token is _Gen) {
        out.addAll(groupParts(parts).where((g) => !isNone(g)));
        parts = [];
        out.add(_Gen(group(token.items)));
      } else {
        parts.add(token);
      }
    }
    out.addAll(groupParts(parts).where((g) => !isNone(g)));
    return out;
  }

  /// Clauses into domain leaves (Python `parse_clause`).
  List<Object?> parseClause(List<Object?> tokens) {
    final out = <Object?>[];
    for (final clause in tokens) {
      if (clause is _Gen) {
        out.add(_Gen(parseClause(clause.items)));
      } else if (clause == 'OR' || clause == 'AND') {
        out.add(clause);
      } else if (clause is _Clause) {
        if (clause.length == 1) {
          out.add(_Clause(['rec_name', 'ilike', likify('${clause[0]}')]));
          continue;
        }
        final name = '${clause[0]}';
        var operator = clause[1] as String?;
        dynamic value = clause[2];
        final field = strings[name.toLowerCase()]!;
        var fieldName = field['name'] as String;
        final type = field['type'];
        dynamic target;
        if (type == 'reference') {
          (target, value) = splitTargetValue(field, value);
          if (target != null) fieldName += '.rec_name';
        } else if (type == 'multiselection') {
          if (value != null && value is! List) value = [value];
        }
        if (operator == null || operator.isEmpty) {
          operator = defaultOperator(field);
        }
        if (value is List && type != 'multiselection') {
          operator = operator == '!' ? 'not in' : 'in';
        }
        if (operator == '!') {
          operator = negateOperator(defaultOperator(field))!;
        }
        if (value == null && operator.endsWith('in')) {
          operator = operator.startsWith('not') ? '!=' : '=';
        }
        if (const {
          'integer', 'float', 'numeric', 'datetime', 'timestamp', 'date',
          'time'
        }.contains(type)) {
          if (value is String && value.contains('..')) {
            final idx = value.indexOf('..');
            final lvalue = convertValue(field, value.substring(0, idx), context);
            final rvalue =
                convertValue(field, value.substring(idx + 2), context);
            out.add(_Gen([
              _Clause([fieldName, '>=', lvalue]),
              _Clause([fieldName, '<=', rvalue]),
            ]));
            continue;
          }
          if (value is String &&
              (type == 'datetime' || type == 'timestamp') &&
              operator == '=') {
            final dt = strptime(value, _dateFormat(context));
            if (dt != null) {
              final date = DateTime(dt.year, dt.month, dt.day).toUtc();
              final nextDate =
                  DateTime(dt.year, dt.month, dt.day + 1).toUtc();
              out.add(_Gen([
                _Clause([fieldName, '>=', date]),
                _Clause([fieldName, '<', nextDate]),
              ]));
              continue;
            }
          }
        }
        if (const {'many2one', 'one2many', 'many2many', 'one2one'}
                .contains(type) &&
            _truthy(value)) {
          fieldName += '.rec_name';
        }
        if (value is List) {
          value = [for (final v in value) convertValue(field, v, context)];
        } else {
          value = convertValue(field, value, context);
        }
        if (operator.contains('like')) value = likify(value as String?);
        out.add(_Clause([
          fieldName,
          operator,
          value,
          ?target,
        ]));
      }
    }
    return out;
  }
}

// ── Test access (the Python tests call the steps directly) ─────────────────

/// A nested group in test input (Python: `iter([...])`); plain lists are
/// clauses (Python tuples).
@visibleForTesting
class TestGroup {
  final List<Object?> items;
  const TestGroup(this.items);
}

Object? _testIn(Object? x) => switch (x) {
      TestGroup() => _Gen([for (final i in x.items) _testIn(i)]),
      List() => _Clause(x),
      _ => x,
    };

/// Groups and clauses as lists (Python `rlist` + tuples as lists).
Object? _testOut(Object? x) => switch (x) {
      _Gen() => [for (final i in x.items) _testOut(i)],
      _Clause() => [for (final p in x.parts) p],
      List() => [for (final i in x) _testOut(i)],
      _ => x,
    };

@visibleForTesting
List<Object?> debugParenthesize(List<String> tokens) =>
    _testOut(parenthesize(tokens)) as List<Object?>;

@visibleForTesting
List<Object?> debugOperatorize(List<Object?> tokens,
        [String operator = 'or']) =>
    _testOut(operatorize([for (final t in tokens) _testIn(t)], operator))
        as List<Object?>;

@visibleForTesting
List<Object?> debugGroup(DomainParser parser, String text) =>
    _testOut(parser.group(udlex(text))) as List<Object?>;

@visibleForTesting
List<Object?> debugParseClause(DomainParser parser, List<Object?> tokens) =>
    _testOut(parser.parseClause([for (final t in tokens) _testIn(t)]))
        as List<Object?>;

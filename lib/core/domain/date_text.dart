/// Date/time text like Python `strftime`/`strptime` and the Python
/// client's `date_parse` (dateutil fallback), and timedelta text
/// (`tryton/common/timedelta.py`), for the DomainParser (spec 7.3).
library;

/// `%x`/`%X`/`%c` of the C locale (default `date_format`).
String expandFormat(String format) => format
    .replaceAll('%x', '%m/%d/%y')
    .replaceAll('%X', '%H:%M:%S')
    .replaceAll('%c', '%a %b %d %H:%M:%S %Y');

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December'
];
const _days = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
  'Sunday'
];

String _pad(int value, [int width = 2]) =>
    value.toString().padLeft(width, '0');

/// Python `strftime` for the usual directives.
String strftime(DateTime value, String format) {
  final f = expandFormat(format);
  final out = StringBuffer();
  for (var i = 0; i < f.length; i++) {
    final c = f[i];
    if (c != '%' || i + 1 >= f.length) {
      out.write(c);
      continue;
    }
    final d = f[++i];
    out.write(switch (d) {
      'd' => _pad(value.day),
      'm' => _pad(value.month),
      'Y' => _pad(value.year, 4),
      'y' => _pad(value.year % 100),
      'H' => _pad(value.hour),
      'I' => _pad(value.hour % 12 == 0 ? 12 : value.hour % 12),
      'p' => value.hour < 12 ? 'AM' : 'PM',
      'M' => _pad(value.minute),
      'S' => _pad(value.second),
      'f' => _pad(value.millisecond * 1000 + value.microsecond, 6),
      'b' => _months[value.month - 1].substring(0, 3),
      'B' => _months[value.month - 1],
      'a' => _days[value.weekday - 1].substring(0, 3),
      'A' => _days[value.weekday - 1],
      'j' => _pad(
          value.difference(DateTime(value.year)).inDays + 1, 3),
      '%' => '%',
      _ => '%$d',
    });
  }
  return out.toString();
}

/// Python `strptime`: the whole [text] must match [format]; null if not.
DateTime? strptime(String text, String format) {
  final f = expandFormat(format);
  final pattern = StringBuffer('^');
  final groups = <String>[];
  for (var i = 0; i < f.length; i++) {
    final c = f[i];
    if (c != '%' || i + 1 >= f.length) {
      pattern.write(c == ' ' ? r'\s+' : RegExp.escape(c));
      continue;
    }
    final d = f[++i];
    final re = switch (d) {
      'd' || 'm' || 'H' || 'M' || 'S' || 'I' => r'(\d{1,2})',
      'Y' => r'(\d{4})',
      'y' => r'(\d{2})',
      'f' => r'(\d{1,6})',
      'p' => r'(AM|PM|am|pm)',
      'j' => r'(\d{1,3})',
      _ => null,
    };
    if (re == null) {
      pattern.write(RegExp.escape(d == '%' ? '%' : '%$d'));
      continue;
    }
    pattern.write(re);
    groups.add(d);
  }
  pattern.write(r'$');
  final match = RegExp(pattern.toString()).firstMatch(text.trim());
  if (match == null) return null;
  var year = 1900, month = 1, day = 1, hour = 0, minute = 0, second = 0;
  var micro = 0;
  var pm = false, hasPm = false;
  for (var g = 0; g < groups.length; g++) {
    final v = match.group(g + 1)!;
    switch (groups[g]) {
      case 'd':
        day = int.parse(v);
      case 'm':
        month = int.parse(v);
      case 'Y':
        year = int.parse(v);
      case 'y':
        final y = int.parse(v);
        year = y < 69 ? 2000 + y : 1900 + y;
      case 'H' || 'I':
        hour = int.parse(v);
      case 'M':
        minute = int.parse(v);
      case 'S':
        second = int.parse(v);
      case 'f':
        micro = int.parse(v.padRight(6, '0'));
      case 'p':
        hasPm = true;
        pm = v.toUpperCase() == 'PM';
    }
  }
  if (hasPm) hour = hour % 12 + (pm ? 12 : 0);
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 ||
      minute > 59 || second > 61) {
    return null;
  }
  final result =
      DateTime(year, month, day, hour, minute, second, 0, micro);
  if (result.month != month || result.day != day) return null;
  return result;
}

/// Python client `date_parse(text, format)`: `strptime`, else a flexible
/// parse (dateutil) with the day/month/year order of [format]; null when
/// the text is no date.
DateTime? dateParse(String text, [String format = '%x']) {
  final exact = strptime(text, format);
  if (exact != null) return exact;
  final sample = strftime(DateTime(1988, 7, 16), format);
  final dayFirst = sample.indexOf('16') == 0;
  final monthIdx = sample.indexOf('7');
  final monthFirst = monthIdx >= 0 && monthIdx <= 1;
  final yearFirst = !dayFirst && !monthFirst;
  return _flexParse(text, dayFirst: dayFirst, yearFirst: yearFirst);
}

DateTime? _flexParse(String text,
    {required bool dayFirst, required bool yearFirst}) {
  var rest = text.trim();
  if (rest.isEmpty) return null;
  int? hour, minute, second, micro;
  final time = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2})(?:[.,](\d{1,6}))?)?')
      .firstMatch(rest);
  if (time != null) {
    hour = int.parse(time.group(1)!);
    minute = int.parse(time.group(2)!);
    second = int.tryParse(time.group(3) ?? '') ?? 0;
    micro = int.tryParse((time.group(4) ?? '').padRight(6, '0')) ?? 0;
    rest = rest.replaceRange(time.start, time.end, ' ');
  }
  // Only digits, separators and am/pm may remain.
  final words = RegExp(r'[A-Za-z]+').allMatches(rest).map((m) => m[0]!);
  var pm = false;
  for (final w in words) {
    final lower = w.toLowerCase();
    if (lower == 'pm') {
      pm = true;
    } else if (lower != 'am') {
      return null;
    }
  }
  final numbers = [
    for (final m in RegExp(r'\d+').allMatches(rest)) m[0]!,
  ];
  if (numbers.isEmpty && time == null) return null;
  if (hour != null && pm && hour < 12) hour += 12;
  final now = DateTime.now();
  int year = now.year, month = now.month, day = now.day;
  int fixYear(String v) {
    final y = int.parse(v);
    if (v.length > 2) return y;
    final century = now.year ~/ 100 * 100;
    var full = century + y;
    if (full >= now.year + 50) full -= 100;
    if (full < now.year - 50) full += 100;
    return full;
  }

  if (numbers.length >= 3) {
    final n = numbers.sublist(0, 3);
    final yearAt = n.indexWhere((v) => v.length == 4);
    if (yearAt == 0 || (yearAt < 0 && yearFirst)) {
      year = fixYear(n[0]);
      month = int.parse(n[1]);
      day = int.parse(n[2]);
    } else if (dayFirst) {
      day = int.parse(n[0]);
      month = int.parse(n[1]);
      year = fixYear(n[2]);
    } else {
      month = int.parse(n[0]);
      day = int.parse(n[1]);
      year = fixYear(n[2]);
    }
  } else if (numbers.length == 2) {
    final a = int.parse(numbers[0]), b = int.parse(numbers[1]);
    if (dayFirst) {
      day = a;
      month = b;
    } else {
      month = a;
      day = b;
    }
  } else if (numbers.length == 1) {
    day = int.parse(numbers[0]);
  }
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if ((hour ?? 0) > 23 || (minute ?? 0) > 59 || (second ?? 0) > 59) {
    return null;
  }
  final result = DateTime(
      year, month, day, hour ?? 0, minute ?? 0, second ?? 0, 0, micro ?? 0);
  if (result.month != month || result.day != day) return null;
  return result;
}

// ── timedelta ──────────────────────────────────────────────────────────────

/// Seconds per unit (Python `DEFAULT_CONVERTER`).
const Map<String, num> defaultConverter = {
  's': 1,
  'm': 60,
  'h': 3600,
  'd': 86400,
  'w': 604800,
  'M': 2592000,
  'Y': 31536000,
};

const _separators = ['Y', 'M', 'w', 'd', 'h', 'm', 's'];

/// Text of a timedelta (Python `timedelta.format`), e.g. `1d 02:00`.
String formatTimedelta(Duration? value, [Map<String, num>? converter]) {
  if (value == null) return '';
  final conv = converter ?? defaultConverter;
  final text = <String>[];
  var seconds = value.inMicroseconds / 1e6;
  final sign = seconds < 0 ? '-' : '';
  seconds = seconds.abs();
  final values = <int>[];
  for (final k in _separators) {
    final v = conv[k];
    if (v != null && v != 0) {
      final part = (seconds ~/ v).toInt();
      seconds -= part * v;
      values.add(part);
    } else {
      values.add(0);
    }
  }
  for (var i = 0; i < _separators.length - 3; i++) {
    if (values[i] != 0) text.add('${values[i]}${_separators[i]}');
  }
  final timeValues = values.sublist(values.length - 3);
  if (timeValues.any((v) => v != 0) || text.isEmpty) {
    var time = '${_pad(timeValues[0])}:${_pad(timeValues[1])}';
    if (timeValues[2] != 0 || seconds != 0) time += ':${_pad(timeValues[2])}';
    text.add(time);
  }
  var result = sign + text.join(' ');
  if (seconds != 0) {
    if (!timeValues.any((v) => v != 0)) result += ' ';
    result += seconds.toStringAsFixed(6).substring(1);
  }
  return result;
}

/// Duration of a text (Python `timedelta.parse`); null for empty text.
Duration? parseTimedelta(String? text, [Map<String, num>? converter]) {
  if (text == null || text.isEmpty) return null;
  final conv = converter ?? defaultConverter;
  var t = text;
  for (final sep in _separators) {
    t = t.replaceAll(sep, '$sep ');
  }
  double seconds = 0;
  double? atof(String v) => double.tryParse(v.replaceAll(',', '.'));
  for (final part in t.split(RegExp(r'\s+')).where((p) => p.isNotEmpty)) {
    if (part.contains(':')) {
      final units = ['h', 'm', 's'];
      final pieces = part.split(':');
      for (var i = 0; i < pieces.length && i < 3; i++) {
        final v = atof(pieces[i]);
        if (v != null) seconds += v.abs() * conv[units[i]]!;
      }
    } else {
      var matched = false;
      for (final sep in _separators) {
        if (part.endsWith(sep)) {
          final v = atof(part.substring(0, part.length - sep.length));
          if (v != null) seconds += v.abs() * conv[sep]!;
          matched = true;
          break;
        }
      }
      if (!matched) {
        final v = atof(part);
        if (v != null) seconds += v.abs();
      }
    }
  }
  if (t.contains('-')) seconds = -seconds;
  return Duration(microseconds: (seconds * 1e6).round());
}

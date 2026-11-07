import 'package:intl/intl.dart';

import '../../core/domain/date_text.dart';

/// Display format for `datetime` fields (SAO default `%Y-%m-%d %H:%M:%S`).
final _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

/// Formats a `datetime` value in the device's local time zone.
/// `TrytonSerializer` already decodes server values (UTC) to local time;
/// `toLocal()` is a no-op then, but guards against UTC values from elsewhere.
String formatDateTimeValue(DateTime value) =>
    _dateTimeFormat.format(value.toLocal());

/// Default time format of `time`/`datetime` fields (spec 15.2).
const defaultTimeFormat = '%H:%M:%S';

/// An `intl` pattern of a strftime [format] (spec 15.2: `%d.%m.%Y` →
/// `dd.MM.yyyy`); literal text is quoted.
String intlPattern(String format) {
  final f = expandFormat(format);
  final out = StringBuffer();
  final literal = StringBuffer();
  void flush() {
    if (literal.isEmpty) return;
    final text = literal.toString();
    out.write(RegExp(r'^[^A-Za-z]*$').hasMatch(text) && !text.contains("'")
        ? text
        : "'${text.replaceAll("'", "''")}'");
    literal.clear();
  }

  for (var i = 0; i < f.length; i++) {
    final c = f[i];
    if (c != '%' || i + 1 >= f.length) {
      literal.write(c);
      continue;
    }
    final d = f[++i];
    final pattern = switch (d) {
      'd' => 'dd',
      'm' => 'MM',
      'Y' => 'yyyy',
      'y' => 'yy',
      'H' => 'HH',
      'I' => 'hh',
      'M' => 'mm',
      'S' => 'ss',
      'f' => 'SSSSSS',
      'p' => 'a',
      'b' => 'MMM',
      'B' => 'MMMM',
      'a' => 'EEE',
      'A' => 'EEEE',
      'j' => 'DDD',
      _ => null,
    };
    if (pattern == null) {
      literal.write(d == '%' ? '%' : '%$d');
      continue;
    }
    flush();
    out.write(pattern);
  }
  flush();
  return out.toString();
}

/// [value] in the strftime [format] with the month/day names of
/// [localeTag] (intl); without a locale like Python `strftime`.
String formatDate(DateTime value, String format, [String? localeTag]) {
  if (localeTag == null) return strftime(value, format);
  try {
    return DateFormat(intlPattern(format), localeTag).format(value);
  } catch (_) {
    return strftime(value, format);
  }
}

/// Keyboard operators of date/time fields (spec 15.3, Python
/// `datetime_.OPERATORS`): lower case adds, upper case subtracts one
/// second (`s`), minute (`i`), hour (`h`), day (`d`), week (`w`), month
/// (`m`) or year (`y`); `=` gives now. Null for other characters.
DateTime? applyDateOperator(DateTime? value, String character,
    {DateTime Function() now = DateTime.now}) {
  if (character == '=') return now();
  if (character.length != 1) return null;
  final lower = character.toLowerCase();
  if (!'sihdwmy'.contains(lower)) return null;
  if (value == null) return null;
  final n = character == lower ? 1 : -1;
  return switch (lower) {
    's' => value.add(Duration(seconds: n)),
    'i' => value.add(Duration(minutes: n)),
    'h' => value.add(Duration(hours: n)),
    'd' => _shift(value, days: n),
    'w' => _shift(value, days: 7 * n),
    'm' => _shift(value, months: n),
    _ => _shift(value, years: n),
  };
}

/// Calendar shift keeping the wall time (`relativedelta`: the day is
/// clipped to the month's last day).
DateTime _shift(DateTime value, {int days = 0, int months = 0, int years = 0}) {
  final total = (value.year + years) * 12 + value.month - 1 + months;
  final year = total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = value.day > lastDay ? lastDay : value.day;
  return DateTime(year, month, day + days, value.hour, value.minute,
      value.second, value.millisecond, value.microsecond);
}

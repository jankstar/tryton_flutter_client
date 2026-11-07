import 'package:intl/intl.dart';

import '../../core/serialization/tryton_serializer.dart';

/// Number format of the user's language (`preferences.locale`, spec 15.1/
/// 15.4): decimal point, thousands separator and grouping like Python's
/// `locale` module (`grouping` `[3, 3, 0]`: the last size repeats after a
/// 0, `-1`/`127` stops grouping). It has priority over the device locale.
class NumberLocale {
  final String decimalPoint;
  final String thousandsSep;
  final List<int> grouping;

  const NumberLocale(
      {this.decimalPoint = '.',
      this.thousandsSep = '',
      this.grouping = const [3, 0]});

  /// From `preferences.locale` (`decimal_point`, `thousands_sep`,
  /// `grouping`); null without one.
  static NumberLocale? fromPreferences(dynamic locale) {
    if (locale is! Map) return null;
    final point = locale['decimal_point'];
    if (point is! String || point.isEmpty) return null;
    final sep = locale['thousands_sep'];
    final grouping = locale['grouping'];
    return NumberLocale(
      decimalPoint: point,
      thousandsSep: sep is String ? sep : '',
      grouping: grouping is List
          ? [for (final g in grouping) if (g is num) g.toInt()]
          : const [3, 0],
    );
  }

  /// The device/app locale (fallback without preferences).
  factory NumberLocale.intl(String localeTag) {
    try {
      final symbols = NumberFormat.decimalPattern(localeTag).symbols;
      return NumberLocale(
          decimalPoint: symbols.DECIMAL_SEP, thousandsSep: symbols.GROUP_SEP);
    } catch (_) {
      return const NumberLocale(thousandsSep: ',');
    }
  }

  /// Integer digits with the thousands separator (Python `locale._group`).
  String group(String digits) {
    if (thousandsSep.isEmpty || grouping.isEmpty) return digits;
    final parts = <String>[];
    var rest = digits;
    int? last;
    var i = 0;
    while (rest.isNotEmpty) {
      int size;
      if (i < grouping.length) {
        final g = grouping[i];
        if (g == 0) {
          if (last == null) break;
          size = last;
        } else if (g < 0 || g >= 127) {
          break;
        } else {
          size = g;
          i++;
        }
      } else {
        // after the list without 0: no further grouping
        break;
      }
      last = size;
      if (rest.length <= size) break;
      parts.insert(0, rest.substring(rest.length - size));
      rest = rest.substring(0, rest.length - size);
    }
    parts.insert(0, rest);
    return parts.join(thousandsSep);
  }

  /// `locale.localize`: a plain number text (`-1234.56`) with decimal
  /// point and (with [grouping]) thousands separators.
  String localize(String plain, {bool grouping = true}) {
    final negative = plain.startsWith('-');
    final body = negative ? plain.substring(1) : plain;
    final dot = body.indexOf('.');
    var integer = dot < 0 ? body : body.substring(0, dot);
    if (grouping) integer = group(integer);
    final text =
        dot < 0 ? integer : '$integer$decimalPoint${body.substring(dot + 1)}';
    return negative ? '-$text' : text;
  }

  /// `locale.delocalize`: user input → plain number text or null when it
  /// is no number (thousands separators are dropped).
  String? delocalize(String text) {
    var v = text.trim().replaceAll(' ', '').replaceAll(' ', '');
    if (v.isEmpty) return null;
    if (thousandsSep.isNotEmpty) v = v.replaceAll(thousandsSep, '');
    if (decimalPoint != '.') {
      // a '.' that is no thousands separator is invalid here
      if (v.contains('.')) return null;
      v = v.replaceAll(decimalPoint, '.');
    }
    if (!RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)$').hasMatch(v)) return null;
    return v.startsWith('+') ? v.substring(1) : v;
  }
}

/// Plain decimal text of [value] with [decimals] places, or the shortest
/// one without (Python `'{0:.{p}f}'` with `p` from the value's exponent).
String plainNumber(dynamic value, int? decimals) {
  if (value is TrytonDecimal) {
    final text = value.value;
    if (decimals == null) {
      return text.contains('e') || text.contains('E')
          ? _shortest(double.parse(text))
          : text;
    }
    return _fixed(text, decimals);
  }
  final d = (value as num).toDouble();
  if (value is int) {
    return decimals == null || decimals <= 0
        ? '$value'
        : d.toStringAsFixed(decimals);
  }
  if (decimals == null) return _shortest(d);
  return d.toStringAsFixed(decimals);
}

String _shortest(double d) {
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  var s = d.toString();
  if (s.contains('e')) {
    final exp = int.parse(s.substring(s.indexOf('e') + 1));
    s = d.toStringAsFixed(exp < 0 ? (-exp + 15).clamp(0, 20) : 0);
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return s;
}

/// [text] (a decimal string) rounded half-up to [decimals] places without
/// binary floating point.
String _fixed(String text, int decimals) {
  var negative = text.startsWith('-');
  var t = negative || text.startsWith('+') ? text.substring(1) : text;
  if (t.contains('e') || t.contains('E')) {
    t = double.parse(t).toStringAsFixed(decimals);
    return negative ? '-$t' : t;
  }
  final dot = t.indexOf('.');
  var integer = dot < 0 ? t : t.substring(0, dot);
  var fraction = dot < 0 ? '' : t.substring(dot + 1);
  if (integer.isEmpty) integer = '0';
  if (fraction.length <= decimals) {
    fraction = fraction.padRight(decimals, '0');
  } else {
    final roundUp = fraction.codeUnitAt(decimals) >= 0x35; // '5'
    var digits = (integer + fraction.substring(0, decimals)).split('');
    if (roundUp) {
      var i = digits.length - 1;
      while (i >= 0) {
        if (digits[i] == '9') {
          digits[i] = '0';
          i--;
        } else {
          digits[i] = String.fromCharCode(digits[i].codeUnitAt(0) + 1);
          break;
        }
      }
      if (i < 0) digits.insert(0, '1');
    }
    final all = digits.join();
    integer = all.substring(0, all.length - decimals);
    fraction = all.substring(all.length - decimals);
  }
  final result = decimals > 0 ? '$integer.$fraction' : integer;
  final isZero = !result.contains(RegExp('[1-9]'));
  return negative && !isZero ? '-$result' : result;
}

/// Formats a numeric value like the Python client's `get_client(record,
/// factor, grouping)`: value × [factor], [digits] decimals (else the
/// value's own precision), localized with [numberLocale] (the
/// preferences) or the device [locale].
///
/// [value]       – the raw value (num, TrytonDecimal, String, or null)
/// [digits]      – field digits [intDigits, decimalDigits], e.g. [16, 2]
/// [locale]      – BCP-47 language tag, e.g. 'de' or 'en' (fallback)
/// [isInteger]   – true for integer fields (no decimal places, digits only)
String formatNumericValue(
  dynamic value, {
  List<int?>? digits,
  required String locale,
  bool isInteger = false,
  NumberLocale? numberLocale,
  num factor = 1,
  bool grouping = true,
}) {
  if (value == null || value == false) return '';
  // Never render raw objects — they would show as "{...}" or "[...]" in the UI.
  if (value is List || value is Map) return '';
  final format = numberLocale ?? NumberLocale.intl(locale);

  dynamic number;
  if (value is num || value is TrytonDecimal) {
    number = value;
  } else {
    final text = value.toString();
    number = isInteger ? int.tryParse(text) : num.tryParse(text);
    if (number == null) return '';
  }
  if (isInteger && number is num) number = number.toInt();
  if (factor != 1) {
    number = number is TrytonDecimal
        ? TrytonDecimal(_shortest(number.toDouble() * factor))
        : (number as num) * factor;
    if (isInteger) number = (number as num).round();
  }
  final decimals = isInteger
      ? 0
      : (digits != null && digits.length > 1 ? digits[1] : null);
  return format.localize(plainNumber(number, decimals), grouping: grouping);
}

/// Parses a locale-formatted number string back to a num (null when empty
/// or no number).
dynamic parseNumericValue(String text, String locale,
    {NumberLocale? numberLocale}) {
  if (text.trim().isEmpty) return null;
  final plain = (numberLocale ?? NumberLocale.intl(locale)).delocalize(text);
  if (plain == null) return null;
  return num.tryParse(plain);
}

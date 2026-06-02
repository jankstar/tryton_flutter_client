import 'package:intl/intl.dart';

/// Formats a numeric value according to the given locale, mirroring SAO's
/// `field.get_client(record, factor, grouping)` → `toLocaleString(lang, opts)`.
///
/// [value]       – the raw value (num, String, or null)
/// [digits]      – field digits [intDigits, decimalDigits], e.g. [16, 2]
/// [locale]      – BCP-47 language tag, e.g. 'de' or 'en'
/// [isInteger]   – true for integer fields (no decimal places, digits only)
String formatNumericValue(
  dynamic value, {
  List<int>? digits,
  required String locale,
  bool isInteger = false,
}) {
  if (value == null || value == false) return '';

  if (isInteger) {
    int? i;
    if (value is int) {
      i = value;
    } else if (value is num) {
      i = value.toInt();
    } else {
      i = int.tryParse(value.toString());
    }
    if (i == null) return value.toString();
    try {
      return NumberFormat.decimalPattern(locale).format(i);
    } catch (_) {
      return i.toString();
    }
  }

  double? d;
  if (value is num) {
    d = value.toDouble();
  } else {
    d = double.tryParse(value.toString());
  }
  if (d == null) return value.toString();

  final decimalPlaces =
      (digits != null && digits.length > 1 && digits[1] >= 0) ? digits[1] : 2;

  try {
    return NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: decimalPlaces,
    ).format(d);
  } catch (_) {
    return d.toStringAsFixed(decimalPlaces);
  }
}

/// Parses a locale-formatted number string back to a num.
dynamic parseNumericValue(String text, String locale) {
  if (text.isEmpty) return null;
  try {
    return NumberFormat.decimalPattern(locale).parse(text);
  } catch (_) {
    return double.tryParse(text.replaceAll(',', '.'));
  }
}

import 'dart:convert';

import '../serialization/tryton_serializer.dart';

/// Encodes Dart values as PYSON JSON (SAO `Sao.PYSON.Encoder`), e.g. for
/// saved searches/bookmarks (spec 03-pyson-domains.md 6).
///
/// - [TrytonDate] → `Date` (no deltas, `start` null)
/// - [DateTime] → `DateTime` with its UTC fields (`ms` in microseconds)
/// - [Duration] → `TimeDelta` (days, seconds, microseconds)
/// - [TrytonDecimal] → number
///
/// PYSON expressions are plain maps with `__class__`; their parameters are
/// encoded recursively.
class PYSONEncoder {
  const PYSONEncoder();

  String encode(dynamic value) => jsonEncode(prepare(value));

  /// Converts [value] into a JSON-encodable structure.
  static dynamic prepare(dynamic value) {
    if (value is List) return value.map(prepare).toList();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), prepare(v)));
    }
    if (value is TrytonDate) {
      return _date('Date', value.year, value.month, value.day);
    }
    if (value is DateTime) {
      final u = value.toUtc();
      return {
        ..._date('DateTime', u.year, u.month, u.day),
        'h': u.hour,
        'm': u.minute,
        's': u.second,
        'ms': u.millisecond * 1000 + u.microsecond,
        'dh': 0,
        'dm': 0,
        'ds': 0,
        'dms': 0,
      };
    }
    if (value is Duration) {
      // Normalised like Python's timedelta: 0 <= seconds < 86400,
      // 0 <= microseconds < 1000000.
      const perDay = Duration.microsecondsPerDay;
      const perSecond = Duration.microsecondsPerSecond;
      final total = value.inMicroseconds;
      final days = (total / perDay).floor();
      final rest = total - days * perDay;
      return {
        '__class__': 'TimeDelta',
        'd': days,
        's': rest ~/ perSecond,
        'm': rest % perSecond,
      };
    }
    if (value is TrytonDecimal) return num.parse(value.value);
    return value;
  }

  static Map<String, dynamic> _date(String cls, int y, int m, int d) => {
        '__class__': cls,
        'y': y,
        'M': m,
        'd': d,
        'dy': 0,
        'dM': 0,
        'dd': 0,
        'start': null,
      };
}

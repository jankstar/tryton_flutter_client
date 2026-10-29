import 'dart:convert';

/// Converts between Dart types and the Tryton JSON protocol.
///
/// Tryton encodes special types with a `__class__` marker:
/// DateTime, Date, Time, TimeDelta, Decimal, Bytes
///
/// `datetime` is UTC on the wire and local time in Dart; `date` and `time`
/// carry no time zone (spec 01-rpc-session.md 2.4).
class TrytonSerializer {
  // ─── Decode (JSON → Dart) ─────────────────────────────────────────────────

  static dynamic decode(dynamic value) {
    if (value is Map<String, dynamic>) {
      final cls = value['__class__'] as String?;
      if (cls != null) return _decodeTyped(cls, value);
      return value.map((k, v) => MapEntry(k, decode(v)));
    }
    if (value is List) return value.map(decode).toList();
    return value;
  }

  static dynamic _decodeTyped(String cls, Map<String, dynamic> v) {
    switch (cls) {
      case 'datetime':
        // Server datetimes are naive UTC (like SAO: moment.utc → local).
        final micro = v['microsecond'] as int? ?? 0;
        return DateTime.utc(
          v['year'] as int,
          v['month'] as int,
          v['day'] as int,
          v['hour'] as int? ?? 0,
          v['minute'] as int? ?? 0,
          v['second'] as int? ?? 0,
          micro ~/ 1000,
          micro % 1000,
        ).toLocal();
      case 'date':
        return TrytonDate(
          v['year'] as int,
          v['month'] as int,
          v['day'] as int,
        );
      case 'time':
        return TrytonTime(
          v['hour'] as int? ?? 0,
          v['minute'] as int? ?? 0,
          v['second'] as int? ?? 0,
          v['microsecond'] as int? ?? 0,
        );
      case 'timedelta':
        // Python's timedelta.total_seconds() – a float (3600.0, 0.5, -90.0).
        final seconds = v['seconds'] as num? ?? 0;
        return Duration(microseconds: (seconds * 1e6).round());
      case 'Decimal':
        return TrytonDecimal(v['decimal'] as String);
      case 'bytes':
        // The server wraps base64 in lines (e.g. res.user avatar).
        return TrytonBytes(base64.decode(
            (v['base64'] as String).replaceAll(RegExp(r'\s'), '')));
      default:
        return v;
    }
  }

  // ─── Encode (Dart → JSON) ─────────────────────────────────────────────────

  static dynamic encode(dynamic value) {
    if (value is DateTime) {
      // Local → naive UTC for the server.
      final utc = value.toUtc();
      return {
        '__class__': 'datetime',
        'year': utc.year,
        'month': utc.month,
        'day': utc.day,
        'hour': utc.hour,
        'minute': utc.minute,
        'second': utc.second,
        'microsecond': utc.millisecond * 1000 + utc.microsecond,
      };
    }
    if (value is TrytonDate) {
      return {
        '__class__': 'date',
        'year': value.year,
        'month': value.month,
        'day': value.day,
      };
    }
    if (value is TrytonTime) {
      return {
        '__class__': 'time',
        'hour': value.hour,
        'minute': value.minute,
        'second': value.second,
        'microsecond': value.microsecond,
      };
    }
    if (value is Duration) {
      // Float seconds, so fractions of a second are not lost.
      return {'__class__': 'timedelta', 'seconds': value.inMicroseconds / 1e6};
    }
    if (value is TrytonDecimal) {
      return {'__class__': 'Decimal', 'decimal': value.value};
    }
    // Wrap TrytonBytes explicitly – do NOT automatically encode int lists as
    // bytes, otherwise ID lists would be erroneously base64-encoded.
    if (value is TrytonBytes) {
      // dart:convert emits base64 without line breaks.
      return {'__class__': 'bytes', 'base64': base64.encode(value.bytes)};
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), encode(v)));
    }
    if (value is List) {
      return value.map(encode).toList();
    }
    return value;
  }

  static List<dynamic> encodeList(List<dynamic> params) =>
      params.map(encode).toList();
}

/// Tryton date without time (Dart has no pure Date type)
class TrytonDate {
  final int year, month, day;
  const TrytonDate(this.year, this.month, this.day);

  DateTime toDateTime() => DateTime(year, month, day);

  static TrytonDate fromDateTime(DateTime dt) =>
      TrytonDate(dt.year, dt.month, dt.day);

  @override
  String toString() =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is TrytonDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

/// Tryton time without date
class TrytonTime {
  final int hour, minute, second, microsecond;
  const TrytonTime(this.hour, this.minute, this.second, this.microsecond);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is TrytonTime &&
      hour == other.hour &&
      minute == other.minute &&
      second == other.second &&
      microsecond == other.microsecond;

  @override
  int get hashCode => Object.hash(hour, minute, second, microsecond);
}

/// Binary data – explicit wrapper so that int lists are not accidentally
/// encoded as bytes (e.g. ID lists).
class TrytonBytes {
  final List<int> bytes;
  const TrytonBytes(this.bytes);
}

/// Decimal number as string (Tryton uses Python Decimal for precision)
class TrytonDecimal {
  final String value;
  const TrytonDecimal(this.value);

  double toDouble() => double.parse(value);

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is TrytonDecimal && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

import 'dart:convert';

/// Converts between Dart types and the Tryton JSON protocol.
///
/// Tryton encodes special types with a `__class__` marker:
/// DateTime, Date, Time, TimeDelta, Decimal, Bytes
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
        return DateTime(
          v['year'] as int,
          v['month'] as int,
          v['day'] as int,
          v['hour'] as int? ?? 0,
          v['minute'] as int? ?? 0,
          v['second'] as int? ?? 0,
          0,
          (v['microsecond'] as int? ?? 0) ~/ 1000,
        );
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
        return Duration(seconds: v['seconds'] as int? ?? 0);
      case 'Decimal':
        return TrytonDecimal(v['decimal'] as String);
      case 'bytes':
        return TrytonBytes(base64.decode(v['base64'] as String));
      default:
        return v;
    }
  }

  // ─── Encode (Dart → JSON) ─────────────────────────────────────────────────

  static dynamic encode(dynamic value) {
    if (value is DateTime) {
      return {
        '__class__': 'datetime',
        'year': value.year,
        'month': value.month,
        'day': value.day,
        'hour': value.hour,
        'minute': value.minute,
        'second': value.second,
        'microsecond': value.millisecond * 1000,
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
      return {'__class__': 'timedelta', 'seconds': value.inSeconds};
    }
    if (value is TrytonDecimal) {
      return {'__class__': 'Decimal', 'decimal': value.value};
    }
    // Wrap TrytonBytes explicitly – do NOT automatically encode int lists as
    // bytes, otherwise ID lists would be erroneously base64-encoded.
    if (value is TrytonBytes) {
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

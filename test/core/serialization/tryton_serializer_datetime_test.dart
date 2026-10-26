import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

Map<String, dynamic> wire(int y, int mo, int d,
        [int h = 0, int mi = 0, int s = 0, int us = 0]) =>
    {
      '__class__': 'datetime',
      'year': y,
      'month': mo,
      'day': d,
      'hour': h,
      'minute': mi,
      'second': s,
      'microsecond': us,
    };

/// True when the test process runs in Europe/Berlin (CET/CEST).
/// Run `TZ=Europe/Berlin flutter test` to exercise the zone-specific tests.
final bool _isBerlin = DateTime(2026, 1, 15).timeZoneOffset.inHours == 1 &&
    DateTime(2026, 7, 15).timeZoneOffset.inHours == 2;

void main() {
  group('datetime – zone independent', () {
    test('decode returns local time of the UTC instant', () {
      final dt = TrytonSerializer.decode(wire(2026, 7, 1, 12, 0, 0))
          as DateTime;
      expect(dt.isUtc, isFalse);
      expect(dt.toUtc(), DateTime.utc(2026, 7, 1, 12));
    });

    test('microseconds are kept completely (decode + encode)', () {
      final w = wire(2026, 1, 2, 3, 4, 5, 123456);
      final dt = TrytonSerializer.decode(w) as DateTime;
      expect(dt.millisecond, 123);
      expect(dt.microsecond, 456);
      expect(TrytonSerializer.encode(dt), w);
    }, testOn: '!browser');

    test('missing time parts default to 0', () {
      final dt = TrytonSerializer.decode(
          {'__class__': 'datetime', 'year': 2026, 'month': 3, 'day': 4})
          as DateTime;
      expect(dt.toUtc(), DateTime.utc(2026, 3, 4));
    });

    test('encode converts local time to UTC', () {
      final local = DateTime(2026, 7, 1, 14, 30);
      final u = local.toUtc();
      expect(TrytonSerializer.encode(local),
          wire(u.year, u.month, u.day, u.hour, u.minute));
    });

    test('encode of a UTC value is unchanged', () {
      expect(TrytonSerializer.encode(DateTime.utc(2026, 12, 31, 23, 59, 59)),
          wire(2026, 12, 31, 23, 59, 59));
    });

    for (final (label, w) in [
      ('winter', wire(2026, 1, 15, 8, 0, 0, 1)),
      ('summer', wire(2026, 7, 15, 8, 0, 0, 999999)),
      ('fall-back hour, 1st', wire(2026, 10, 25, 0, 30)),
      ('fall-back hour, 2nd', wire(2026, 10, 25, 1, 30)),
      ('spring-forward', wire(2026, 3, 29, 1, 30)),
      ('year boundary', wire(2026, 12, 31, 23, 30)),
    ]) {
      test('round trip server → client → server ($label)', () {
        expect(TrytonSerializer.encode(TrytonSerializer.decode(w)), w);
      });
    }

    test('nested in lists and maps (read/default_get results)', () {
      final decoded = TrytonSerializer.decode([
        {'id': 1, 'write_date': wire(2026, 7, 1, 12)}
      ]) as List;
      final value = (decoded.first as Map)['write_date'];
      expect(value, isA<DateTime>());
      expect((value as DateTime).toUtc(), DateTime.utc(2026, 7, 1, 12));
      expect(TrytonSerializer.encode({'write_date': value}),
          {'write_date': wire(2026, 7, 1, 12)});
    });
  });

  group('datetime – Europe/Berlin (summer/winter time)', () {
    test('winter: UTC+1', () {
      final dt = TrytonSerializer.decode(wire(2026, 1, 15, 8, 0)) as DateTime;
      expect([dt.year, dt.month, dt.day, dt.hour, dt.minute],
          [2026, 1, 15, 9, 0]);
    });

    test('summer: UTC+2', () {
      final dt = TrytonSerializer.decode(wire(2026, 7, 15, 8, 0)) as DateTime;
      expect([dt.hour, dt.minute], [10, 0]);
    });

    test('date changes across midnight', () {
      final dt =
          TrytonSerializer.decode(wire(2026, 12, 31, 23, 30)) as DateTime;
      expect([dt.year, dt.month, dt.day, dt.hour, dt.minute],
          [2027, 1, 1, 0, 30]);
    });

    test('fall-back: 00:30 and 01:30 UTC both show 02:30, stay distinct', () {
      final a = TrytonSerializer.decode(wire(2026, 10, 25, 0, 30)) as DateTime;
      final b = TrytonSerializer.decode(wire(2026, 10, 25, 1, 30)) as DateTime;
      expect([a.hour, a.minute], [2, 30]);
      expect([b.hour, b.minute], [2, 30]);
      expect(b.difference(a), const Duration(hours: 1));
      expect(TrytonSerializer.encode(a), wire(2026, 10, 25, 0, 30));
      expect(TrytonSerializer.encode(b), wire(2026, 10, 25, 1, 30));
    });

    test('user input: local 14:30 in summer → 12:30 UTC, winter → 13:30', () {
      expect(TrytonSerializer.encode(DateTime(2026, 7, 1, 14, 30)),
          wire(2026, 7, 1, 12, 30));
      expect(TrytonSerializer.encode(DateTime(2026, 1, 1, 14, 30)),
          wire(2026, 1, 1, 13, 30));
    });

    test('user input on spring-forward day: 03:30 CEST → 01:30 UTC', () {
      expect(TrytonSerializer.encode(DateTime(2026, 3, 29, 3, 30)),
          wire(2026, 3, 29, 1, 30));
    });
  }, skip: _isBerlin ? false : 'run with TZ=Europe/Berlin');

  group('date and time have no time zone', () {
    test('date round trip', () {
      final w = {'__class__': 'date', 'year': 2026, 'month': 3, 'day': 29};
      final d = TrytonSerializer.decode(w);
      expect(d, const TrytonDate(2026, 3, 29));
      expect(TrytonSerializer.encode(d), w);
    });

    test('time round trip keeps microseconds', () {
      final w = {
        '__class__': 'time',
        'hour': 23,
        'minute': 30,
        'second': 1,
        'microsecond': 123456
      };
      final t = TrytonSerializer.decode(w) as TrytonTime;
      expect([t.hour, t.minute, t.second, t.microsecond], [23, 30, 1, 123456]);
      expect(TrytonSerializer.encode(t), w);
    });

    test('date picked late in the evening stays the same day', () {
      final d = TrytonDate.fromDateTime(DateTime(2026, 12, 31, 23, 59));
      expect(TrytonSerializer.encode(d),
          {'__class__': 'date', 'year': 2026, 'month': 12, 'day': 31});
    });
  });
}

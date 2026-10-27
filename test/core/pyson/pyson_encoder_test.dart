import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/pyson/pyson_encoder.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

import 'pyson_test_helpers.dart';

/// SAO tests/sao.js 'PYSON Encoder'.
void main() {
  const encoder = PYSONEncoder();
  final pysonDate = date(y: 2002, M: 1, d: 1);
  final pysonDateTime =
      dateTime(y: 2002, M: 1, d: 1, h: 12, m: 30, s: 0, ms: 0);
  const d = TrytonDate(2002, 1, 1);

  test('null', () {
    expect(encoder.encode(null), 'null');
  });

  test('decimal → number', () {
    expect(encoder.encode(const TrytonDecimal('1.1')), jsonEncode(1.1));
  });

  test('date', () {
    expect(encoder.encode(d), jsonEncode(pysonDate));
  });

  test('datetime (UTC fields)', () {
    expect(encoder.encode(DateTime.utc(2002, 1, 1, 12, 30)),
        jsonEncode(pysonDateTime));
    // A local DateTime is encoded by its UTC fields.
    expect(encoder.encode(DateTime.utc(2002, 1, 1, 12, 30).toLocal()),
        jsonEncode(pysonDateTime));
    expect(
        jsonDecode(encoder.encode(DateTime.utc(2002, 1, 1, 0, 0, 0, 1, 2)))
            ['ms'],
        1002);
  });

  test('timedelta (days, seconds, microseconds)', () {
    expect(
        encoder.encode(const Duration(days: 1, seconds: 2, milliseconds: 3)),
        jsonEncode(timeDelta(1, 2, 3000)));
    // Normalised like Python: -1 s = -1 day + 86399 s.
    expect(encoder.encode(const Duration(seconds: -1)),
        jsonEncode(timeDelta(-1, 86399, 0)));
  });

  test('array', () {
    expect(encoder.encode(['create_date', '>=', d]),
        jsonEncode(['create_date', '>=', pysonDate]));
  });

  test('statement', () {
    expect(encoder.encode(equal(d, d)),
        jsonEncode({'__class__': 'Equal', 's1': pysonDate, 's2': pysonDate}));
  });

  test('encode → decode round trip keeps the values', () {
    final value = DateTime.utc(2002, 1, 1, 12, 30, 5, 7, 9);
    expect(decode(eval_('x', value)), value);
    expect(decode(eval_('x', d)), d);
    const td = Duration(days: 2, seconds: 3, microseconds: 4);
    expect(decode(eval_('x', td)), td);
  });
}

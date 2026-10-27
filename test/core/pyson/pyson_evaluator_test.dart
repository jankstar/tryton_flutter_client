import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/pyson/pyson_evaluator.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

import 'pyson_test_helpers.dart';

/// Cases from SAO's tests/sao.js (PYSON sections), translated to Dart.
/// Where SAO and the Python client (tryton/pyson.py) disagree, the Python
/// client wins (marked "Python:").
void main() {
  test('Decoder: null', () {
    expect(decode(null), isNull);
  });

  test('Eval', () {
    final e = eval_('test', 0);
    expect(decode(e, {'test': 1}), 1);
    expect(decode(e), 0);
    // A missing key gives the default, a present null stays null.
    expect(decode(e, {'test': null}), isNull);
  });

  test('Eval dot notation', () {
    final e = eval_('foo.bar', 0);
    expect(decode(e, {'foo': {'bar': 1}}), 1);
    expect(decode(e, {'foo': {'foo': 1}}), 0);
    expect(decode(e, {'bar': {'bar': 1}}), 0);
    expect(decode(e, {'foo': null}), 0);
    expect(decode(e, {'foo': 5}), 0);
  });

  test('Eval dot notation nested', () {
    final e = eval_('foo.bar.test', 0);
    expect(decode(e, {'foo': {'bar': {'test': 1}}}), 1);
    expect(decode(e, {'foo': {'foo': 1}}), 0);
    expect(decode(e, {'bar': {'bar': 1}}), 0);
  });

  test('Eval dot notation in context: the exact key wins', () {
    expect(
        decode(eval_('foo.bar', 0), {
          'foo.bar': 1,
          'foo': {'bar': 0},
        }),
        1);
  });

  test('Eval default is evaluated (may be PYSON)', () {
    final e = equal(eval_('foo', eval_('bar', 1)), 1);
    expect(decode(e), isTrue);
    expect(decode(e, {'foo': 2}), isFalse);
    expect(decode(e, {'bar': 2}), isFalse);
    expect(decode(e, {'foo': 1, 'bar': 2}), isTrue);
  });

  test('Not', () {
    expect(decode(not(true)), isFalse);
    expect(decode(not(false)), isTrue);
    expect(decode(not({})), isTrue);
    expect(decode(not({'a': 1})), isFalse);
    expect(decode(not([])), isTrue);
    expect(decode(not(['a'])), isFalse);
  });

  test('Bool', () {
    expect(decode(bool_(true)), isTrue);
    expect(decode(bool_(false)), isFalse);
    expect(decode(bool_('test')), isTrue);
    expect(decode(bool_('')), isFalse);
    expect(decode(bool_(1)), isTrue);
    expect(decode(bool_(0)), isFalse);
    expect(decode(bool_(['test'])), isTrue);
    expect(decode(bool_([])), isFalse);
    expect(decode(bool_({'foo': 'bar'})), isTrue);
    expect(decode(bool_({})), isFalse);

    final e = bool_(eval_('value'));
    // Python: bool(time(0, 0)) is True (SAO: false).
    expect(decode(e, {'value': const TrytonTime(0, 0, 0, 0)}), isTrue);
    expect(decode(e, {'value': const TrytonTime(0, 0, 0, 1000)}), isTrue);
    expect(decode(e, {'value': Duration.zero}), isFalse);
    expect(decode(e, {'value': const Duration(days: 1)}), isTrue);
    expect(decode(e, {'value': const TrytonDecimal('0')}), isFalse);
    expect(decode(e, {'value': const TrytonDecimal('1')}), isTrue);
  });

  test('And', () {
    expect(decode(and([true, true])), isTrue);
    expect(decode(and([true, true, true])), isTrue);
    expect(decode(and([true, false])), isFalse);
    expect(decode(and([false, true])), isFalse);
    expect(decode(and([false, false])), isFalse);
    expect(decode(and([false, false, false])), isFalse);
    expect(decode(and([true, false, false])), isFalse);
    expect(decode(and([false, true, false])), isFalse);
    expect(decode(and([false, false, true])), isFalse);
  });

  test('Or', () {
    expect(decode(or([true, true])), isTrue);
    expect(decode(or([true, true, true])), isTrue);
    expect(decode(or([true, false])), isTrue);
    expect(decode(or([false, true])), isTrue);
    expect(decode(or([false, false])), isFalse);
    expect(decode(or([false, false, false])), isFalse);
    expect(decode(or([true, false, false])), isTrue);
    expect(decode(or([false, true, false])), isTrue);
    expect(decode(or([false, false, true])), isTrue);
  });

  test('Equal', () {
    expect(decode(equal('test', 'test')), isTrue);
    expect(decode(equal('foo', 'bar')), isFalse);
    expect(decode(equal(['test'], ['test'])), isTrue);
    expect(decode(equal(['foo'], ['bar'])), isFalse);
    expect(decode(equal(date(y: 2017, M: 1, d: 1), date(y: 2017, M: 1, d: 1))),
        isTrue);
    expect(decode(equal(date(y: 2017, M: 1, d: 1), date(y: 2017, M: 1, d: 2))),
        isFalse);
    expect(
        decode(equal(
            dateTime(y: 2017, M: 1, d: 1, h: 12, m: 0, s: 0, ms: 0),
            dateTime(y: 2017, M: 1, d: 1, h: 12, m: 0, s: 0, ms: 0))),
        isTrue);
    expect(
        decode(equal(
            dateTime(y: 2017, M: 1, d: 1, h: 12, m: 0, s: 0, ms: 0),
            dateTime(y: 2017, M: 1, d: 1, h: 14, m: 0, s: 0, ms: 0))),
        isFalse);
    // A DateTime at midnight is not the Date of that day.
    expect(
        decode(equal(dateTime(y: 2017, M: 1, d: 1, h: 0, m: 0, s: 0, ms: 0),
            date(y: 2017, M: 1, d: 1))),
        isFalse);
  });

  test('Equal: numbers and decimals compare numerically', () {
    expect(decode(equal(1, 1.0)), isTrue);
    expect(decode(equal(eval_('x'), 2), {'x': const TrytonDecimal('2.0')}),
        isTrue);
  });

  test('Greater', () {
    expect(decode(greater(1, 0)), isTrue);
    expect(decode(greater(0, 1)), isFalse);
    expect(decode(greater(1, 0, true)), isTrue);
    expect(decode(greater(0, 1, true)), isFalse);
    expect(decode(greater(1, 1)), isFalse);
    expect(decode(greater(1, 1, true)), isTrue);
    expect(decode(greater(null, 1)), isFalse);
    expect(decode(greater(1, null)), isFalse);

    final dt0 = dateTime(y: 2020, M: 1, d: 1, h: 0, m: 0, s: 0, ms: 0);
    expect(decode(greater(dt0, const TrytonDate(2020, 1, 2))), isFalse);
    expect(
        decode(greater(
            dateTime(y: 2020, M: 1, d: 1, h: 0, m: 0, s: 0, ms: 1000),
            const TrytonDate(2020, 1, 1))),
        isTrue);
    expect(decode(greater(dt0, const TrytonDate(2020, 1, 1), true)), isTrue);
    expect(decode(greater(dt0, dt0)), isFalse);
    expect(
        decode(greater(
            date(y: 2020, M: 1, d: 1), const TrytonDate(2020, 1, 1))),
        isFalse);
    expect(
        decode(greater(eval_('foo', const TrytonDate(2020, 1, 1)),
            const TrytonDate(2020, 1, 1))),
        isFalse);
    expect(
        decode(greater(eval_('foo', date(y: 2020, M: 1, d: 1)),
            date(y: 2020, M: 1, d: 1))),
        isFalse);
    final dt1 = dateTime(y: 2020, M: 1, d: 1, h: 0, m: 0, s: 0, ms: 1);
    expect(decode(greater(date(y: 2020, M: 1, d: 1), dt1)), isFalse);
    expect(decode(greater(dt1, date(y: 2020, M: 1, d: 1), true)), isTrue);
    expect(decode(greater(dt0, 90000)), isTrue);
    expect(decode(greater(timeDelta(5, 2), timeDelta(4, 2))), isTrue);
    expect(decode(greater(timeDelta(4, 2), timeDelta(5, 2))), isFalse);
    expect(
        decode(greater(
            timeDelta(5, 2), const Duration(days: 4, seconds: 2))),
        isTrue);
    expect(decode(greater(eval_('i', 0), 0), {'i': 1}), isTrue);
  });

  test('Less', () {
    expect(decode(less(1, 0)), isFalse);
    expect(decode(less(0, 1)), isTrue);
    expect(decode(less(1, 0, true)), isFalse);
    expect(decode(less(0, 1, true)), isTrue);
    expect(decode(less(1, 1)), isFalse);
    expect(decode(less(1, 1, true)), isTrue);
    expect(decode(less(null, 1)), isFalse);
    expect(decode(less(1, null)), isFalse);

    final dt0 = dateTime(y: 2020, M: 1, d: 1, h: 0, m: 0, s: 0, ms: 0);
    expect(
        decode(less(dateTime(y: 2020, M: 1, d: 1, h: 0, m: 0, s: 0, ms: 1000),
            const TrytonDate(2020, 1, 1))),
        isFalse);
    expect(decode(less(dt0, const TrytonDate(2020, 1, 2), true)), isTrue);
    expect(decode(less(dt0, dt0)), isFalse);
    expect(
        decode(less(date(y: 2020, M: 1, d: 1), const TrytonDate(2020, 1, 2))),
        isTrue);
    expect(
        decode(less(date(y: 2020, M: 1, d: 1),
            dateTime(y: 2020, M: 1, d: 1, h: 0, m: 0, s: 0, ms: 1000))),
        isTrue);
    expect(decode(less(dt0, date(y: 2020, M: 1, d: 1), true)), isTrue);
    expect(decode(less(dt0, 90000)), isFalse);
  });

  test('If', () {
    expect(decode(if_(true, 'foo', 'bar')), 'foo');
    expect(decode(if_(false, 'foo', 'bar')), 'bar');
  });

  test('Get', () {
    expect(decode(get({'foo': 'bar'}, 'foo', 'default')), 'bar');
    expect(decode(get({'foo': 'bar'}, 'test', 'default')), 'default');
    expect(decode(get({}, 'foo', 'default')), 'default');
  });

  test('In', () {
    expect(decode(in_('foo', {'foo': 'bar'})), isTrue);
    expect(decode(in_(eval_('test', 'foo'), {'foo': 'bar'})), isTrue);
    expect(decode(in_('1', {'1': 'bar'})), isTrue);
    expect(decode(in_('test', {'foo': 'bar'})), isFalse);
    expect(decode(in_(eval_('foo', 'test'), {'foo': 'bar'})), isFalse);
    expect(decode(in_('foo', ['foo'])), isTrue);
    expect(decode(in_(1, [1])), isTrue);
    expect(decode(in_('test', ['foo'])), isFalse);
    expect(decode(in_(1, [2])), isFalse);
    expect(decode(in_('test', [])), isFalse);
    expect(decode(in_('test', eval_('foo', [])), {'foo': null}), isFalse);
  });

  test('Date', () {
    expect(decode(date(y: 2010, M: 1, d: 12)), const TrytonDate(2010, 1, 12));
    expect(decode(date(y: 2010, M: 1, d: 12, dy: -1)),
        const TrytonDate(2009, 1, 12));
    expect(decode(date(y: 2010, M: 1, d: 12, dM: 12)),
        const TrytonDate(2011, 1, 12));
    expect(decode(date(y: 2010, M: 1, d: 12, dd: -7)),
        const TrytonDate(2010, 1, 5));
    expect(decode(date(y: 2010, M: 2, d: 22)), const TrytonDate(2010, 2, 22));
  });

  test('Date: relativedelta semantics (Python)', () {
    expect(decode(date(y: 2021, M: 1, d: 31, dM: 1)),
        const TrytonDate(2021, 2, 28));
    expect(decode(date(y: 2020, M: 3, d: 1, dd: -1)),
        const TrytonDate(2020, 2, 29));
    // An absolute day is clamped to the month's end (no overflow).
    expect(decode(date(y: 2021, M: 2, d: 31)), const TrytonDate(2021, 2, 28));
    // The day is clamped once, against the final month.
    expect(decode(date(M: 2, dM: 1, start: const TrytonDate(2021, 1, 31))),
        const TrytonDate(2021, 3, 31));
    expect(decode(date(dy: 1, start: const TrytonDate(2020, 2, 29))),
        const TrytonDate(2021, 2, 28));
    expect(decode(date(dM: -13, start: const TrytonDate(2021, 1, 15))),
        const TrytonDate(2019, 12, 15));
  });

  group('Date/DateTime without values use the current date', () {
    setUp(() => PYSONEvaluator.clock = () => DateTime(2024, 5, 17, 9, 30));
    tearDown(() => PYSONEvaluator.clock = DateTime.now);

    test('Date start', () {
      expect(decode(date(start: eval_('date')),
          {'date': const TrytonDate(2000, 2, 1)}),
          const TrytonDate(2000, 2, 1));
      expect(decode(date(start: eval_('datetime')),
          {'datetime': DateTime.utc(2000, 2, 1, 12, 0)}),
          const TrytonDate(2000, 2, 1));
      // Python: the date of a datetime is its UTC date.
      expect(decode(date(start: eval_('datetime')),
          {'datetime': DateTime.utc(2000, 2, 1, 23, 30).toLocal()}),
          const TrytonDate(2000, 2, 1));
      // A start that is no date → today.
      expect(decode(date(start: eval_('foo')), {'foo': 'bar'}),
          const TrytonDate(2024, 5, 17));
      expect(decode(date(dd: 1)), const TrytonDate(2024, 5, 18));
    });

    test('DateTime start', () {
      final datetime = DateTime(2000, 2, 1, 12, 0);
      final result =
          decode(dateTime(start: eval_('datetime')), {'datetime': datetime});
      expect((result as DateTime).isAtSameMomentAs(datetime), isTrue);
      expect(result.isUtc, isTrue);
      // Python: combine(date, time()) – midnight of the naive (UTC) values.
      expect(
          decode(dateTime(start: eval_('date')),
              {'date': const TrytonDate(2000, 2, 1)}),
          DateTime.utc(2000, 2, 1));
      // Python: absolute hours on a start datetime are UTC hours.
      expect(
          decode(dateTime(h: 8, start: eval_('datetime')),
              {'datetime': DateTime.utc(2000, 2, 1, 12, 0).toLocal()}),
          DateTime.utc(2000, 2, 1, 8, 0));
      final now = decode(dateTime(start: eval_('foo')), {'foo': 'bar'});
      expect(now, isA<DateTime>());
      expect((now as DateTime).isAtSameMomentAs(DateTime(2024, 5, 17, 9, 30)),
          isTrue);
    });
  });

  test('DateTime (values are UTC)', () {
    DateTime dt({int dy = 0, int dM = 0, int dd = 0, int dh = 0, int dm = 0,
            int ds = 0, int dms = 0}) =>
        decode(dateTime(
            y: 2010, M: 1, d: 12, h: 10, m: 30, s: 20, ms: 0, //
            dy: dy, dM: dM, dd: dd, dh: dh, dm: dm, ds: ds, dms: dms));

    expect(dt(), DateTime.utc(2010, 1, 12, 10, 30, 20));
    expect(dt(dy: -1), DateTime.utc(2009, 1, 12, 10, 30, 20));
    expect(dt(dM: 12), DateTime.utc(2011, 1, 12, 10, 30, 20));
    expect(dt(dd: -7), DateTime.utc(2010, 1, 5, 10, 30, 20));
    expect(dt(dh: 12), DateTime.utc(2010, 1, 12, 22, 30, 20));
    expect(dt(dm: -30), DateTime.utc(2010, 1, 12, 10, 0, 20));
    expect(dt(ds: 30), DateTime.utc(2010, 1, 12, 10, 30, 50));
    expect(dt(dms: 2000), DateTime.utc(2010, 1, 12, 10, 30, 20, 2));
    expect(
        decode(dateTime(y: 2010, M: 2, d: 22, h: 10, m: 30, s: 20, ms: 2000)),
        DateTime.utc(2010, 2, 22, 10, 30, 20, 2));
  });

  test('TimeDelta (m in microseconds)', () {
    expect(decode(timeDelta(1, 2, 3)),
        const Duration(days: 1, seconds: 2, microseconds: 3));
    // Python: floats are allowed (timedelta(days=1.5)).
    expect(decode({'__class__': 'TimeDelta', 'd': 1.5, 's': 0.5, 'm': 0}),
        const Duration(hours: 36, milliseconds: 500));
  });

  test('Len', () {
    expect(decode(len([1, 2, 3])), 3);
    expect(decode(len({'1': 2, '3': 4})), 2);
    expect(decode(len('foo bar')), 7);
  });

  test('Composite', () {
    final expr = [
      'id',
      if_(not(in_('company', eval_('context', {}))), '=', '!='),
      get(eval_('context', {}), 'company', -1),
    ];
    expect(
        decode(expr, {
          'context': {'company': 1}
        }),
        ['id', '!=', 1]);
    expect(decode(expr, {'context': {}}), ['id', '=', -1]);
  });

  test('PYSON inside plain dicts is evaluated', () {
    expect(decode({'company': eval_('company', -1)}, {'company': 3}),
        {'company': 3});
  });

  test('Unknown classes (also the removed Not_in) stay a dict', () {
    expect(decode({'__class__': 'Foo', 'v': eval_('x')}, {'x': 1}),
        {'__class__': 'Foo', 'v': 1});
    expect(decode({'__class__': 'Not_in', 'k': 1, 'v': [1]}),
        {'__class__': 'Not_in', 'k': 1, 'v': [1]});
  });

  test('Eval returns the environment value unchanged (no Many2One magic)',
      () {
    expect(decode(eval_('party'), {'party': [5, 'Name']}), [5, 'Name']);
  });
}

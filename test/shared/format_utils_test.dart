import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/shared/utils/date_format_utils.dart';
import 'package:tryton_flutter_client/shared/utils/number_format_utils.dart';

/// Number and date formats of the preferences (spec 15.2–15.4).
void main() {
  const de = NumberLocale(
      decimalPoint: ',', thousandsSep: '.', grouping: [3, 3, 0]);

  group('NumberLocale', () {
    test('from preferences.locale', () {
      final l = NumberLocale.fromPreferences({
        'decimal_point': ',',
        'thousands_sep': '.',
        'grouping': [3, 0]
      })!;
      expect((l.decimalPoint, l.thousandsSep), (',', '.'));
      expect(l.grouping, [3, 0]);
      expect(NumberLocale.fromPreferences(null), isNull);
    });

    test('grouping like Python locale', () {
      expect(de.group('1234567'), '1.234.567');
      expect(de.group('123'), '123');
      const indian = NumberLocale(thousandsSep: ',', grouping: [3, 2, 0]);
      expect(indian.group('123456789'), '12,34,56,789');
      const once = NumberLocale(thousandsSep: ',', grouping: [3]);
      expect(once.group('1234567'), '1234,567', reason: 'no 0: stops');
      const none = NumberLocale(thousandsSep: ',', grouping: [-1]);
      expect(none.group('1234567'), '1234567');
    });

    test('localize / delocalize', () {
      expect(de.localize('-1234567.5'), '-1.234.567,5');
      expect(de.localize('1234.5', grouping: false), '1234,5');
      expect(de.delocalize('1.234,56'), '1234.56');
      expect(de.delocalize(' -2,5 '), '-2.5');
      expect(de.delocalize('1,2,3'), isNull);
      expect(de.delocalize('1.5x'), isNull);
      expect(const NumberLocale().delocalize('+3.25'), '3.25');
    });
  });

  group('formatNumericValue (Python get_client)', () {
    String f(dynamic v, {List<int?>? digits, num factor = 1, bool int = false}) =>
        formatNumericValue(v,
            locale: 'en',
            numberLocale: de,
            digits: digits,
            factor: factor,
            isInteger: int);

    test('digits, own precision without digits', () {
      expect(f(1234.56, digits: [16, 2]), '1.234,56');
      expect(f(7.0), '7');
      expect(f(0.125), '0,125');
      expect(f(const TrytonDecimal('1234.5'), digits: [16, 3]), '1.234,500');
      expect(f(const TrytonDecimal('2.675'), digits: [16, 2]), '2,68',
          reason: 'decimal rounding without float error');
      expect(f(1234567, int: true), '1.234.567');
    });

    test('factor', () {
      expect(f(0.125, digits: [16, 2], factor: 100), '12,50');
      expect(f(3, int: true, factor: 2), '6');
    });
  });

  group('dates', () {
    test('strftime → intl pattern', () {
      expect(intlPattern('%d.%m.%Y'), 'dd.MM.yyyy');
      expect(intlPattern('%Y-%m-%d %H:%M:%S'), 'yyyy-MM-dd HH:mm:ss');
      expect(intlPattern('%d de %B'), "dd' de 'MMMM");
      expect(intlPattern('%x'), 'MM/dd/yy');
    });

    test('formatDate with and without locale', () {
      final d = DateTime(2026, 3, 1, 14, 5, 9);
      expect(formatDate(d, '%d.%m.%Y'), '01.03.2026');
      expect(formatDate(d, '%d.%m.%Y %H:%M', 'de'), '01.03.2026 14:05');
    });

    test('keyboard operators (15.3)', () {
      final d = DateTime(2026, 1, 31, 10, 30, 15);
      expect(applyDateOperator(d, 'd'), DateTime(2026, 2, 1, 10, 30, 15));
      expect(applyDateOperator(d, 'D'), DateTime(2026, 1, 30, 10, 30, 15));
      expect(applyDateOperator(d, 'w'), DateTime(2026, 2, 7, 10, 30, 15));
      expect(applyDateOperator(d, 'W'), DateTime(2026, 1, 24, 10, 30, 15));
      expect(applyDateOperator(d, 'm'), DateTime(2026, 2, 28, 10, 30, 15),
          reason: 'clipped to the last day');
      expect(applyDateOperator(d, 'M'), DateTime(2025, 12, 31, 10, 30, 15));
      expect(applyDateOperator(d, 'y'), DateTime(2027, 1, 31, 10, 30, 15));
      expect(applyDateOperator(d, 'Y'), DateTime(2025, 1, 31, 10, 30, 15));
      expect(applyDateOperator(d, 'h'), DateTime(2026, 1, 31, 11, 30, 15));
      expect(applyDateOperator(d, 'I'), DateTime(2026, 1, 31, 10, 29, 15));
      expect(applyDateOperator(d, 's'), DateTime(2026, 1, 31, 10, 30, 16));
      final now = DateTime(2030);
      expect(applyDateOperator(null, '=', now: () => now), now);
      expect(applyDateOperator(null, 'd'), isNull);
      expect(applyDateOperator(d, 'x'), isNull);
    });
  });
}

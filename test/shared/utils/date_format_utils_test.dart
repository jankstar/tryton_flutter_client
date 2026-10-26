import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/shared/utils/date_format_utils.dart';

void main() {
  test('formats local time without milliseconds', () {
    expect(formatDateTimeValue(DateTime(2026, 10, 26, 14, 5, 9, 123)),
        '2026-10-26 14:05:09');
  });

  test('UTC values are shown in local time', () {
    final utc = DateTime.utc(2026, 7, 1, 12);
    expect(formatDateTimeValue(utc), formatDateTimeValue(utc.toLocal()));
  });
}

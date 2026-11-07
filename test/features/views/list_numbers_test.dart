import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

import 'form_harness.dart';

/// Amount columns with `digits`/`symbol` of a currency field (party list:
/// receivable_today, payable_today, deposit): one `get_digits` and one
/// `get_symbol` per currency, not per cell.
void main() {
  testWidgets('54 rows × 3 amount columns: one get_digits, one get_symbol',
      (tester) async {
    const amount = {
      'type': 'numeric',
      'string': 'Amount',
      'digits': '"currency"',
      'symbol': 'currency',
    };
    final ids = [for (var i = 1; i <= 54; i++) i];
    final rpc = FakeFormRpc({
      'model.test.party.fields_view_get': (_) => {
            'type': 'tree',
            'view_id': 1,
            'arch': '<tree><field name="name"/><field name="r"/>'
                '<field name="p"/><field name="d"/></tree>',
            'fields': {
              'name': {'type': 'char', 'string': 'Name'},
              'r': amount,
              'p': amount,
              'd': amount,
              'currency': {
                'type': 'many2one',
                'string': 'Currency',
                'relation': 'test.currency'
              },
            },
          },
      'model.test.party.search': (_) => ids,
      'model.test.party.search_count': (_) => ids.length,
      'model.test.party.read': (p) => [
            for (final id in p[0] as List)
              {
                'id': id,
                'name': 'N$id',
                'r': const TrytonDecimal('1234.5'),
                'p': const TrytonDecimal('-2'),
                'd': const TrytonDecimal('0'),
                'currency': 1,
                'currency.': {'rec_name': 'EUR'},
                '_timestamp': '1',
              }
          ],
      // slow answers: all cells are built before the first one arrives
      'model.test.currency.get_digits': (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return [16, 2];
      },
      'model.test.currency.get_symbol': (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return ['€', 1];
      },
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
    });
    await pumpScreen(
        tester, rpc, const ScreenAttributes('test.party', mode: ['tree']),
        settle: false);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(rpc.named('model.test.party.read'), hasLength(1));
    expect(rpc.named('model.test.currency.get_digits'), hasLength(1));
    expect(rpc.named('model.test.currency.get_symbol'), hasLength(1));
    expect(find.text('1,234.50 €'), findsWidgets,
        reason: 'digits and symbol of the shared answer');
    expect(tester.takeException(), isNull);
  });
}

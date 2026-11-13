import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';

import 'form_harness.dart';

/// A reference column whose selection is a server method (invoice payment
/// means: `instrument` → `get_instruments`) shows the translated model
/// label before the record name (Python `_ReferenceSelection`), not the
/// technical model name.
void main() {
  testWidgets('reference column with a method selection: the model label',
      (tester) async {
    final rpc = FakeFormRpc({
      'model.test.mean.fields_view_get': (_) => {
            'type': 'tree',
            'view_id': 7,
            'arch': '<tree><field name="instrument"/></tree>',
            'fields': {
              'instrument': {
                'type': 'reference',
                'string': 'Instrument',
                'selection': 'get_instruments',
              },
            },
          },
      'model.test.mean.get_instruments': (_) => [
            ['', ''],
            ['bank.account', 'Bankkonto'],
          ],
      'model.test.mean.search': (_) => [1],
      'model.test.mean.search_count': (_) => 1,
      'model.test.mean.read': (p) => [
            for (final id in p[0] as List)
              {
                'id': id,
                '_timestamp': '1',
                'instrument': 'bank.account,5',
                'instrument.': {'id': 5, 'rec_name': 'DE89 3704'},
              }
          ],
      'model.test.mean.view_toolbar_get': (_) => <String, dynamic>{},
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
    });
    await pumpScreen(
        tester, rpc, const ScreenAttributes('test.mean', mode: ['tree']),
        settle: false);
    await pumpFrames(tester, 20);
    expect(find.text('DE89 3704'), findsOneWidget);
    expect(find.text('Bankkonto:'), findsOneWidget);
    expect(find.textContaining('bank.account'), findsNothing);
    expect(rpc.named('model.test.mean.get_instruments'), hasLength(1),
        reason: 'loaded once, shared with the search of the screen');
  });
}

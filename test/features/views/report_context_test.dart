import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';

import 'form_harness.dart';

/// Actions of the toolbar get the screen's context with the values of
/// the context form (Python `Form._action`: `screen.local_context`) –
/// e.g. the general ledger report needs the fiscal year.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  // „Open report“ and „Print report“ (direct_print, Python toolbar)
  for (final (tooltip, direct) in [
    ('Open report', false),
    ('Print report', true),
  ]) {
    testWidgets('$tooltip from a list with context form: fiscal year and '
        'context_model in the report context', (tester) async {
      final rpc = FakeFormRpc({
        'model.test.ledger.context.fields_view_get': (_) =>
            formView('<form><field name="fiscalyear"/></form>', {
              'fiscalyear': {'type': 'integer', 'string': 'Fiscal Year'},
            }),
        'model.test.ledger.context.default_get': (_) => {'fiscalyear': 2},
        'model.test.ledger.fields_view_get': (_) => {
          'type': 'tree',
          'view_id': 3,
          'arch': '<tree><field name="name"/></tree>',
          'fields': {
            'name': {'type': 'char', 'string': 'Name'},
          },
        },
        'model.test.ledger.search': (_) => [412, 425],
        'model.test.ledger.search_count': (_) => 2,
        'model.test.ledger.read': (p) => [
          for (final id in p[0] as List)
            {'id': id, 'name': 'Account $id', '_timestamp': '1'},
        ],
        'model.test.ledger.view_toolbar_get': (_) => {
          'print': [
            <String, dynamic>{
              'id': 107,
              'name': 'General Ledger',
              'type': 'ir.action.report',
              'report_name': 'test.general_ledger',
            },
          ],
        },
        'report.test.general_ledger.execute': (_) =>
            throw Exception('stop after the call'),
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });
      await pumpScreen(
        tester,
        rpc,
        const ScreenAttributes(
          'test.ledger',
          mode: ['tree'],
          contextModel: 'test.ledger.context',
        ),
        settle: false,
      );
      await pumpFrames(tester);
      // the search already ran with the fiscal year
      expect(
        rpc.named('model.test.ledger.search').last.context['fiscalyear'],
        2,
      );

      // a click selects after the double-click time
      await tester.tap(find.text('Account 412'));
      await pumpFrames(tester, 10);
      await tester.tap(find.byTooltip('$tooltip: General Ledger'));
      await pumpFrames(tester, 10);

      final call = rpc.named('report.test.general_ledger.execute').single;
      expect(call.context['fiscalyear'], 2);
      expect(call.context['context_model'], 'test.ledger.context');
      expect(call.context['direct_print'], direct);
      expect(call.params[0], [412]);
      expect((call.params[1] as Map)['model_context'], 'test.ledger.context');
    }, variant: desktop);
  }
}

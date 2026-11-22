import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/views/record_form.dart';

import 'form_harness.dart';

/// The `<button>`s of an x2many's inline form (a row selected, then
/// „Switch view“) run like in the popup of „Open“ (Python One2Many: the
/// child screen's form view). They were always disabled (no handler).
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  FakeFormRpc server() => FakeFormRpc({
        'model.test.form.fields_view_get': (_) => formView(
            '<form><field name="lines" colspan="4"/></form>', {
          'lines': {
            'type': 'one2many',
            'string': 'Rent adjustments',
            'relation': 'test.line',
            'relation_field': 'parent',
          },
        }),
        'model.test.form.read': (_) => [
              {'id': 1, 'lines': [11, 12], '_timestamp': '1'}
            ],
        'model.test.line.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'view_id': 40,
                'arch': '<tree><field name="name"/></tree>',
                'fields': {
                  'name': {'type': 'char', 'string': 'Name'}
                },
              }
            : {
                ...formView(
                    '<form><label name="name"/><field name="name"/>'
                    '<button name="apply" string="Apply"/></form>',
                    {
                      'name': {'type': 'char', 'string': 'Name'}
                    }),
                'view_id': 41,
              },
        'model.test.line.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'L$id', '_timestamp': '1'}
            ],
        'model.test.line.apply': (_) => null,
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.form.resources': (_) => <String, dynamic>{},
      });

  testWidgets('a row, Switch view, the form\'s button runs (like Open)',
      (tester) async {
    final rpc = server();
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    // select the second row (a click selects after the double-tap time)
    await tester.tap(find.text('L12'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('x2m-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Apply'), findsOneWidget, reason: 'the inline form');

    final button = find.ancestor(
        of: find.text('Apply'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));
    expect(tester.widget<ButtonStyleButton>(button.first).onPressed, isNotNull,
        reason: 'the button can be chosen');
    expect(find.byType(RecordButton), findsOneWidget);

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    final call = rpc.named('model.test.line.apply').single;
    expect(call.params[0], [12], reason: 'the record of the inline form');
  }, variant: desktop);
}

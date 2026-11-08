import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';

import 'form_harness.dart';

/// x2many `pre_validate` and `product` (spec 9.2.7, Python
/// `form_gtk/one2many.py` `_validate`, `_new_product`; `WinForm`).
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  FakeFormRpc server(String attrs,
          {Object? Function(List<dynamic>)? preValidate}) =>
      FakeFormRpc({
        'model.test.form.fields_view_get': (_) =>
            formView('<form><field name="lines" $attrs/></form>', {
              'lines': {
                'type': 'one2many',
                'string': 'Lines',
                'relation': 'test.line',
                'relation_field': 'form',
              },
            }),
        'model.test.form.read': (p) => [
              {'id': 1, '_timestamp': '1', 'lines': <int>[]}
            ],
        'model.test.form.write': (_) => null,
        'model.test.line.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'arch': '<tree><field name="name"/><field name="product"/></tree>',
                'fields': {
                  'name': {'type': 'char', 'string': 'Name'},
                  'product': {
                    'type': 'many2one',
                    'string': 'Product',
                    'relation': 'test.product',
                  },
                },
              }
            : formView('<form><field name="name"/></form>', {
                'name': {'type': 'char', 'string': 'Name'},
              }),
        'model.test.line.default_get': (_) => {'name': 'Default'},
        'model.test.line.pre_validate': preValidate ?? (_) => null,
        'model.test.line.view_toolbar_get': (_) => <String, dynamic>{},
        'model.test.product.fields_view_get': (_) => {
              'type': 'tree',
              'arch': '<tree><field name="name"/></tree>',
              'fields': {
                'name': {'type': 'char', 'string': 'Name'},
              },
            },
        'model.test.product.search': (_) => [1, 2],
        'model.test.product.search_count': (_) => 2,
        'model.test.product.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'P$id', 'rec_name': 'P$id', '_timestamp': '1'}
            ],
        'model.test.product.view_toolbar_get': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.form.resources': (_) => <String, dynamic>{},
      });

  Finder inDialog(Finder f) =>
      find.descendant(of: find.byType(Dialog).last, matching: f);

  group('pre_validate', () {
    testWidgets('OK of the popup asks the server before taking the record',
        (tester) async {
      final rpc = server('pre_validate="1"');
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      await tester.tap(find.byKey(const ValueKey('x2m-new')));
      await tester.pumpAndSettle();
      await tester.enterText(inDialog(find.byType(TextField)), 'Line A');
      await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Add')));
      await tester.pumpAndSettle();
      final call = rpc.named('model.test.line.pre_validate').single;
      expect((call.params[0] as Map)['name'], 'Line A');
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Line A'), findsOneWidget, reason: 'in the list');
    }, variant: desktop);

    testWidgets('an error of pre_validate keeps the popup open',
        (tester) async {
      final rpc = server('pre_validate="1"',
          preValidate: (_) => throw const UserError('Not allowed'));
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      await tester.tap(find.byKey(const ValueKey('x2m-new')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Add')));
      await tester.pumpAndSettle();
      expect(find.text('Not allowed'), findsOneWidget, reason: 'warning');
      await tester.tap(find.byKey(const ValueKey('dialog-ok')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Add'), findsOneWidget,
          reason: 'form dialog still open');
    }, variant: desktop);

    testWidgets('without pre_validate no call', (tester) async {
      final rpc = server('');
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      await tester.tap(find.byKey(const ValueKey('x2m-new')));
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Add')));
      await tester.pumpAndSettle();
      expect(rpc.named('model.test.line.pre_validate'), isEmpty);
    }, variant: desktop);
  });

  testWidgets('product: a search dialog per field, one record per chosen '
      'value with the defaults', (tester) async {
    final rpc = server('product="product"');
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(find.byKey(const ValueKey('x2m-new')));
    await tester.pumpAndSettle();
    // the search dialog of test.product: all rows chosen
    expect(rpc.named('model.test.product.search'), isNotEmpty);
    final boxes = inDialog(find.byType(Checkbox));
    for (var i = 0; i < boxes.evaluate().length; i++) {
      if (tester.widget<Checkbox>(boxes.at(i)).value != true) {
        await tester.tap(boxes.at(i));
        // (the rows also wait for a double click)
        await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
        await tester.pumpAndSettle();
      }
    }
    await tester.tap(inDialog(find.widgetWithText(FilledButton, 'OK')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('P1'), findsOneWidget);
    expect(find.text('P2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
    final lines = (rpc.named('model.test.form.write').single.params[1] as Map)['lines']
        as List;
    final create = lines.singleWhere((c) => (c as List).first == 'create') as List;
    final values = create[1] as List;
    expect([for (final v in values) (v as Map)['product']], [1, 2]);
    expect([for (final v in values) (v as Map)['name']], ['Default', 'Default'],
        reason: 'the defaults of the first record');
  }, variant: desktop);
}

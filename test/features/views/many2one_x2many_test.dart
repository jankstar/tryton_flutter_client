import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/views/embedded_tree_widget.dart';

import 'form_harness.dart';

/// Many2One (9.2.6), x2many popups (9.2.7) and the dialogs (11.1, 11.2)
/// with a fake RPC.
void main() {
  const arch = '<form col="4">'
      '<label name="name"/><field name="name"/>'
      '<label name="partner"/><field name="partner"/>'
      '<field name="categories" colspan="4"/>'
      '</form>';

  Map<String, Object? Function(List<dynamic>)> handlers({
    List<int> categories = const [],
    Object? size,
  }) =>
      {
        'model.test.form.fields_view_get': (_) => formView(arch, {
              'name': {'type': 'char', 'string': 'Name'},
              'partner': {
                'type': 'many2one',
                'string': 'Partner',
                'relation': 'test.party',
              },
              'categories': {
                'type': 'many2many',
                'string': 'Categories',
                'relation': 'test.cat',
                'size': ?size,
              },
            }),
        'model.test.form.read': (p) => [
              {
                'id': 1,
                'name': 'Order',
                'partner': null,
                'partner.': null,
                'categories': categories,
                'rec_name': 'Order',
                '_timestamp': '1',
              }
            ],
        'model.test.form.write': (_) => null,
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        // Relation views: list and form
        'model.test.party.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'view_id': 20,
                'arch': '<tree><field name="name"/></tree>',
                'fields': {
                  'name': {'type': 'char', 'string': 'Name'}
                },
              }
            : formView('<form><label name="name"/><field name="name"/></form>', {
                'name': {'type': 'char', 'string': 'Name'}
              }),
        'model.test.party.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'P$id', 'rec_name': 'P$id', '_timestamp': '1'}
            ],
        'model.test.cat.fields_view_get': (p) => {
              'type': p[1],
              'view_id': p[1] == 'tree' ? 30 : 31,
              'arch': p[1] == 'tree'
                  ? '<tree><field name="name"/></tree>'
                  : '<form><label name="name"/><field name="name"/></form>',
              'fields': {
                'name': {'type': 'char', 'string': 'Name'}
              },
            },
        'model.test.cat.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'C$id', 'rec_name': 'C$id', '_timestamp': '1'}
            ],
      };

  Finder m2o() => find.byKey(const ValueKey('m2o-partner'));

  String m2oText(WidgetTester tester) =>
      tester.widget<TextField>(m2o()).controller!.text;

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.save));
    await pumpFrames(tester);
  }

  testWidgets('autocomplete: typing offers entries, the choice is set',
      (tester) async {
    final rpc = FakeFormRpc({
      ...handlers(),
      'model.test.party.autocomplete': (p) => [
            {'id': 5, 'name': 'Acme'},
            {'id': null, 'name': 'Ac', 'defaults': {}},
          ],
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1, settle: false);
    await tester.enterText(m2o(), 'Ac');
    await tester.pump(const Duration(milliseconds: 350));
    await pumpFrames(tester, 5);
    final call = rpc.named('model.test.party.autocomplete').single;
    expect(call.params.sublist(0, 2), ['Ac', <dynamic>[]]);
    expect(find.text('Create "Ac"...'), findsOneWidget);
    expect(find.text('Search...'), findsOneWidget);

    await tester.tap(find.text('Acme'));
    await pumpFrames(tester);
    expect(m2oText(tester), 'Acme');
    await save(tester);
    expect(rpc.named('model.test.form.write').single.params[1],
        containsPair('partner', 5));
  });

  testWidgets('text without choice: search dialog for several hits, '
      'one hit is taken directly', (tester) async {
    var hits = [1, 2];
    final rpc = FakeFormRpc({
      ...handlers(),
      'model.test.party.autocomplete': (_) => <dynamic>[],
      'model.test.party.search': (_) => hits,
      'model.test.party.search_count': (_) => hits.length,
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1, settle: false);
    await tester.enterText(m2o(), 'P');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester);
    expect(find.text('Search Partner'), findsOneWidget);
    final search = rpc.named('model.test.party.search').single;
    expect(search.params[0], [
      ['rec_name', 'ilike', '%P%']
    ]);
    await tester.tap(find.text('P2'));
    await tester.pump(kDoubleTapTimeout);
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await pumpFrames(tester);
    expect(find.text('Search Partner'), findsNothing);
    expect(m2oText(tester), 'P2');

    // Clear, then a text with exactly one hit: no dialog.
    await tester.tap(find.byKey(const ValueKey('m2o-clear-partner')));
    await pumpFrames(tester, 5);
    hits = [7];
    await tester.enterText(m2o(), 'P7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFrames(tester);
    expect(find.text('Search Partner'), findsNothing);
    expect(m2oText(tester), 'P7');
  });

  testWidgets('F3 opens the form popup for a new record with the text',
      (tester) async {
    final rpc = FakeFormRpc({
      ...handlers(),
      'model.test.party.autocomplete': (_) => <dynamic>[],
      'model.test.party.default_get': (_) => {'name': 'New Co'},
      'model.test.party.create': (_) => [9],
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1, settle: false);
    await tester.enterText(m2o(), 'New Co');
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await pumpFrames(tester);
    final defaults = rpc.named('model.test.party.default_get').single;
    expect(defaults.context['default_rec_name'], 'New Co');
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpFrames(tester);
    expect(rpc.named('model.test.party.create').single.params[0], [
      {'name': 'New Co'}
    ]);
    expect(m2oText(tester), 'P9', reason: 'rec_name read after saving');
  });

  testWidgets('many2many: Add via search dialog (multiple), without the '
      'contained records', (tester) async {
    final rpc = FakeFormRpc({
      ...handlers(categories: [1]),
      'model.test.cat.search': (_) => [2, 3],
      'model.test.cat.search_count': (_) => 2,
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1, settle: false);
    final list = find.byType(EmbeddedTreeWidget);
    expect(find.descendant(of: list, matching: find.text('C1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('x2m-add')));
    await pumpFrames(tester);
    final search = rpc.named('model.test.cat.search').single;
    expect(search.params[0].toString(), contains('[id, not in, [1]]'));
    final dialog = find.byType(Dialog);
    await tester.tap(find.descendant(of: dialog, matching: find.text('C2')));
    await tester.pump(kDoubleTapTimeout);
    await tester.tap(find.descendant(of: dialog, matching: find.text('C3')));
    await tester.pump(kDoubleTapTimeout);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await pumpFrames(tester);
    expect(find.descendant(of: list, matching: find.text('C3')), findsOneWidget);

    await save(tester);
    expect(rpc.named('model.test.form.write').single.params[1], {
      'categories': [
        [
          'add',
          [2, 3]
        ]
      ]
    });
  });

  testWidgets('size limit disables New and Add', (tester) async {
    final rpc = FakeFormRpc(handlers(categories: [1], size: 1));
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1, settle: false);
    IconButton button(String key) => tester.widget<IconButton>(find.descendant(
        of: find.byKey(ValueKey(key)), matching: find.byType(IconButton)));
    expect(button('x2m-add').onPressed, isNull);
    expect(button('x2m-new').onPressed, isNull);
  });
}

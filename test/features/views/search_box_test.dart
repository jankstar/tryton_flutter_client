import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';

import 'form_harness.dart';

/// Search bar (spec 8.4) with DomainParser syntax (7.3) and a fake RPC.
void main() {
  FakeFormRpc server({List<dynamic> searchValue = const []}) => FakeFormRpc({
        'model.ir.model.list_models': (_) => ['test.form'],
        'model.ir.model.access.get_access': (p) => {
              for (final m in p[0] as List)
                m: {'read': 1, 'write': 1, 'create': 1, 'delete': 1}
            },
        'model.ir.ui.view_search.get': (_) => {
              'test.form': [
                [
                  7,
                  'Drafts',
                  [
                    ['state', '=', 'draft']
                  ],
                  true
                ],
              ]
            },
        'model.ir.ui.view_search.set': (_) => 8,
        'model.res.user.get_preferences': (p) => p[0] == false
            ? {
                'locale': {
                  'date': '%d.%m.%Y',
                  'decimal_point': ',',
                  'thousands_sep': '.'
                }
              }
            : <String, dynamic>{},
        'model.test.form.fields_view_get': (_) => {
              'type': 'tree',
              'view_id': 3,
              'arch': '<tree><field name="name"/><field name="state"/>'
                  '<field name="amount"/><field name="active"/></tree>',
              'fields': {
                'name': {'type': 'char', 'string': 'Name'},
                'state': {
                  'type': 'selection',
                  'string': 'State',
                  'selection': [
                    ['draft', 'Draft'],
                    ['done', 'Done'],
                  ],
                },
                'amount': {'type': 'float', 'string': 'Amount'},
                'active': {'type': 'boolean', 'string': 'Active'},
              },
            },
        'model.test.form.search': (_) => [1],
        'model.test.form.read': (p) => [
              for (final id in p[0] as List)
                {
                  'id': id,
                  'name': 'N$id',
                  'state': 'draft',
                  'amount': 1.0,
                  'active': true,
                  '_timestamp': '1'
                }
            ],
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  Finder text() => find.byKey(const ValueKey('search-text'));
  String shown(WidgetTester tester) =>
      tester.widget<TextField>(text()).controller!.text;
  FormCall lastSearch(FakeFormRpc rpc) =>
      rpc.named('model.test.form.search').last;

  Future<void> search(WidgetTester tester, String value) async {
    await tester.enterText(text(), value);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await pumpFrames(tester);
  }

  testWidgets('input → domain of the search call, text normalized',
      (tester) async {
    final rpc = server();
    await pumpScreen(tester, rpc, const ScreenAttributes('test.form'),
        settle: false, metadata: true);
    await search(tester, 'name: doe  state: draft amount: >1.000,5');
    expect(lastSearch(rpc).params[0], [
      ['name', 'ilike', '%doe%'],
      ['state', '=', 'draft'],
      ['amount', '>', 1000.5],
    ]);
    expect(shown(tester), 'Name: doe State: Draft Amount: >1.000,5');

    await search(tester, 'free');
    expect(lastSearch(rpc).params[0], [
      ['rec_name', 'ilike', '%free%']
    ]);
  });

  testWidgets('the action search_value is the first search, shown as text',
      (tester) async {
    final rpc = server();
    await pumpScreen(
        tester,
        rpc,
        const ScreenAttributes('test.form', searchValue: [
          ['state', '=', 'done']
        ]),
        settle: false,
        metadata: true);
    expect(rpc.named('model.test.form.search').first.params[0], [
      ['state', '=', 'done']
    ]);
    expect(shown(tester), 'State: Done');
  });

  testWidgets('bookmarks: save with the star, apply from the list',
      (tester) async {
    final rpc = server();
    await pumpScreen(tester, rpc, const ScreenAttributes('test.form'),
        settle: false, metadata: true);
    await tester.enterText(text(), 'Name: Foo');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('search-star')));
    await pumpFrames(tester, 5);
    await tester.enterText(find.byKey(const ValueKey('bookmark-name')), 'Mine');
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await pumpFrames(tester, 5);
    expect(rpc.named('model.ir.ui.view_search.set').single.params,
        ['Mine', 'test.form', '[["name","ilike","%Foo%"]]']);
    // The text is a bookmark now: filled star.
    expect(find.byIcon(Icons.star), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('search-bookmarks')));
    await pumpFrames(tester, 5);
    await tester.tap(find.text('Drafts').last);
    await pumpFrames(tester);
    expect(lastSearch(rpc).params[0], [
      ['state', '=', 'draft']
    ]);
    expect(shown(tester), 'State: Draft');
  });

  testWidgets('show inactive records: active = false, active_test = false',
      (tester) async {
    final rpc = server();
    await pumpScreen(tester, rpc, const ScreenAttributes('test.form'),
        settle: false, metadata: true);
    await tester.tap(find.byKey(const ValueKey('search-active')));
    await pumpFrames(tester);
    final call = lastSearch(rpc);
    expect(call.params[0], [
      ['active', '=', false]
    ]);
    expect(call.context['active_test'], isFalse);
  });

  testWidgets('filter dialog builds the search text', (tester) async {
    final rpc = server();
    await pumpScreen(tester, rpc, const ScreenAttributes('test.form'),
        settle: false, metadata: true);
    await tester.tap(find.byKey(const ValueKey('search-filter')));
    await pumpFrames(tester, 5);
    await tester.enterText(find.byKey(const ValueKey('filter-name')), 'Doe');
    await tester.enterText(find.byKey(const ValueKey('filter-from-amount')), '1');
    await tester.enterText(find.byKey(const ValueKey('filter-to-amount')), '5');
    await tester.tap(find.widgetWithText(FilterChip, 'Done'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Find'));
    await pumpFrames(tester);
    expect(lastSearch(rpc).params[0], [
      ['name', 'ilike', '%Doe%'],
      ['state', '=', 'done'], // one value: '=' (like the Python client)
      [
        ['amount', '>=', 1.0],
        ['amount', '<=', 5.0]
      ], // range: nested (like the Python client)
    ]);
  });

  testWidgets('completion offers the labels', (tester) async {
    final rpc = server();
    await pumpScreen(tester, rpc, const ScreenAttributes('test.form'),
        settle: false, metadata: true);
    await tester.tap(text());
    await tester.enterText(text(), 'Sta');
    await tester.pump();
    // Completions are trimmed (SAO `e.trim()`).
    expect(find.text('State:'), findsOneWidget);
    await tester.tap(find.text('State:'));
    await tester.pump();
    expect(shown(tester), 'State:');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';

import 'form_harness.dart';

/// Search bar (spec 8.4) with DomainParser syntax (7.3) and a fake RPC.
void main() {
  FakeFormRpc server(
          {List<dynamic> searchValue = const [],
          Map<String, dynamic> extraFields = const {},
          String extraArch = ''}) =>
      FakeFormRpc({
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
                  '<field name="amount"/><field name="active"/>$extraArch'
                  '</tree>',
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
                ...extraFields,
              },
            },
        'model.test.form.get_kinds': (_) => [
              [null, ''],
              ['z', 'Zulu'],
              ['a', 'Alpha'],
              ['m', 'Mike Two'],
            ],
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
    await tester.enterText(find.byKey(const ValueKey('dialog-ask')), 'Mine');
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
    await tester.tap(find.byKey(const ValueKey('filter-state-Done')));
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

  Future<void> openFilter(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('search-filter')));
    await pumpFrames(tester, 5);
  }

  Future<void> find_(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('filter-find')));
    await pumpFrames(tester);
  }

  bool checked(WidgetTester tester, String key) => tester
      .widget<Checkbox>(find.descendant(
          of: find.byKey(ValueKey(key)), matching: find.byType(Checkbox)))
      .value!;

  testWidgets(
      'filter: static selection is a sorted check list, several values '
      '→ "A;B" → in', (tester) async {
    final rpc = server();
    await pumpScreen(tester, rpc, const ScreenAttributes('test.form'),
        settle: false, metadata: true);
    await openFilter(tester);
    // a row per option with a check box, sorted by label
    final rows = tester
        .widgetList<Text>(find.descendant(
            of: find.byKey(const ValueKey('filter-state')),
            matching: find.byType(Text)))
        .map((t) => t.data)
        .toList();
    expect(rows, ['Done', 'Draft']);
    expect(checked(tester, 'filter-state-Draft'), isFalse);
    await tester.tap(find.byKey(const ValueKey('filter-state-Draft')));
    await tester.pump();
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('filter-state-Done')),
        matching: find.byType(Checkbox)));
    await tester.pump();
    expect(checked(tester, 'filter-state-Draft'), isTrue);
    expect(checked(tester, 'filter-state-Done'), isTrue);
    await find_(tester);
    expect(shown(tester), 'State: Done;Draft');
    expect(lastSearch(rpc).params[0], [
      ['state', 'in', ['done', 'draft']]
    ]);

    // reopened after the search: the choice is kept; Clear empties it
    await openFilter(tester);
    expect(checked(tester, 'filter-state-Done'), isTrue);
    await tester.tap(find.byKey(const ValueKey('filter-clear')));
    await tester.pump();
    expect(checked(tester, 'filter-state-Done'), isFalse);
    expect(checked(tester, 'filter-state-Draft'), isFalse);
    await tester.tap(find.byKey(const ValueKey('filter-state-Draft')));
    await tester.pump();
    await find_(tester);
    expect(lastSearch(rpc).params[0], [
      ['state', '=', 'draft']
    ]);

    // another search text (cleared): the dialog starts empty
    await tester.tap(find.byTooltip('Clear'));
    await pumpFrames(tester);
    await openFilter(tester);
    expect(checked(tester, 'filter-state-Draft'), isFalse);
  });

  testWidgets(
      'filter: method selection is loaded (sort=False keeps the order), '
      'labels with spaces quoted', (tester) async {
    final rpc = server(extraFields: {
      'kind': {
        'type': 'selection',
        'string': 'Kind',
        'selection': 'get_kinds',
        'sort': false,
        'readonly': true,
      },
    }, extraArch: '<field name="kind"/>');
    await pumpScreen(tester, rpc, const ScreenAttributes('test.form'),
        settle: false, metadata: true);
    expect(rpc.named('model.test.form.get_kinds'), hasLength(1));
    await openFilter(tester);
    final rows = tester
        .widgetList<Text>(find.descendant(
            of: find.byKey(const ValueKey('filter-kind')),
            matching: find.byType(Text)))
        .map((t) => t.data)
        .toList();
    // (the screen sorts the method selection by label like Python
    // `Screen.get_selection`; `sort` False keeps that order)
    expect(rows, ['""', 'Alpha', 'Mike Two', 'Zulu']);
    await tester.tap(find.byKey(const ValueKey('filter-kind-Mike Two')));
    await tester.tap(find.byKey(const ValueKey('filter-kind-Alpha')));
    await tester.pump();
    await find_(tester);
    expect(shown(tester), 'Kind: Alpha;"Mike Two"');
    expect(lastSearch(rpc).params[0], [
      ['kind', 'in', ['a', 'm']]
    ]);
  });
}

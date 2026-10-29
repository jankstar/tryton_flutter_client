import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/auth/user_preferences_provider.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';
import 'package:tryton_flutter_client/features/tabs/menu_sidebar.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

import '../views/form_harness.dart';

/// Menu of `pyson_menu` (F1) with favorites (F2), opened by `tree_open`.
void main() {
  // pyson_menu of trytond 8.0 (get_preferences(false), shortened).
  final pysonMenu = jsonEncode({
    'type': 'ir.action.act_window',
    'res_model': 'ir.ui.menu',
    'views': [
      [3, 'tree']
    ],
    'pyson_domain': jsonEncode([
      ['parent', '=', null]
    ]),
    'pyson_order': jsonEncode([
      ['sequence', 'ASC NULLS LAST'],
      ['id', null]
    ]),
    'pyson_context': '{}',
    'limit': null,
  });
  final menu = {
    1: {'name': 'Parties', 'childs': <int>[], 'favorite': false},
    2: {'name': 'Sales', 'childs': [21], 'favorite': true},
    21: {'name': 'Orders', 'childs': <int>[], 'favorite': false},
  };

  FakeFormRpc server() => FakeFormRpc({
        'model.ir.ui.menu.fields_view_get': (_) => {
              'type': 'tree',
              'view_id': 3,
              'field_childs': 'childs',
              'arch': '<tree keyword_open="1" tree_state="1">'
                  '<field name="name"/><field name="icon"/>'
                  '<field name="favorite" tree_invisible="1"/></tree>',
              'fields': {
                'name': {'type': 'char', 'string': 'Menu'},
                'icon': {'type': 'char', 'string': 'Icon'},
                'favorite': {'type': 'boolean', 'string': 'Favorite'},
                'childs': {
                  'type': 'one2many',
                  'string': 'Children',
                  'relation': 'ir.ui.menu',
                  'relation_field': 'parent',
                },
              },
            },
        'model.ir.ui.menu.search': (_) => [1, 2],
        'model.ir.ui.menu.read': (p) => [
              for (final id in p[0] as List)
                {
                  'id': id,
                  ...menu[id]!,
                  'icon': null,
                  '_timestamp': '1',
                }
            ],
        'model.ir.ui.menu.favorite.get': (_) => [
              [2, 'Sales', 'tryton-sale']
            ],
        'model.ir.ui.menu.favorite.set': (_) => null,
        'model.ir.action.keyword.get_keyword': (p) => [
              {
                'type': 'ir.action.act_window',
                'name': 'Parties',
                'res_model': 'party.party',
                'domains': const [],
              }
            ],
      });

  Future<ProviderContainer> pumpMenu(
      WidgetTester tester, FakeFormRpc rpc) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final svc = ModelService(
        rpc: rpc,
        getContext: () => {'language': 'en'},
        getDatabase: () => 'test');
    final container = ProviderContainer(overrides: [
      rpcClientProvider.overrideWithValue(rpc),
      modelServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(container.dispose);
    container.read(preferencesProvider.notifier).state = {
      'pyson_menu': pysonMenu
    };
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: MenuSidebar()),
      ),
    ));
    await pumpFrames(tester);
    return container;
  }

  testWidgets('menu tree of pyson_menu; entry → tree_open → tab',
      (tester) async {
    final rpc = server();
    final container = await pumpMenu(tester, rpc);

    // The action's view, domain and order, no limit; no own search_read.
    final view = rpc.named('model.ir.ui.menu.fields_view_get').single;
    expect(view.params, [3, 'tree']);
    final search = rpc.named('model.ir.ui.menu.search').single;
    expect(search.params[0], [
      ['parent', '=', null]
    ]);
    expect(search.params[2], isNull, reason: 'no limit');
    expect(search.params[3], [
      ['sequence', 'ASC NULLS LAST'],
      ['id', null]
    ]);
    expect(rpc.named('model.ir.ui.menu.search_read'), isEmpty);

    expect(find.text('Parties'), findsOneWidget);
    // Favorites on top (and the entry itself in the tree).
    expect(find.text('Sales'), findsNWidgets(2));
    expect(find.text('Orders'), findsNothing, reason: 'collapsed');

    await tester.tap(find.byKey(const ValueKey('menu-1')));
    await pumpFrames(tester);
    final keyword = rpc.named('model.ir.action.keyword.get_keyword').single;
    expect(keyword.params, [
      'tree_open',
      ['ir.ui.menu', 1]
    ]);
    final tabs = container.read(tabsProvider).tabs;
    expect(tabs.single.title, 'Parties', reason: 'without ids: no suffix');
    expect(tabs.single.attributes.model, 'party.party');

    // A parent expands (and is remembered) and opens its action, too.
    await tester.tap(find.byKey(const ValueKey('menu-2')));
    await pumpFrames(tester);
    expect(find.text('Orders'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(prefs.getKeys().single), ['2']);
  });

  testWidgets('star → ir.ui.menu.favorite.set', (tester) async {
    final rpc = server();
    await pumpMenu(tester, rpc);
    expect(find.byKey(const ValueKey('menu-star-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menu-star-1')));
    await pumpFrames(tester);
    expect(rpc.named('model.ir.ui.menu.favorite.set').single.params, [1]);
    expect(
        tester
            .widget<Icon>(find.descendant(
                of: find.byKey(const ValueKey('menu-star-1')),
                matching: find.byType(Icon)))
            .icon,
        Icons.star);
    // favorites loaded again
    expect(rpc.named('model.ir.ui.menu.favorite.get'), hasLength(2));
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/app.dart';
import 'package:tryton_flutter_client/core/session/session.dart';
import 'package:tryton_flutter_client/core/session/session_store.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/shell/menu_width.dart';
import 'package:tryton_flutter_client/features/tabs/menu_sidebar.dart';

import '../views/form_harness.dart';

class _NoStore implements SessionStore {
  @override
  Future<StoredSession?> read([String? key]) async => null;
  @override
  Future<void> write(StoredSession session) async {}
  @override
  Future<void> delete([String? key]) async {}
}

class _Session extends TrytonSession {
  _Session(FakeFormRpc rpc) : super(rpcClient: rpc, store: _NoStore());
  @override
  Future<bool> restore([String? key]) async => true;
}

/// Narrow windows (< [menuToggleWidth], decision 2026-11-22): like on a
/// phone the menu does not stand beside the tabs – the tab bar stays on
/// top, below either the menu or the tabs in the full width; the menu
/// button switches, a menu entry shows its tab at once; wide windows keep
/// the menu beside the tabs.
void main() {
  FakeFormRpc server() => FakeFormRpc({
        'model.res.user.get_preferences': (_) => {
              'language': 'en',
              'status_bar': 'Administrator',
              'pyson_menu': jsonEncode({
                'type': 'ir.action.act_window',
                'res_model': 'ir.ui.menu',
                'views': [
                  [3, 'tree']
                ],
                'pyson_domain': jsonEncode([
                  ['parent', '=', null]
                ]),
                'pyson_context': '{}',
              }),
            },
        'model.ir.ui.menu.fields_view_get': (_) => {
              'type': 'tree',
              'view_id': 3,
              'field_childs': 'childs',
              'arch': '<tree><field name="name"/></tree>',
              'fields': {
                'name': {'type': 'char', 'string': 'Menu'},
                'childs': {
                  'type': 'one2many',
                  'string': 'Children',
                  'relation': 'ir.ui.menu',
                  'relation_field': 'parent'
                },
              },
            },
        'model.ir.ui.menu.search': (_) => [1],
        'model.ir.ui.menu.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'Parties', 'childs': <int>[], '_timestamp': '1'}
            ],
        'model.ir.action.keyword.get_keyword': (_) => [
              {
                'type': 'ir.action.act_window',
                'name': 'Parties',
                'res_model': 'test.party',
                'domains': const [],
                'views': [
                  [null, 'tree']
                ],
              }
            ],
        'model.test.party.fields_view_get': (_) => {
              'type': 'tree',
              'view_id': 11,
              'arch': '<tree><field name="name"/></tree>',
              'fields': {
                'name': {'type': 'char', 'string': 'Name'}
              },
            },
        'model.test.party.search': (_) => [1],
        'model.test.party.search_count': (_) => 1,
        'model.test.party.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'Acme', '_timestamp': '1'}
            ],
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  Future<void> pumpApp(WidgetTester tester, Size size) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final rpc = server();
    final svc = ModelService(
        rpc: rpc, getContext: () => {'language': 'en'}, getDatabase: () => 'test');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        rpcClientProvider.overrideWithValue(rpc),
        modelServiceProvider.overrideWithValue(svc),
        sessionProvider.overrideWithValue(_Session(rpc)),
      ],
      child: const TrytonFlutterClientApp(),
    ));
    await pumpFrames(tester, 40);
  }

  /// The menu entry „Parties“ can be seen and tapped.
  Finder menuEntry() =>
      find.byKey(const ValueKey('menu-1')).hitTestable();

  testWidgets('narrow: menu or tabs, the button switches, a menu entry '
      'shows its tab at once', (tester) async {
    await pumpApp(tester, const Size(500, 800));
    // no tab open: only the menu (no empty page), nothing to switch to
    for (var i = 0; i < 40 && menuEntry().evaluate().isEmpty; i++) {
      await pumpFrames(tester, 5);
    }
    expect(menuEntry(), findsOneWidget, reason: 'only the menu');
    IconButton toggle() => tester.widget<IconButton>(
        find.byKey(const ValueKey('menu-toggle')));
    expect(toggle().onPressed, isNull);
    expect(tester.getSize(find.byType(MenuSidebar)).width, 500,
        reason: 'in the full width');

    // a menu entry opens its tab and shows it at once (like on a phone)
    await tester.tap(menuEntry());
    await pumpFrames(tester, 40);
    expect(menuEntry(), findsNothing, reason: 'switched to the tab');
    expect(find.text('Acme').hitTestable(), findsOneWidget);
    expect(toggle().onPressed, isNotNull, reason: 'a tab: the button switches');

    // the button switches back and forth; the tab keeps its state
    await tester.tap(find.byKey(const ValueKey('menu-toggle')));
    await pumpFrames(tester, 10);
    expect(menuEntry(), findsOneWidget);
    expect(find.text('Acme').hitTestable(), findsNothing);
    await tester.tap(find.byKey(const ValueKey('menu-toggle')));
    await pumpFrames(tester, 10);
    expect(find.text('Acme').hitTestable(), findsOneWidget);

    // the last tab closed: only the menu again
    await tester.tap(find.descendant(
        of: find.byType(InputChip), matching: find.byIcon(Icons.close)));
    await pumpFrames(tester, 20);
    expect(menuEntry(), findsOneWidget, reason: 'no tab: the menu');
    expect(toggle().onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}

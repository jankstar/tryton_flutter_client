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

/// Wide windows (≥ [menuToggleWidth]): the menu stays beside the tabs.
/// (Own file: a second app start in one test process shows an empty menu
/// – an open finding, see narrow_menu_test.dart.)
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

  testWidgets('wide (≥ 640 px): the menu beside the tabs as before',
      (tester) async {
    await pumpApp(tester, const Size(900, 800));
    // (on stage: the menu stands beside the tabs)
    final entry = find.byKey(const ValueKey('menu-1'));
    for (var i = 0; i < 40 && entry.evaluate().isEmpty; i++) {
      await pumpFrames(tester, 5);
    }
    expect(entry, findsOneWidget, reason: 'the menu is open');
    expect(tester.getSize(find.byType(MenuSidebar)).width, lessThan(900),
        reason: 'beside the tabs');
    await tester.tap(entry);
    await pumpFrames(tester, 40);
    expect(entry, findsOneWidget, reason: 'the menu stays beside');
    expect(find.text('Acme'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Acme')).dx,
        greaterThan(tester.getSize(find.byType(MenuSidebar)).width),
        reason: 'the tab right of the menu');
  });
}

import 'dart:convert';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/shell/app_shell.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';

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

/// A tab gives its content its own size as the window size (MediaQuery):
/// beside the menu a form decides its layout by the width it really has –
/// with the window's width the address form of a 450 px tab kept its
/// columns and squeezed the check box group (overflow).
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
        'model.party.address.fields_view_get': (_) => formView(
            '<form col="6"><label name="party"/><field name="party" colspan="5"/>'
            '<label name="party_name"/><field name="party_name"/><label name="attn"/><field name="attn"/>'
            '<group colspan="2" col="-1" id="checkboxes"><label name="active"/>'
            '<field name="active" xexpand="0" width="25"/><label name="invoice"/>'
            '<field name="invoice" xexpand="0" width="25"/><label name="delivery"/>'
            '<field name="delivery" xexpand="0" width="25"/><label name="sequence"/>'
            '<field name="sequence"/></group></form>', {
              'party': {'type': 'many2one', 'string': 'Partei', 'relation': 'party.party'},
              'party_name': {'type': 'char', 'string': 'Partei-Name'},
              'attn': {'type': 'char', 'string': 'z. Hd.'},
              'active': {'type': 'boolean', 'string': 'Aktiv'},
              'invoice': {'type': 'boolean', 'string': 'Rechnung'},
              'delivery': {'type': 'boolean', 'string': 'Lieferadresse'},
              'sequence': {'type': 'integer', 'string': 'Reihenfolge'},
            }),
        'model.party.address.read': (_) => [
              {'id': 1, 'party': 5, 'party.': {'rec_name': 'Mieter 30'}, 'party_name': '', 'attn': '',
               'active': true, 'invoice': true, 'delivery': true, 'sequence': 1, '_timestamp': '1'}
            ],
        'model.party.address.resources': (_) => <String, dynamic>{},
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

  testWidgets('a form in a tab beside the menu takes the tab\'s width: '
      'one column below 600 px, no squeezed group', (tester) async {
    // 700 px window, the menu (250 px) beside: a tab of about 450 px
    await pumpApp(tester, const Size(700, 600));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    container.read(tabsProvider.notifier).openTab(
        title: 'Adresse',
        attributes: const ScreenAttributes('party.address',
            mode: ['form'], resId: 1));
    await pumpFrames(tester, 40);
    expect(tester.takeException(), isNull, reason: 'no overflow');
    // the narrow layout: no label cells („Aktiv:“), the check boxes with
    // their text beside them
    expect(find.text('Aktiv:'), findsNothing);
    expect(find.text('Aktiv'), findsOneWidget);
    expect(find.text('Lieferadresse'), findsOneWidget);
    final tab = tester.getSize(find.byType(IndexedStack).last);
    expect(tab.width, lessThan(600));
  });

  testWidgets('a wide tab keeps the columns and the label cells',
      (tester) async {
    await pumpApp(tester, const Size(1200, 600));
    final container =
        ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    container.read(tabsProvider.notifier).openTab(
        title: 'Adresse',
        attributes: const ScreenAttributes('party.address',
            mode: ['form'], resId: 1));
    await pumpFrames(tester, 40);
    expect(tester.takeException(), isNull);
    expect(find.text('Aktiv:'), findsOneWidget, reason: 'label cells');
  });
}

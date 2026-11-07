import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/session/session.dart';
import 'package:tryton_flutter_client/core/session/session_store.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/auth/preferences_dialog.dart';
import 'package:tryton_flutter_client/features/auth/user_preferences_provider.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

import '../views/form_harness.dart';

class _NoStore implements SessionStore {
  @override
  Future<StoredSession?> read() async => null;
  @override
  Future<void> write(StoredSession session) async {}
  @override
  Future<void> delete() async {}
}

/// Preferences dialog (spec 3.3, B11).
void main() {
  final preferences = {
    'name': 'Administrator',
    'password': 'xxxxxxxxxx',
    'language': 'de',
    'company': 1,
    'company.rec_name': 'ImmoBau GmbH',
    'status_bar': 'Administrator',
  };

  testWidgets('tabs closed after the question; changed values sent with '
      'set_preferences; preferences reloaded', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var current = Map<String, dynamic>.from(preferences);
    final rpc = FakeFormRpc({
      'model.res.user.get_preferences_fields_view': (_) => {
            'type': 'form',
            'view_id': null,
            'arch': '<form><label name="name"/><field name="name"/>'
                '<label name="password"/><field name="password" widget="password"/>'
                '<label name="language"/><field name="language"/>'
                '<label name="company"/><field name="company" widget="selection"/></form>',
            'fields': {
              'name': {'type': 'char', 'string': 'Name', 'required': true},
              'password': {'type': 'char', 'string': 'Password'},
              'language': {
                'type': 'selection',
                'string': 'Language',
                'selection': [
                  ['de', 'German'],
                  ['en', 'English']
                ],
              },
              'company': {
                'type': 'many2one',
                'string': 'Company',
                'relation': 'company.company'
              },
            },
          },
      'model.res.user.get_preferences': (p) => current,
      'model.res.user.set_preferences': (p) {
        current = {...current, ...(p[0] as Map).cast<String, dynamic>(), 'status_bar': 'New Name'};
        return null;
      },
      'model.company.company.search_read': (_) => [
            {'id': 1, 'rec_name': 'ImmoBau GmbH'}
          ],
    })
      ..auth = const SessionAuth('admin', 1, 'tok');
    final session = TrytonSession(rpcClient: rpc, store: _NoStore())
      ..database = 'test'
      ..userId = 1
      ..login = 'admin';
    final svc = ModelService(
        rpc: rpc, getContext: () => const {}, getDatabase: () => 'test');
    final container = ProviderContainer(overrides: [
      rpcClientProvider.overrideWithValue(rpc),
      sessionProvider.overrideWithValue(session),
      modelServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(container.dispose);
    container.read(tabsProvider.notifier).openTab(title: 'A', model: 'a');
    bool? saved;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  saved = await showPreferencesDialog(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('requires to close all tabs'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs, isEmpty);
    expect(find.byKey(const ValueKey('preferences-dialog')), findsOneWidget);
    final name = textFieldOf('Name');
    expect(tester.widget<TextField>(name).controller!.text, 'Administrator');
    expect(find.text('ImmoBau GmbH'), findsWidgets, reason: 'company.rec_name');

    await tester.enterText(name, 'New Name');
    await tester.tap(find.byKey(const ValueKey('preferences-ok')));
    await tester.pumpAndSettle();
    expect(rpc.named('model.res.user.set_preferences').single.params, [
      {'name': 'New Name'}
    ], reason: 'only the changed values (password stays out)');
    expect(saved, isTrue);
    expect(find.byKey(const ValueKey('preferences-dialog')), findsNothing);
    // context and preferences reloaded → user chip
    expect(rpc.named('model.res.user.get_preferences').map((c) => c.params.first),
        containsAll([true, false]));
    expect(container.read(preferencesProvider)?['status_bar'], 'New Name');
  });
}

@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/auth/user_preferences_provider.dart';
import 'package:tryton_flutter_client/features/model/metadata_service.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/views/record_form.dart';
import 'package:tryton_flutter_client/features/views/screen_widget.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

/// Form widgets against the Tryton test server, read only (E10–E13, H4):
/// the party form with its addresses (`mode="form,tree"`) and numbers in
/// the user's locale.
///
///     TRYTON_PASSWORD=… flutter test --run-skipped -t integration
const _server = 'http://127.0.0.1:8000';
const _database = 'tryton';

void main() {
  // Real timers and HTTP for the widgets (the default test binding fakes
  // the clock and blocks HTTP).
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  final password = Platform.environment['TRYTON_PASSWORD'];

  testWidgets('party form: addresses as inline form, switch to the table',
      (tester) async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    HttpOverrides.global = null;
    late RpcClient rpc;
    late ModelService svc;
    late Map<String, dynamic> preferences;
    late int partyId;
    await tester.runAsync(() async {
      rpc = RpcClient(baseUrl: _server);
      final result = await rpc.call(_database, 'common.db.login', [
        'admin',
        {'password': password},
        'de'
      ], reAuth: false) as List;
      rpc.auth = SessionAuth('admin', result[0] as int, result[1] as String);
      var context = <String, dynamic>{};
      svc = ModelService(
          rpc: rpc, getContext: () => context, getDatabase: () => _database);
      final prefs = await svc.execute<Map<String, dynamic>>(
          'res.user', 'get_preferences', [true]);
      context = {
        for (final e in prefs.entries)
          if (e.key != 'locale' && !e.key.endsWith('.rec_name')) e.key: e.value
      };
      preferences = await svc.execute<Map<String, dynamic>>(
          'res.user', 'get_preferences', [false]);
      await (svc.metadata = MetadataService(svc))
          .load(locale: preferences['locale'] as Map<String, dynamic>?);
      final ids = await svc.execute<List>('party.party', 'search', [
        [
          ['addresses', '!=', null]
        ],
        0,
        1,
        null
      ]);
      partyId = ids.first as int;
    });
    addTearDown(() => tester.runAsync(() async {
          try {
            await rpc.call(_database, 'common.db.logout', [], reAuth: false);
          } catch (_) {}
        }));

    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        rpcClientProvider.overrideWithValue(rpc),
        modelServiceProvider.overrideWithValue(svc),
        preferencesProvider.overrideWith((ref) => preferences),
      ],
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScreenWidget(
            attributes: ScreenAttributes('party.party',
                mode: const ['form'], resId: partyId),
            title: 'Partei'),
      ),
    ));
    Future<void> settle(Finder until) async {
      for (var i = 0; i < 100 && until.evaluate().isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      // a few more rounds for the lazily loaded rows
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    }

    await settle(find.byKey(const ValueKey('x2m-position')));
    expect(tester.takeException(), isNull);
    expect(find.byType(RecordForm), findsWidgets);
    // Language (many2one with widget="selection"): a dropdown of ir.lang
    final lang = find.byWidgetPredicate((w) =>
        w is DropdownButtonFormField<int?> &&
        '${w.key}'.contains('m2o-selection-lang'));
    expect(lang, findsOneWidget);
    await tester.ensureVisible(lang);
    await tester.tap(lang);
    await settle(find.byType(DropdownMenuItem<int?>));
    final items = tester
        .widgetList<DropdownMenuItem<int?>>(find.byType(DropdownMenuItem<int?>))
        .map((i) => i.value)
        .toSet();
    // (the empty entry at the end lies outside the built part of the menu)
    expect(items.length, greaterThan(1), reason: 'languages of ir.lang');
    // close the menu without a choice
    await tester.tapAt(Offset.zero);
    await settle(find.byKey(const ValueKey('x2m-position')));

    // Addresses (mode="form,tree"): the form of the first address
    expect(find.byKey(const ValueKey('x2m-position')), findsOneWidget);
    expect(find.text('1 / ${_count(tester)}'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('x2m-switch')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('x2m-switch')));
    await settle(find.byType(DataTable));
    expect(tester.takeException(), isNull);
    expect(find.byType(DataTable), findsWidgets,
        reason: 'switched to the table view 166');
  });
}

/// Number of addresses from the position text „1 / n“.
String _count(WidgetTester tester) {
  final text =
      tester.widget<Text>(find.byKey(const ValueKey('x2m-position'))).data!;
  return text.split(' / ').last;
}

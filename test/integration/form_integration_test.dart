@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/icons/tryton_icon.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/auth/user_preferences_provider.dart';
import 'package:tryton_flutter_client/features/model/metadata_service.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/views/record_form.dart';
import 'package:tryton_flutter_client/features/views/screen_widget.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';
import 'package:tryton_flutter_client/shared/utils/number_format_utils.dart';

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

  testWidgets('lists: party amounts, ir.model.log date/time and reference',
      (tester) async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    HttpOverrides.global = null;
    late RpcClient rpc;
    late ModelService svc;
    late Map<String, dynamic> preferences;
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
    });
    addTearDown(() => tester.runAsync(() async {
          try {
            await rpc.call(_database, 'common.db.logout', [], reAuth: false);
          } catch (_) {}
        }));
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    List<String> texts() => [
          for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? ''
        ];
    final time = RegExp(r'^\d\d:\d\d:\d\d\.\d{6}$');

    Future<void> show(String model, bool Function() ready,
        {List<dynamic> domain = const [], List<dynamic>? order}) async {
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
              key: ValueKey(model),
              attributes:
                  ScreenAttributes(model,
                      mode: const ['tree'],
                      limit: 30,
                      domain: domain,
                      order: order),
              title: model),
        ),
      ));
      for (var i = 0; i < 150 && !ready(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    }

    await show('party.party', () => find.byType(Checkbox).evaluate().length > 2);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('list-column-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('header-name#0')), findsOneWidget);

    // old logs of parties (logs of deleted records, e.g. CLAUDE-TEST,
    // read their resource as null)
    await show('ir.model.log', () => texts().any(time.hasMatch), domain: [
      ['resource', 'like', 'party.party,%']
    ], order: [
      ['id', 'ASC']
    ]);
    expect(tester.takeException(), isNull);
    // the same field twice: Date and Hour (with fractions of seconds)
    expect(find.byKey(const ValueKey('header-create_date#0')), findsOneWidget);
    expect(find.byKey(const ValueKey('header-create_date#1')), findsOneWidget);
    final shown = texts();
    expect(shown.any(time.hasMatch), isTrue,
        reason: 'time column %H:%M:%S.%f');
    expect(shown.any((t) => RegExp(r'^\d\d\.\d\d\.\d{4}$').hasMatch(t)),
        isTrue, reason: 'date column in the locale date format');
    expect(shown.any((t) => t.endsWith(':') && t.length > 1), isTrue,
        reason: 'reference: model label before the rec_name');
  });

  testWidgets('sums: move lines in the move form and as list', (tester) async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    HttpOverrides.global = null;
    late RpcClient rpc;
    late ModelService svc;
    late Map<String, dynamic> preferences;
    late int moveId;
    late String expected;
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
      // a move with lines; the expected debit total from the server
      final moves = await svc.execute<List>('account.move', 'search_read', [
        [
          ['lines', '!=', null]
        ],
        0,
        1,
        null,
        ['lines']
      ]);
      moveId = (moves.first as Map)['id'] as int;
      final lines = await svc.execute<List>('account.move.line', 'read', [
        (moves.first as Map)['lines'],
        ['debit']
      ]);
      var total = 0.0;
      for (final l in lines) {
        final d = (l as Map)['debit'];
        total += d is TrytonDecimal ? d.toDouble() : (d as num).toDouble();
      }
      expected = formatNumericValue(total,
          digits: const [16, 2],
          locale: 'de',
          numberLocale: NumberLocale.fromPreferences(preferences['locale']));
    });
    addTearDown(() => tester.runAsync(() async {
          try {
            await rpc.call(_database, 'common.db.logout', [], reAuth: false);
          } catch (_) {}
        }));
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<void> show(ScreenAttributes attributes, Finder ready) async {
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
              key: ValueKey(attributes.model), attributes: attributes, title: 'x'),
        ),
      ));
      String? text() => ready.evaluate().isEmpty
          ? null
          : (ready.evaluate().first.widget as Text).data;
      for (var i = 0; i < 150 && (text() == null || text() == '-'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
    }

    // embedded lines of the move form (move_line_tree_move, sum="1")
    final x2mSum = find.byKey(const ValueKey('x2m-sum-debit#0'));
    await show(ScreenAttributes('account.move', mode: const ['form'], resId: moveId),
        x2mSum);
    expect(tester.takeException(), isNull);
    expect((tester.widget<Text>(x2mSum)).data, '$expected\n$expected');

    // the same lines as list
    final listSum = find.byKey(const ValueKey('sum-debit#0'));
    await show(
        ScreenAttributes('account.move.line', mode: const ['tree'], domain: [
          ['move', '=', moveId]
        ]),
        listSum);
    expect(tester.takeException(), isNull);
    expect((tester.widget<Text>(listSum)).data, '$expected\n$expected');
  });

  testWidgets('button icons: billing unit 1 – module icons from ir.ui.icon, '
      'own icons from the assets', (tester) async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    HttpOverrides.global = null;
    late RpcClient rpc;
    late ModelService svc;
    late Map<String, dynamic> preferences;
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
      IconFactory.clear();
      IconFactory.setService(svc);
      await IconFactory.loadIcons();
    });
    addTearDown(() => tester.runAsync(() async {
          IconFactory.clear();
          IconFactory.setService(null);
          try {
            await rpc.call(_database, 'common.db.logout', [], reAuth: false);
          } catch (_) {}
        }));
    tester.view.physicalSize = const Size(1600, 1100);
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
            attributes: const ScreenAttributes('real_estate.billing_unit',
                mode: ['form'], resId: 1),
            title: 'Abrechnungseinheit'),
      ),
    ));
    final buttons = find.byType(RecordButton);
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
      final icons = find.descendant(of: buttons, matching: find.byType(SvgPicture));
      if (buttons.evaluate().isNotEmpty &&
          icons.evaluate().length >= buttons.evaluate().length) {
        break;
      }
    }
    expect(tester.takeException(), isNull);
    expect(buttons, findsWidgets, reason: 'the visible buttons of state');
    final withIcon = [
      for (final e in buttons.evaluate())
        if ((e.widget as RecordButton).node.icon != null) e.widget as RecordButton
    ];
    expect(withIcon, isNotEmpty);
    for (final b in withIcon) {
      final svg = find.descendant(
          of: find.byWidget(b), matching: find.byType(SvgPicture));
      expect(svg, findsOneWidget, reason: '${b.node.name}: ${b.node.icon}');
    }
  });
}

/// Number of addresses from the position text „1 / n“.
String _count(WidgetTester tester) {
  final text =
      tester.widget<Text>(find.byKey(const ValueKey('x2m-position'))).data!;
  return text.split(' / ').last;
}

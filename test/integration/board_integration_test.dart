@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/xml/form_xml_parser.dart';
import 'package:tryton_flutter_client/core/xml/view_definition.dart';
import 'package:tryton_flutter_client/features/actions/action_service.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/auth/user_preferences_provider.dart';
import 'package:tryton_flutter_client/features/model/metadata_service.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';
import 'package:tryton_flutter_client/features/views/board_view.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

/// Board (spec 9.7, E33) against the Tryton test server, read only: the
/// menu „Dashboard“ opens a board tab, which loads its arch with
/// `ir.ui.view.view_get` and a screen per `<action>`.
///
///     TRYTON_PASSWORD=… flutter test --run-skipped -t integration
const _server = 'http://127.0.0.1:8000';
const _database = 'tryton';

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  final password = Platform.environment['TRYTON_PASSWORD'];

  testWidgets('menu „Dashboard“ opens the board', (tester) async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    HttpOverrides.global = null;
    late RpcClient rpc;
    late ModelService svc;
    late Map<String, dynamic> preferences;
    late Map<String, dynamic> context;
    late int userId;
    final tabs = TabsNotifier();
    int? menuId;
    var actionCount = 0;
    await tester.runAsync(() async {
      rpc = RpcClient(baseUrl: _server);
      final result = await rpc.call(_database, 'common.db.login', [
        'admin',
        {'password': password},
        'de'
      ], reAuth: false) as List;
      userId = result[0] as int;
      rpc.auth = SessionAuth('admin', userId, result[1] as String);
      context = {};
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
      final menus = await svc.execute<List>('ir.ui.menu', 'search', [
        [
          ['name', '=', 'Dashboard'],
        ],
        0,
        1,
        null
      ]);
      if (menus.isEmpty) return;
      menuId = menus.first as int;
      // the menu entry as the sidebar opens it
      await ActionService(svc, tabs,
              sessionContext: () => context, userId: () => userId)
          .execKeyword('tree_open', {'model': 'ir.ui.menu', 'id': menuId},
              warning: false);
      final tab = tabs.state.tabs.singleOrNull;
      if (tab == null) return;
      final view = await svc.execute<Map<String, dynamic>>(
          'ir.ui.view', 'view_get', [tab.attributes.viewIds.first]);
      actionCount = _actions(FormXmlParser().parse('${view['arch']}').children);
    });
    addTearDown(() => tester.runAsync(() async {
          try {
            await rpc.call(_database, 'common.db.logout', [], reAuth: false);
          } catch (_) {}
        }));
    if (menuId == null) {
      markTestSkipped('no menu „Dashboard“ (module dashboard)');
      return;
    }
    final tab = tabs.state.tabs.single;
    expect(tab.isBoard, isTrue, reason: 'first view board');
    expect(tab.attributes.viewIds, hasLength(1));

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
        home: BoardView(attributes: tab.attributes, title: tab.title),
      ),
    ));
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    expect(find.text(tab.title), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'arch and actions loaded');
    // one frame per <action> of the user's dashboard (none for a new user)
    expect(find.byWidgetPredicate((w) => '${w.key}'.contains('board-action-')),
        findsNWidgets(actionCount));
  });
}

int _actions(List<FormNode> nodes) {
  var n = 0;
  for (final node in nodes) {
    switch (node) {
      case ActionNode():
        n++;
      case GroupNode():
        n += _actions(node.children);
      case NotebookNode():
        for (final p in node.pages) {
          n += _actions(p.children);
        }
      default:
        break;
    }
  }
  return n;
}

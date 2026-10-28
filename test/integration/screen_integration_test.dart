@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/actions/act_window.dart';
import 'package:tryton_flutter_client/features/model/model_rpc.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';

/// Screen (list of party.party) against the Tryton test server, read
/// only (not part of `flutter test`, the tag `integration` is skipped in
/// dart_test.yaml).
///
///     TRYTON_PASSWORD=… flutter test --run-skipped -t integration
const _server = 'http://127.0.0.1:8000';
const _database = 'tryton';

void main() {
  final env = Platform.environment;
  final password = env['TRYTON_PASSWORD'];
  final login = env['TRYTON_LOGIN'] ?? 'admin';
  late RpcClient rpc;
  late ModelService svc;
  late Map<String, dynamic> context;

  setUpAll(() async {
    if (password == null) return;
    rpc = RpcClient(baseUrl: _server);
    final result = await rpc.call(_database, 'common.db.login', [
      login,
      {'password': password},
      'de'
    ], reAuth: false) as List;
    rpc.auth = SessionAuth(login, result[0] as int, result[1] as String);
    context = {};
    svc = ModelService(
        rpc: rpc, getContext: () => context, getDatabase: () => _database);
    final prefs = await svc.execute<Map<String, dynamic>>(
        'res.user', 'get_preferences', [true]);
    context = {
      for (final e in prefs.entries)
        if (e.key != 'locale' && !e.key.endsWith('.rec_name')) e.key: e.value
    };
  });

  tearDownAll(() async {
    if (password == null) return;
    try {
      await rpc.call(_database, 'common.db.logout', [], reAuth: false);
    } catch (_) {}
  });

  test('read: list of party.party – search, count, sort, rows, form',
      () async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    // The party action as the menu opens it.
    final actions = await svc.searchRead('ir.action.act_window',
        domain: [
          ['res_model', '=', 'party.party']
        ],
        fields: actWindowFields,
        limit: 1);
    expect(actions, isNotEmpty);
    final action = ScreenAttributes.fromActWindow(actions.first.values,
        sessionContext: context);
    final attributes = ScreenAttributes(
      action.model,
      mode: action.mode,
      viewIds: action.viewIds,
      domain: action.domain,
      context: action.context,
      order: action.order,
      limit: 3,
    );
    final screen = TrytonScreen(attributes, session: modelSessionFor(svc))
      ..screenSize = () => [1200, 800];
    addTearDown(screen.dispose);

    await screen.switchView(viewType: 'tree');
    expect(screen.currentView!.viewType, 'tree');
    expect(screen.currentView!.fieldChilds, isNull);

    await screen.searchFilter();
    final total = await svc.execute<int>(
        'party.party', 'search_count', [screen.searchDomain()]);
    expect(screen.group.length, total < 3 ? total : 3);
    expect(screen.searchCount, total);

    // Row values with neighbours in one read.
    final first = screen.group.first;
    await first.load('name');
    expect(screen.group.every((r) => r.isLoaded('name')), isTrue);
    expect(first.fieldGet('name'), isA<String>());

    if (total > 3) {
      expect(screen.hasMore, isTrue);
      await screen.searchMore();
      expect(screen.group.length, total < 6 ? total : 6);
    }

    // Sorting by name: ASC and DESC give the first/last name.
    await screen.sortBy('name');
    await screen.group.first.load('name');
    final ascFirst = screen.group.first.fieldGet('name');
    await screen.sortBy('name');
    expect(screen.sortDirection('name'), 'DESC');
    await screen.group.first.load('name');
    if (total > 1) {
      expect(screen.group.first.fieldGet('name'), isNot(ascFirst));
    }

    // The form shares the record and loads all its fields.
    final record = screen.group.first;
    screen.currentRecord = record;
    expect(await screen.switchView(viewType: 'form'), isTrue);
    expect(identical(screen.currentRecord, record), isTrue);
    expect(record.isLoaded('addresses'), isTrue);
    expect(screen.statusText, startsWith('1'));
  });
}

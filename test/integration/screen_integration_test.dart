@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/model/model.dart';
import 'package:tryton_flutter_client/core/rpc/error_processing.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/core/wizard/wizard.dart';
import 'package:tryton_flutter_client/features/actions/action_service.dart';
import 'package:tryton_flutter_client/features/model/metadata_service.dart';
import 'package:tryton_flutter_client/features/model/model_rpc.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';

/// Screen (list of party.party) against the Tryton test server, read
/// only (not part of `flutter test`, the tag `integration` is skipped in
/// dart_test.yaml).
///
///     TRYTON_PASSWORD=… flutter test --run-skipped -t integration
const _server = 'http://127.0.0.1:8000';
const _database = 'tryton';

/// [ActionUi] that runs a wizard up to its first view and cancels it
/// (records what it saw).
class _CancelUi implements ActionUi {
  String? viewModel;
  List<WizardButton> buttons = const [];

  @override
  Future<void> runWizard(TrytonWizard wizard,
      {required bool window, required String title}) async {
    await wizard.run();
    viewModel = wizard.screen?.model.name;
    buttons = wizard.buttons;
    if (!wizard.done) await wizard.cancel();
  }

  @override
  RpcErrorProcessor? get errorProcessor => null;
  @override
  Future<void> message(String text) async {}
  @override
  Future<Map<String, dynamic>?> choose(
          List<Map<String, dynamic>> actions) async =>
      null;
  @override
  Future<void> openUrl(String url) async {}
  @override
  String get noActionDefined => '';
  @override
  String get nameSeparator => ', ';
  @override
  String generatingReport() => '';
  @override
  String reportGenerated(String name, String format) => '';
  @override
  String notSupported(String name, String type) => '';
}

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
    final ids = await svc.execute<List>('ir.action.act_window', 'search', [
      [
        ['res_model', '=', 'party.party']
      ],
      0,
      1,
      null
    ]);
    expect(ids, isNotEmpty);
    final values = await svc.execute<Map<String, dynamic>>(
        'ir.action', 'get_action_value', [ids.first]);
    final action =
        ScreenAttributes.fromActWindow(values, sessionContext: context);
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

  test('read: open a party → run a relate action (keyword, name suffix)',
      () async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    // Open the first party in a form screen.
    final ids = await svc.execute<List>('party.party', 'search', [
      <dynamic>[],
      0,
      1,
      null
    ]);
    expect(ids, isNotEmpty);
    final id = ids.first as int;
    final form = TrytonScreen(
        ScreenAttributes('party.party', mode: const ['form'], resId: id),
        session: modelSessionFor(svc));
    addTearDown(form.dispose);
    form.load([id]);
    form.currentRecord = form.group.first;
    await form.switchView();
    final recName = await form.currentRecord!.recName();

    // Relate actions of the toolbar, the first act_window is run.
    final toolbar = await svc.execute<Map>('party.party', 'view_toolbar_get', []);
    final relate = [
      for (final a in (toolbar['relate'] as List? ?? const []))
        if (a is Map && a['type'] == 'ir.action.act_window')
          Map<String, dynamic>.from(a)
    ];
    if (relate.isEmpty) {
      markTestSkipped('no relate action for party.party');
      return;
    }
    final tabs = TabsNotifier();
    final service = ActionService(svc, tabs,
        sessionContext: () => context, userId: () => null);
    await service.execute(relate.first,
        data: {
          'model': 'party.party',
          'id': id,
          'ids': [id]
        },
        context: form.localContext,
        keyword: true);
    final tab = tabs.state.tabs.single;
    expect(tab.title, '${relate.first['name']} ($recName)');
    expect(tab.attributes.domain.toString(), isNot(contains('__class__')),
        reason: 'PYSON evaluated with active_id(s)');

    // The opened screen searches without error.
    final related =
        TrytonScreen(tab.attributes, session: modelSessionFor(svc));
    addTearDown(related.dispose);
    await related.switchView();
    expect(await related.searchFilter(), isTrue);
    expect(related.searchCount, greaterThanOrEqualTo(0));
  });

  test('read: wizard party.check_vies on a party without VAT id → cancel',
      () async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    final wizardIds = await svc.execute<List>('ir.action.wizard', 'search', [
      [
        ['wiz_name', '=', 'party.check_vies']
      ],
      0,
      1,
      null
    ]);
    if (wizardIds.isEmpty) {
      markTestSkipped('party.check_vies not installed');
      return;
    }
    // A party without identifiers: check_vies changes nothing.
    final parties = await svc.searchRead('party.party',
        fields: ['identifiers'], limit: 200);
    final party = parties.firstWhere(
        (p) => (p['identifiers'] as List? ?? const []).isEmpty);

    final ui = _CancelUi();
    final service = ActionService(svc, TabsNotifier(),
        sessionContext: () => context, userId: () => null);
    await service.execute(wizardIds.first as int,
        data: {
          'model': 'party.party',
          'id': party.id,
          'ids': [party.id]
        },
        keyword: true,
        ui: ui);
    expect(ui.viewModel, 'party.check_vies.result',
        reason: 'transition "check", then the result view');
    expect(ui.buttons.map((b) => (b.state, b.isDefault)), [('end', true)]);
  });

  test('party → add and remove a category without saving', () async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    final ids = await svc.execute<List>('party.party', 'search', [
      <dynamic>[],
      0,
      1,
      null
    ]);
    final id = ids.first as int;
    final form = TrytonScreen(
        ScreenAttributes('party.party', mode: const ['form'], resId: id),
        session: modelSessionFor(svc));
    addTearDown(form.dispose);
    form.load([id]);
    form.currentRecord = form.group.first;
    await form.switchView();
    final record = form.currentRecord!;
    final field = record.model.fields['categories'];
    if (field == null) {
      markTestSkipped('party form without categories');
      return;
    }
    final group = record.fieldGetClient('categories') as RecordGroup;
    final existing = [for (final r in group) r.id];

    // Add: like the search dialog, a category not contained yet.
    final candidates = await svc.execute<List>('party.category', 'search', [
      [
        field.getDomain(record),
        ['id', 'not in', existing]
      ],
      0,
      1,
      null
    ]);
    if (candidates.isEmpty) {
      if (env['TRYTON_WRITE_TEST'] != '1') {
        markTestSkipped('no further category (TRYTON_WRITE_TEST=1 creates one)');
        return;
      }
      // Temporary category with the test prefix, deleted afterwards.
      final created = await svc.execute<List>('party.category', 'create', [
        [
          {'name': 'CLAUDE-TEST category'}
        ]
      ]);
      addTearDown(() => svc.execute<dynamic>('party.category', 'delete', [created]));
      candidates.addAll(created);
    }
    final added = candidates.first as int;
    group.load([added], modified: true);
    expect(record.modified, isTrue);
    expect(field.get(record), [
      [
        'add',
        [added]
      ]
    ]);

    // Remove (unlink) the added one again: no command is left.
    group.remove(group.get(added)!, remove: true);
    expect((field.get(record) as List).where((c) => c[0] == 'add'), isEmpty);
    if (existing.isNotEmpty) {
      group.remove(group.get(existing.first)!, remove: true);
      expect(field.get(record), contains([
        'remove',
        [existing.first]
      ]));
    }
    // Nothing saved: discard.
    record.cancel();
  });

  test('read: metadata – get_access for some models, names, history',
      () async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    final metadata = MetadataService(svc);
    await metadata.load();
    for (final model in ['party.party', 'res.user', 'ir.model']) {
      final access = await metadata.access(model);
      expect(access.read, isTrue, reason: '$model readable for $login');
    }
    // One batch covers the neighbours of the list.
    expect(metadata.accessOf('party.party'), isNotNull);
    final name = await metadata.name('party.party');
    expect(name, isNotEmpty);
    // MODELHISTORY is a (possibly empty) set; it decides the revisions menu.
    expect(metadata.hasHistory('ir.model'), isA<bool>());
    // Rights flow into the data layer.
    final session = modelSessionFor(svc..metadata = metadata);
    final screen = TrytonScreen(
        const ScreenAttributes('party.party', mode: ['tree']),
        session: session);
    addTearDown(screen.dispose);
    expect(screen.model.access.read, isTrue);
  });
}

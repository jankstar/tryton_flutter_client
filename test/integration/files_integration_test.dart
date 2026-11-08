@Tags(['integration'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/core/session/session.dart';
import 'package:tryton_flutter_client/core/session/session_store.dart';
import 'package:tryton_flutter_client/features/actions/action_service.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/auth/preferences_dialog.dart';
import 'package:tryton_flutter_client/features/model/metadata_service.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/views/csv_dialogs.dart';
import 'package:tryton_flutter_client/features/views/resource_dialogs.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';
import 'package:tryton_flutter_client/shared/utils/csv_format.dart';
import 'package:tryton_flutter_client/shared/utils/file_actions.dart';

/// Files against the Tryton test server (E13, F8, F9, G2): avatar of the
/// preferences as image, CSV export (field tree, export_data), report
/// output, attachments – read only; predefined export and CSV import
/// only with `TRYTON_WRITE_TEST=1` (prefix CLAUDE-TEST, removed again).
///
///     TRYTON_PASSWORD=… [TRYTON_WRITE_TEST=1] flutter test --run-skipped -t integration
const _server = 'http://127.0.0.1:8000';
const _database = 'tryton';

class _NoStore implements SessionStore {
  @override
  Future<StoredSession?> read() async => null;
  @override
  Future<void> write(StoredSession session) async {}
  @override
  Future<void> delete() async {}
}

/// Records written/opened files instead of opening them on the machine.
class _FakeFiles extends FileActions {
  final written = <(String, List<int>)>[];
  final opened = <String>[];
  final printed = <String>[];

  @override
  Future<String> writeTemp(String name, List<int> bytes) async {
    written.add((name, bytes));
    return '/tmp/$name';
  }

  @override
  Future<void> open(String path) async => opened.add(path);

  @override
  Future<void> print(String name, String type, Uint8List bytes, String path) async =>
      printed.add(path);
}

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final password = env['TRYTON_PASSWORD'];
  final write = env['TRYTON_WRITE_TEST'] == '1';

  /// Logged-in session (German), context of the preferences, metadata.
  Future<(RpcClient, ModelService, int)> login() async {
    final rpc = RpcClient(baseUrl: _server);
    final result = await rpc.call(_database, 'common.db.login', [
      'admin',
      {'password': password},
      'de'
    ], reAuth: false) as List;
    final userId = result[0] as int;
    rpc.auth = SessionAuth('admin', userId, result[1] as String);
    var context = <String, dynamic>{};
    final svc = ModelService(
        rpc: rpc, getContext: () => context, getDatabase: () => _database);
    final prefs = await svc.execute<Map<String, dynamic>>(
        'res.user', 'get_preferences', [true]);
    context = {
      for (final e in prefs.entries)
        if (e.key != 'locale' && !e.key.endsWith('.rec_name')) e.key: e.value
    };
    final full = await svc.execute<Map<String, dynamic>>(
        'res.user', 'get_preferences', [false]);
    await (svc.metadata = MetadataService(svc))
        .load(locale: full['locale'] as Map<String, dynamic>?);
    return (rpc, svc, userId);
  }

  Future<void> logout(RpcClient rpc) async {
    try {
      await rpc.call(_database, 'common.db.logout', [], reAuth: false);
    } catch (_) {}
  }

  testWidgets('preferences: the avatar is shown as image (read only)',
      (tester) async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    HttpOverrides.global = null;
    late RpcClient rpc;
    late ModelService svc;
    late int userId;
    await tester.runAsync(() async => (rpc, svc, userId) = await login());
    addTearDown(() => tester.runAsync(() => logout(rpc)));
    final session = TrytonSession(rpcClient: rpc, store: _NoStore())
      ..database = _database
      ..userId = userId
      ..login = 'admin';
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        rpcClientProvider.overrideWithValue(rpc),
        sessionProvider.overrideWithValue(session),
        modelServiceProvider.overrideWithValue(svc),
      ],
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => showPreferencesDialog(context, ref),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    final image = find.byKey(const ValueKey('image-avatar'));
    for (var i = 0; i < 100 && image.evaluate().isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('preferences-dialog')), findsOneWidget);
    expect(image, findsOneWidget, reason: 'avatar (binary, widget image)');
    // with a value: Save As and Clear (Python `update_buttons`), editable
    expect(find.byKey(const ValueKey('binary-clear-avatar')), findsOneWidget);
    expect(find.byKey(const ValueKey('binary-save-avatar')), findsOneWidget);
    // closed without saving
    await tester.tap(find.text('Abbrechen'));
    await tester.pump(const Duration(milliseconds: 500));
  });

  test('CSV export: field tree with relations, export_data with header '
      'and the CSV text; attachments of a party', () async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    final (rpc, svc, _) = await login();
    addTearDown(() => logout(rpc));
    final l10n = lookupAppLocalizations(const Locale('de'));
    final tree = CsvFieldTree(svc, 'party.party', svc.sessionContext(),
        import: false, l10n: l10n);
    await tree.load();
    expect(tree.fields['name'], isNotNull);
    final city = await tree.resolve('addresses/city');
    expect(city, isNotNull, reason: 'addresses expanded');
    expect(city!.label, contains('/'));

    final ids = await svc.execute<List>('party.party', 'search', [
      [
        ['addresses', '!=', null]
      ],
      0,
      3,
      null
    ]);
    final data = await svc.execute<List>('party.party', 'export_data', [
      ids,
      ['name', 'addresses/city'],
      true
    ]);
    expect(data.length, greaterThan(ids.length - 1));
    final header = data.first as List;
    expect(header.length, 2);
    final text = csvText([
      for (final row in data)
        formatCsvRow(row as List, context: svc.metadata?.parserContext)
    ], delimiter: ';');
    expect(text.split('\r\n').first, '${header[0]};${header[1]}');

    // F8: attachments (≤ 20) of the first party
    final attachments = await attachmentsOf(svc, (
      model: 'party.party',
      id: ids.first as int,
      recName: '',
      context: const <String, dynamic>{}
    ));
    expect(attachments.length, lessThanOrEqualTo(20));
  });

  test('report: execute a party report and write/open its file', () async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    final (rpc, svc, _) = await login();
    addTearDown(() => logout(rpc));
    final toolbar = await svc.viewToolbarGet('party.party');
    if (toolbar.print.isEmpty) {
      markTestSkipped('no report for party.party');
      return;
    }
    final report = toolbar.print.first;
    final ids = await svc.execute<List>('party.party', 'search', [[], 0, 1, null]);
    final result = await svc.executeMethod<List>(
        'report.${report.reportName}.execute', [
      ids,
      {'model': 'party.party', 'id': ids.first, 'ids': ids}
    ], context: {
      'direct_print': false
    });
    final [type, content, _, name] = result;
    expect(type, isA<String>());
    final bytes = content is TrytonBytes
        ? Uint8List.fromList(content.bytes)
        : Uint8List.fromList('$content'.codeUnits);
    expect(bytes, isNotEmpty);
    final files = FileActions.instance = _FakeFiles();
    addTearDown(() => FileActions.instance = FileActions());
    await ActionService.outputReport('$name', '$type', bytes);
    expect(files.written, isNotEmpty);
    if (type != 'zip') expect(files.written.single.$1, endsWith('.$type'));
    expect(files.opened, hasLength(files.written.length));
  });

  test('write: predefined export (ir.export set/get/update/unset) and CSV '
      'import of a CLAUDE-TEST party', () async {
    if (password == null || !write) {
      markTestSkipped('TRYTON_PASSWORD / TRYTON_WRITE_TEST=1 not set');
      return;
    }
    final (rpc, svc, _) = await login();
    addTearDown(() => logout(rpc));
    int? exportId;
    final imported = <int>[];
    try {
      exportId = (await svc.execute<num>('ir.export', 'set', [
        {
          'name': 'CLAUDE-TEST Export',
          'resource': 'party.party',
          'header': true,
          'records': 'listed',
          'ignore_search_limit': false,
          'export_fields': [
            {'name': 'name'}
          ],
        }
      ])).toInt();
      await svc.execute<dynamic>('ir.export', 'update', [
        exportId,
        {'header': false, 'records': 'selected', 'ignore_search_limit': false},
        ['name', 'code']
      ]);
      final exports = await svc.execute<List>('ir.export', 'get', [
        'party.party',
        ['name', 'header', 'records', 'ignore_search_limit', 'export_fields.name'],
      ]);
      final mine = exports.cast<Map>().firstWhere((e) => e['id'] == exportId);
      expect(mine['header'], false);
      expect(mine['records'], 'selected');
      expect([for (final f in mine['export_fields.'] as List) (f as Map)['name']],
          ['name', 'code']);
      // in the print menu after clearing the cache
      svc.clearCache('model.party.party.view_toolbar_get');
      final toolbar = await svc.viewToolbarGet('party.party');
      expect(toolbar.exports.map((e) => e['id']), contains(exportId));

      // CSV import (spec 11.8)
      final rows = parseCsv('Name\r\nCLAUDE-TEST Import\r\n');
      final count = await svc.execute<num>('party.party', 'import_data', [
        ['name'],
        [
          for (final r in rows.skip(1)) [for (final v in r) parseCsvValue(v, 'char')]
        ],
      ]);
      expect(count, 1);
      imported.addAll((await svc.execute<List>('party.party', 'search', [
        [
          ['name', '=', 'CLAUDE-TEST Import']
        ],
        0,
        null,
        null
      ]))
          .cast<int>());
      expect(imported, hasLength(1));
    } finally {
      if (exportId != null) {
        await svc.execute<dynamic>('ir.export', 'unset', [exportId]);
      }
      if (imported.isNotEmpty) {
        await svc.execute<dynamic>('party.party', 'delete', [imported]);
      }
    }
    final rest = await svc.execute<List>('ir.export', 'search', [
      [
        ['name', 'like', 'CLAUDE-TEST%']
      ],
      0,
      null,
      null
    ]);
    expect(rest, isEmpty, reason: 'cleaned up');
  });
}

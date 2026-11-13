@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/model/model.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/features/model/concurrency.dart';
import 'package:tryton_flutter_client/features/model/model_rpc.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/shared/errors/error_handler.dart';

/// Data layer against the Tryton test server (not part of `flutter test`,
/// the tag `integration` is skipped in dart_test.yaml).
///
/// Run (the password is only read from the environment, never stored):
///
///     TRYTON_PASSWORD=… flutter test --run-skipped -t integration
///
/// The writing tests additionally need `TRYTON_WRITE_TEST=1`; they create
/// a party `CLAUDE-TEST …` (with an address; a second one for the
/// concurrency conflict), change and delete it, and remove leftovers with
/// that prefix.
const _server = 'http://127.0.0.1:8000';
const _database = 'tryton';
const _prefix = 'CLAUDE-TEST';

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

  Future<TrytonModel> partyModel([ModelSession? session]) async {
    session ??= modelSessionFor(svc);
    final model = TrytonModel('party.party', session: session);
    model.addFields(Map<String, dynamic>.from(await svc
        .execute<Map>('party.party', 'fields_get', [<String>[]])));
    return model;
  }

  /// Like SAO `group.add_fields`: new address records also get the
  /// defaults of the added fields (e.g. `active`).
  Future<void> addAddressFields(RecordGroup addresses) async {
    await addresses.addFieldsWithDefaults(Map<String, dynamic>.from(await svc
        .execute<Map>('party.address', 'fields_get', [<String>[]])));
  }

  test('read: load party.party with neighbours and addresses', () async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    final ids = await svc.execute<List>('party.party', 'search', [
      <dynamic>[],
      0,
      5,
      null
    ]);
    expect(ids, isNotEmpty, reason: 'test database needs parties');
    final group = RecordGroup(await partyModel())..load(ids.cast<int>());
    final first = group.first;
    await first.load('name');
    // Eager loading reads the neighbours in the same call.
    expect(group.every((r) => r.isLoaded('name')), isTrue);
    expect(first.fieldGet('name'), isA<String>());
    expect(first.values['rec_name'], isNotNull);
    expect(first.timestamp, isA<String>());
    expect(first.exception, isFalse);
    final addresses = first.fieldGetClient('addresses') as RecordGroup;
    await addAddressFields(addresses);
    if (addresses.isNotEmpty) {
      await addresses.first.load('city');
      expect(addresses.first.isLoaded('city'), isTrue);
      expect(addresses.first.fieldGet('party'), first.id);
    }
  });

  test('read: form view (fields_view_get) of party.party', () async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    final view = await svc.fieldsViewGet('party.party', viewType: 'form');
    expect(view.rawFields, isNotEmpty);
    final model = TrytonModel('party.party', session: modelSessionFor(svc))
      ..addFields(view.rawFields);
    final ids = await svc.execute<List>('party.party', 'search', [
      <dynamic>[],
      0,
      1,
      null
    ]);
    final group = RecordGroup(model)..load(ids.cast<int>());
    final record = group.first;
    await record.load('*');
    expect(record.exception, isFalse);
    expect(record.validate(softValidation: true), isTrue,
        reason: record.invalidMessage());
    await record.idle;
    for (final field in model.fields.values) {
      field.setState(record);
    }
    expect(record.modified, isFalse, reason: 'loading changes nothing');
    final addresses = record.fieldGetClient('addresses') as RecordGroup;
    expect(addresses.model.fields, isNotEmpty,
        reason: 'sub-view fields of the form view');
  });

  test('write: party with address – create, change, delete', () async {
    if (password == null || env['TRYTON_WRITE_TEST'] != '1') {
      markTestSkipped('TRYTON_PASSWORD / TRYTON_WRITE_TEST=1 not set');
      return;
    }
    final name = '$_prefix ${DateTime.now().toIso8601String()}';
    final model = await partyModel();
    final group = RecordGroup(model);
    try {
      final party = group.add(await group.newRecordWithDefaults());
      await party.fieldSetClient('name', name);
      final addresses = party.fieldGetClient('addresses') as RecordGroup;
      await addAddressFields(addresses);
      // default_get of party.party may already create an empty address
      final address = addresses.isNotEmpty
          ? addresses.first
          : addresses.add(await addresses.newRecordWithDefaults());
      await address.fieldSetClient('city', '$_prefix Stadt');
      await address.idle;
      await party.idle;
      expect(party.validate(), isTrue, reason: party.invalidMessage());

      expect(await party.save(), isTrue);
      expect(party.id, isPositive);
      expect(party.fieldGet('name'), name);
      final saved = party.fieldGetClient('addresses') as RecordGroup;
      await addAddressFields(saved);
      await saved.first.load('city');
      expect(saved.first.fieldGet('city'), '$_prefix Stadt');

      await party.fieldSetClient('name', '$name geändert');
      await saved.first.fieldSetClient('city', '$_prefix Neu');
      await party.idle;
      expect(await party.save(), isTrue);
      expect(party.fieldGet('name'), '$name geändert');
      final changed = party.fieldGetClient('addresses') as RecordGroup;
      await addAddressFields(changed);
      await changed.first.load('city');
      expect(changed.first.fieldGet('city'), '$_prefix Neu');

      expect(await group.delete([party]), isTrue);
      final left = await svc.execute<List>('party.party', 'search', [
        [
          ['id', '=', party.id]
        ]
      ]);
      expect(left, isEmpty);
    } finally {
      // Remove leftovers of this or earlier runs (prefix only).
      final leftovers = await svc.execute<List>('party.party', 'search', [
        [
          ['name', 'like', '$_prefix%']
        ]
      ]);
      if (leftovers.isNotEmpty) {
        await svc.execute<dynamic>('party.party', 'delete', [leftovers]);
      }
    }
  });

  test('write: concurrency – a party changed meanwhile by someone else',
      () async {
    if (password == null || env['TRYTON_WRITE_TEST'] != '1') {
      markTestSkipped('TRYTON_PASSWORD / TRYTON_WRITE_TEST=1 not set');
      return;
    }
    final name = '$_prefix Konflikt ${DateTime.now().toIso8601String()}';
    // the screen's session: error dialogs (ErrorHandler) and the
    // concurrency dialog, here answered by the test
    final shown = <String>[];
    final answers = <ConcurrencyChoice>[];
    final session = modelSessionFor(svc,
        processor: ErrorHandler(
            presenter: _Presenter(shown), skipWarning: (_, _) async {}),
        concurrencyRunner: concurrencyRunner(
          ask: () async {
            shown.add('dialog');
            return answers.removeAt(0);
          },
          onCompare: (_, _) async => shown.add('compare'),
          onMessage: () async => shown.add('message'),
        ));
    Future<String> serverName(int id) async =>
        ((await svc.execute<List>('party.party', 'read', [
          [id],
          ['name']
        ]))
            .first as Map)['name'] as String;
    try {
      final id = ((await svc.execute<List>('party.party', 'create', [
        [
          {'name': name}
        ]
      ]))
          .first as int);
      // this client loads the party (with its _timestamp) …
      final group = RecordGroup(await partyModel(session))..load([id]);
      final party = group.first;
      await party.load('name');
      expect(party.fieldGet('name'), name);
      // … someone else saves it meanwhile …
      await svc.execute<dynamic>('party.party', 'write', [
        [id],
        {'name': '$name anders'}
      ]);
      // … and this client saves its own change: the dialog, no error
      await party.fieldSetClient('name', '$name meins');
      await party.idle;

      answers.add(ConcurrencyChoice.cancel);
      expect(await party.save(), isFalse);
      expect(shown, ['dialog'], reason: 'the dialog, not the error message');
      expect(await serverName(id), '$name anders', reason: 'Cancel: kept');
      expect(party.modified, isTrue, reason: 'the change stays');

      shown.clear();
      answers.add(ConcurrencyChoice.compare);
      expect(await party.save(), isFalse);
      expect(shown, ['dialog', 'compare']);

      shown.clear();
      answers.add(ConcurrencyChoice.writeAnyway);
      expect(await party.save(), isTrue);
      expect(shown, ['dialog']);
      expect(await serverName(id), '$name meins', reason: 'Write Anyway');
    } finally {
      final leftovers = await svc.execute<List>('party.party', 'search', [
        [
          ['name', 'like', '$_prefix%']
        ]
      ]);
      if (leftovers.isNotEmpty) {
        await svc.execute<dynamic>('party.party', 'delete', [leftovers]);
      }
    }
  });
}

/// The dialogs of the error handler as log entries.
class _Presenter implements ErrorPresenter {
  final List<String> log;
  _Presenter(this.log);

  @override
  Future<void> userError(String message, String description) async =>
      log.add('userError:$message');
  @override
  Future<WarningChoice> userWarning(String message, String description) async {
    log.add('warning:$message');
    return WarningChoice.cancel;
  }

  @override
  Future<void> applicationError(String title, String details) async =>
      log.add('app:$title');
  @override
  Future<void> httpError(int? code, String text) async =>
      log.add('http:$code');
  @override
  Future<void> concurrency() async => log.add('error:concurrency');
}

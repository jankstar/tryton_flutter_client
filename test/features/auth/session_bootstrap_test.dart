import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/session/session.dart';
import 'package:tryton_flutter_client/core/session/session_store.dart';
import 'package:tryton_flutter_client/features/auth/session_bootstrap.dart';
import 'package:tryton_flutter_client/features/model/metadata_service.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';

import '../views/form_harness.dart';

class _NoStore implements SessionStore {
  @override
  Future<StoredSession?> read() async => null;
  @override
  Future<void> write(StoredSession session) async {}
  @override
  Future<void> delete() async {}
}

class _Session extends TrytonSession {
  _Session(RpcClient rpc, this.log) : super(rpcClient: rpc, store: _NoStore());
  final List<String> log;
  @override
  Future<void> reloadContext() async => log.add('reload_context');
}

class _Metadata extends MetadataService {
  _Metadata(super.svc, this.log);
  final List<String> log;
  Map<String, dynamic>? loadedLocale;
  @override
  Future<void> load({Map<String, dynamic>? locale}) async {
    loadedLocale = locale;
    log.add('metadata');
  }

  @override
  set locale(Map<String, dynamic>? value) {
    loadedLocale = value;
    log.add('locale');
  }

  @override
  void clearNames() => log.add('clear names');

  @override
  void clear() => log.add('clear metadata');
}

/// Start sequence (spec 3.2, B10).
void main() {
  late List<String> log;
  late FakeFormRpc rpc;
  late _Metadata metadata;
  late SessionBootstrap bootstrap;
  late List<Map<String, dynamic>?> published;
  final preferences = {
    'status_bar': 'Administrator [EUR]',
    'actions': [7, 8],
    'language': 'de',
    'language_direction': 'rtl',
    'locale': {'date': '%d.%m.%Y'},
    'pyson_menu': '{}',
  };

  setUp(() {
    log = [];
    published = [];
    rpc = FakeFormRpc({
      'model.res.user.get_preferences': (p) {
        log.add('get_preferences(${p.single})');
        return preferences;
      },
    });
    final svc = ModelService(
        rpc: rpc, getContext: () => const {}, getDatabase: () => 'tryton');
    metadata = _Metadata(svc, log);
    bootstrap = SessionBootstrap(
      session: _Session(rpc, log),
      svc: svc,
      metadata: metadata,
      runAction: (id) async {
        log.add('action $id');
        if (id == 7) throw StateError('failing start action');
      },
      applyLanguage: (language, direction) async =>
          log.add('language $language $direction'),
      publish: (p) {
        log.add(p == null ? 'publish null' : 'publish');
        published.add(p);
      },
    );
  });

  test('run: context, preferences, metadata, actions, language, menu/chip',
      () async {
    final result = await bootstrap.run();
    expect(log, [
      'reload_context',
      'get_preferences(false)',
      'metadata',
      'action 7', // its error does not stop the start
      'action 8',
      'language de rtl',
      'clear names',
      'publish',
    ]);
    expect(metadata.loadedLocale, {'date': '%d.%m.%Y'});
    expect(result, preferences);
    expect(published.single, preferences);
  });

  test('reload after a context change: no metadata or start actions',
      () async {
    await bootstrap.reload();
    expect(log, [
      'reload_context',
      'get_preferences(false)',
      'locale',
      'language de rtl',
      'clear names',
      'publish',
    ]);
  });

  test('clear at logout', () {
    bootstrap.clear();
    expect(log, ['publish null', 'clear metadata']);
  });
}

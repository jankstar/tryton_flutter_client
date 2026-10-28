import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';

class _FakeRpc extends RpcClient {
  _FakeRpc() : super(baseUrl: 'http://localhost');
  final calls = <(String, String, List<dynamic>)>[];
  dynamic result = <dynamic>[];
  @override
  Future<dynamic> call(String database, String method, List<dynamic> params,
      {bool reAuth = true}) async {
    calls.add((database, method, params));
    return result;
  }
}

void main() {
  late _FakeRpc rpc;
  late ModelService svc;
  late Map<String, dynamic> session;

  setUp(() {
    rpc = _FakeRpc();
    session = {'client': 'uuid-1', 'language': 'de', 'company': 1};
    svc = ModelService(
        rpc: rpc, getContext: () => session, getDatabase: () => 'tryton');
  });

  Map<String, dynamic> lastCtx() =>
      rpc.calls.last.$3.last as Map<String, dynamic>;

  group('execute', () {
    test('session context is appended as last parameter', () async {
      await svc.execute<List>('party.party', 'search', [[], 0, 10]);
      final (db, method, params) = rpc.calls.single;
      expect(db, 'tryton');
      expect(method, 'model.party.party.search');
      expect(params, [[], 0, 10, session]);
    });

    test('passed context overrides session context (session ⊕ context)',
        () async {
      await svc.execute<List>('party.party', 'read', [
        [1],
        ['name']
      ], context: {
        'language': 'en',
        'active_test': false
      });
      expect(lastCtx(), {
        'client': 'uuid-1',
        'language': 'en',
        'company': 1,
        'active_test': false,
      });
    });

    test('session context is not modified by the merge', () async {
      await svc.execute<List>('party.party', 'read', [[1], []],
          context: {'language': 'en'});
      expect(session['language'], 'de');
      expect(session.containsKey('active_test'), isFalse);
    });

    test('current session context is read on every call', () async {
      await svc.execute<List>('party.party', 'read', [[1], []]);
      session = {...session, 'language': 'fr'};
      await svc.execute<List>('party.party', 'read', [[1], []]);
      expect(lastCtx()['language'], 'fr');
    });

    test('mergeContext: null context → copy of session', () {
      final merged = ModelService.mergeContext(session, null);
      expect(merged, session);
      expect(identical(merged, session), isFalse);
    });
  });

  group('every ModelService call ends with exactly one context', () {
    test('CRUD and view methods', () async {
      rpc.result = <dynamic>[];
      await svc.searchRead('party.party', domain: [], fields: ['name']);
      await svc.read('party.party', [1], ['name']);
      rpc.result = [5];
      await svc.create('party.party', [{'name': 'X'}]);
      await svc.copy('party.party', [1]);
      rpc.result = true;
      await svc.write('party.party', [1], {'name': 'Y'});
      await svc.delete('party.party', [1]);
      rpc.result = <String, dynamic>{};
      await svc.defaultGet('party.party', ['name']);
      rpc.result = 0;
      await svc.searchCount('party.party');
      rpc.result = <dynamic>[];
      await svc.searchName('party.party', 'Ja');
      await svc.getSelectionOptions('party.party', 'get_x');
      await svc.executeReport('party.label', [1], 'party.party');

      for (final (_, method, params) in rpc.calls) {
        final ctx = params.last;
        expect(ctx, isA<Map<String, dynamic>>(), reason: method);
        expect((ctx as Map)['client'], 'uuid-1', reason: method);
        // No second context hidden in the parameters.
        expect(params.where((p) => p is Map && p['client'] != null),
            hasLength(1),
            reason: method);
      }
      expect(rpc.calls.last.$2, 'report.party.label.execute');
    });

    test('write with timestamp: _timestamp merged into session context',
        () async {
      rpc.result = true;
      await svc.write('party.party', [7], {'name': 'Y'}, timestamp: '12.5');
      expect(lastCtx(), {
        ...session,
        '_timestamp': {'party.party,7': '12.5'}
      });
      expect(rpc.calls.single.$3, hasLength(3));
    });
  });
}

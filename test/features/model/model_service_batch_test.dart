import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';

/// Answers `read`/`copy` with one entry per id, everything else with null.
class _FakeRpc extends RpcClient {
  _FakeRpc() : super(baseUrl: 'http://localhost');
  final calls = <(String, List<dynamic>)>[];
  @override
  Future<dynamic> call(String database, String method, List<dynamic> params,
      {bool reAuth = true}) async {
    calls.add((method, params));
    final ids = params.first;
    if (method.endsWith('.read') || method.endsWith('.copy')) {
      return [for (final id in ids as List) id];
    }
    return null;
  }
}

/// B8: id lists over 1000 go in batches (server `records_limit`).
void main() {
  late _FakeRpc rpc;
  late ModelService svc;
  final ids = [for (var i = 1; i <= 2500; i++) i];

  setUp(() {
    rpc = _FakeRpc();
    svc = ModelService(
        rpc: rpc, getContext: () => const {}, getDatabase: () => 'tryton');
  });

  List<int> batchSizes() =>
      [for (final (_, params) in rpc.calls) (params.first as List).length];

  test('read in batches, results joined in order', () async {
    final result =
        await svc.execute<List>('party.party', 'read', [ids, ['name']]);
    expect(batchSizes(), [1000, 1000, 500]);
    expect(result, ids);
    expect(rpc.calls.first.$2.sublist(1), [
      ['name'],
      {}
    ]);
  });

  test('write, delete, copy, export_data in batches', () async {
    await svc.execute('party.party', 'write', [ids, {'active': false}]);
    expect(batchSizes(), [1000, 1000, 500]);
    rpc.calls.clear();
    await svc.execute('party.party', 'delete', [ids]);
    expect(batchSizes(), [1000, 1000, 500]);
    rpc.calls.clear();
    expect(await svc.execute<List>('party.party', 'copy', [ids, {}]), ids);
    rpc.calls.clear();
    await svc.execute('party.party', 'export_data', [ids, ['name']]);
    expect(batchSizes(), [1000, 1000, 500]);
  });

  test('up to 1000 ids, other methods and multi-write in one call',
      () async {
    await svc.execute('party.party', 'read', [ids.sublist(0, 1000), []]);
    await svc.execute('party.party', 'search_count', [ids]);
    await svc.execute('party.party', 'write',
        [ids, {'active': false}, [1], {'active': true}]);
    expect(rpc.calls, hasLength(3));
  });
}

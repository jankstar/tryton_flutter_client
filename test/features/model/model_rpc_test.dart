import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';
import 'package:tryton_flutter_client/features/model/concurrency.dart';
import 'package:tryton_flutter_client/features/model/model_rpc.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';

class _FakeRpc extends RpcClient {
  _FakeRpc() : super(baseUrl: 'http://localhost');
  final calls = <(String, List<dynamic>)>[];
  @override
  Future<dynamic> call(String database, String method, List<dynamic> params,
      {bool reAuth = true}) async {
    calls.add((method, params));
    return [7];
  }
}

void main() {
  test('ModelServiceRpc: model.X.method with session ⊕ context', () async {
    final rpc = _FakeRpc();
    final svc = ModelService(
        rpc: rpc,
        getContext: () => {'language': 'de'},
        getDatabase: () => 'tryton');
    final session = modelSessionFor(svc);
    expect(session.context(), {'language': 'de'});
    final result = await session.rpc!.execute('party.party', 'search', [[]],
        context: {'active_test': false}, processException: false);
    expect(result, [7]);
    final (method, params) = rpc.calls.single;
    expect(method, 'model.party.party.search');
    expect(params, [
      [],
      {'language': 'de', 'active_test': false}
    ]);
  });

  group('concurrencyRunner (A1 flow)', () {
    Future<void> Function(bool) action(List<bool> log) => (withTimestamp) async {
          log.add(withTimestamp);
          if (withTimestamp) throw const ConcurrencyException();
        };

    test('write anyway → repeated without timestamp', () async {
      final log = <bool>[];
      final runner = concurrencyRunner(
        ask: () async => ConcurrencyChoice.writeAnyway,
        onCompare: (_, _) async => fail('no compare'),
        onMessage: () async => fail('no message'),
      );
      expect(await runner('sale.sale', [1], action(log)), isTrue);
      expect(log, [true, false]);
    });

    test('compare opens model/id and cancels', () async {
      final compared = <(String, int)>[];
      final runner = concurrencyRunner(
        ask: () async => ConcurrencyChoice.compare,
        onCompare: (model, id) async => compared.add((model, id)),
        onMessage: () async {},
      );
      expect(await runner('sale.sale', [5], action([])), isFalse);
      expect(compared, [('sale.sale', 5)]);
    });

    test('several records → message only', () async {
      var messages = 0;
      final runner = concurrencyRunner(
        ask: () async => fail('no question'),
        onCompare: (_, _) async {},
        onMessage: () async => messages++,
      );
      expect(await runner('sale.sale', [1, 2], action([])), isFalse);
      expect(messages, 1);
    });
  });
}

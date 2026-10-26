import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';
import 'package:tryton_flutter_client/features/model/concurrency.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';

/// Records every RPC call; throws [ConcurrencyException] for calls whose
/// context contains `_timestamp` while [conflict] is true.
class _FakeRpcClient extends RpcClient {
  _FakeRpcClient() : super(baseUrl: 'http://localhost');

  bool conflict = true;
  final calls = <(String, List<dynamic>)>[];

  @override
  Future<dynamic> call(
      String database, String method, List<dynamic> params) async {
    calls.add((method, params));
    final ctx = params.last as Map<String, dynamic>;
    if (conflict && ctx.containsKey('_timestamp')) {
      throw const ConcurrencyException();
    }
    return true;
  }
}

void main() {
  late _FakeRpcClient rpc;
  late ModelService svc;

  setUp(() {
    rpc = _FakeRpcClient();
    svc = ModelService(
      rpc: rpc,
      getContext: () => {'language': 'de'},
      getDatabase: () => 'tryton',
    );
  });

  Map<String, dynamic> ctxOf(int call) =>
      rpc.calls[call].$2.last as Map<String, dynamic>;

  group('ModelService.write / delete', () {
    test('write sends _timestamp per record and does NOT retry silently',
        () async {
      await expectLater(
        svc.write('party.party', [7], {'name': 'X'}, timestamp: '123.4'),
        throwsA(isA<ConcurrencyException>()),
      );
      expect(rpc.calls, hasLength(1));
      expect(rpc.calls.single.$1, 'model.party.party.write');
      expect(ctxOf(0)['_timestamp'], {'party.party,7': '123.4'});
      expect(ctxOf(0)['language'], 'de');
    });

    test('write without timestamp sends no _timestamp', () async {
      await svc.write('party.party', [7], {'name': 'X'});
      expect(ctxOf(0).containsKey('_timestamp'), isFalse);
    });

    test('delete sends _timestamp and propagates the conflict', () async {
      await expectLater(
        svc.delete('party.party', [7], timestamp: '1'),
        throwsA(isA<ConcurrencyException>()),
      );
      expect(rpc.calls.single.$1, 'model.party.party.delete');
      expect(ctxOf(0)['_timestamp'], {'party.party,7': '1'});
    });
  });

  group('runWithConcurrencyCheck', () {
    Future<bool> run(
      ConcurrencyChoice choice, {
      int idCount = 1,
      List<String>? log,
    }) {
      log ??= [];
      return runWithConcurrencyCheck(
        idCount: idCount,
        action: (withTimestamp) => svc.write('party.party', [7], {'name': 'X'},
            timestamp: withTimestamp ? '123.4' : null),
        ask: () async {
          log!.add('ask');
          return choice;
        },
        onCompare: () async => log!.add('compare'),
        onMessage: () async => log!.add('message'),
      );
    }

    test('no conflict → written once, no dialog', () async {
      rpc.conflict = false;
      final log = <String>[];
      expect(await run(ConcurrencyChoice.cancel, log: log), isTrue);
      expect(rpc.calls, hasLength(1));
      expect(log, isEmpty);
    });

    test('Cancel → not written again', () async {
      final log = <String>[];
      expect(await run(ConcurrencyChoice.cancel, log: log), isFalse);
      expect(log, ['ask']);
      expect(rpc.calls, hasLength(1));
    });

    test('Compare → opens server version, save aborted', () async {
      final log = <String>[];
      expect(await run(ConcurrencyChoice.compare, log: log), isFalse);
      expect(log, ['ask', 'compare']);
      expect(rpc.calls, hasLength(1));
    });

    test('Write Anyway → repeated without _timestamp', () async {
      final log = <String>[];
      expect(await run(ConcurrencyChoice.writeAnyway, log: log), isTrue);
      expect(log, ['ask']);
      expect(rpc.calls, hasLength(2));
      expect(ctxOf(0).containsKey('_timestamp'), isTrue);
      expect(ctxOf(1).containsKey('_timestamp'), isFalse);
      expect(rpc.calls[1].$2.take(2), [
        [7],
        {'name': 'X'}
      ]);
    });

    test('several records → simple message, no dialog, no retry', () async {
      final log = <String>[];
      expect(
          await run(ConcurrencyChoice.writeAnyway, idCount: 2, log: log),
          isFalse);
      expect(log, ['message']);
      expect(rpc.calls, hasLength(1));
    });

    test('other errors are not swallowed', () async {
      await expectLater(
        runWithConcurrencyCheck(
          idCount: 1,
          action: (_) async => throw const UserError('boom'),
          ask: () async => ConcurrencyChoice.writeAnyway,
          onCompare: () async {},
          onMessage: () async {},
        ),
        throwsA(isA<UserError>()),
      );
    });
  });
}

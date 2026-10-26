import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/reauth_service.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';

/// Answers each request with the next queued (status, body, headers).
class _FakeAdapter implements HttpClientAdapter {
  final List<(int, String, Map<String, List<String>>)> responses;
  int requests = 0;
  final paths = <String>[];
  _FakeAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final (status, body, headers) =
        responses[requests < responses.length ? requests : responses.length - 1];
    requests++;
    paths.add(options.uri.path);
    return ResponseBody.fromString(body, status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

const _html = '<!doctype html><html><body>Forbidden</body></html>';
const _htmlHeaders = {
  'content-type': ['text/html; charset=utf-8']
};
const _jsonHeaders = {
  'content-type': ['application/json']
};
String _ok(dynamic result) => jsonEncode({'id': 1, 'result': result});

void main() {
  late List<Duration> sleeps;

  (RpcClient, _FakeAdapter) client(
      List<(int, String, Map<String, List<String>>)> responses) {
    final adapter = _FakeAdapter(responses);
    final dio = Dio()..httpClientAdapter = adapter;
    sleeps = [];
    return (
      RpcClient(
        baseUrl: 'http://localhost:8000',
        dio: dio,
        sleep: (d) async => sleeps.add(d),
      ),
      adapter
    );
  }

  group('retryDelay (HTTP 503)', () {
    test('Retry-After in seconds', () {
      expect(RpcClient.retryDelay('3', 1), const Duration(seconds: 3));
      expect(RpcClient.retryDelay(' 7 ', 4), const Duration(seconds: 7));
    });
    test('without Retry-After: attempt number', () {
      expect(RpcClient.retryDelay(null, 1), const Duration(seconds: 1));
      expect(RpcClient.retryDelay(null, 4), const Duration(seconds: 4));
      expect(RpcClient.retryDelay('Wed, 21 Oct 2026 07:28:00 GMT', 2),
          const Duration(seconds: 2));
    });
    test('at most 10 s, never negative', () {
      expect(RpcClient.retryDelay('60', 1), const Duration(seconds: 10));
      expect(RpcClient.retryDelay(null, 12), const Duration(seconds: 10));
      expect(RpcClient.retryDelay('-5', 1), Duration.zero);
    });
  });

  group('HTTP 503 retries', () {
    test('5 attempts in total, then RpcHttpException(503)', () async {
      final (rpc, adapter) = client([(503, '', {})]);
      await expectLater(
        rpc.call('tryton', 'model.party.party.read', []),
        throwsA(isA<RpcHttpException>()
            .having((e) => e.statusCode, 'statusCode', 503)),
      );
      expect(adapter.requests, 5);
      expect(sleeps, [for (var i = 1; i <= 4; i++) Duration(seconds: i)]);
    });

    test('Retry-After is honoured and capped', () async {
      final (rpc, _) = client([
        (503, '', {'retry-after': ['2']}),
        (503, '', {'retry-after': ['30']}),
        (200, _ok(42), _jsonHeaders),
      ]);
      expect(await rpc.call('tryton', 'm', []), 42);
      expect(sleeps, const [Duration(seconds: 2), Duration(seconds: 10)]);
    });
  });

  group('non-JSON body', () {
    test('HTML with 403 → RpcHttpException(403)', () async {
      final (rpc, adapter) = client([(403, _html, _htmlHeaders)]);
      await expectLater(
        rpc.call('tryton', 'model.secret.method', []),
        throwsA(isA<RpcHttpException>()
            .having((e) => e.statusCode, 'statusCode', 403)),
      );
      expect(adapter.requests, 1);
    });

    test('HTML with 401 → re-login is asked; on failure RpcHttpException(401)',
        () async {
      final sub = ReAuthService.reAuthRequests
          .listen((_) => ReAuthService.fail());
      addTearDown(sub.cancel);
      final (rpc, _) = client([(401, _html, _htmlHeaders)]);
      await expectLater(
        rpc.call('tryton', 'm', []),
        throwsA(isA<RpcHttpException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
    });

    test('HTML with 200 → RpcProtocolException, not null', () async {
      final (rpc, _) = client([(200, _html, _htmlHeaders)]);
      await expectLater(rpc.call('tryton', 'm', []),
          throwsA(isA<RpcProtocolException>()));
    });

    test('HTML with 202 (2xx ≠ 200) → RpcHttpException', () async {
      final (rpc, _) = client([(202, _html, _htmlHeaders)]);
      await expectLater(
        rpc.call('tryton', 'm', []),
        throwsA(isA<RpcHttpException>()
            .having((e) => e.statusCode, 'statusCode', 202)),
      );
    });

    test('empty body stays null (logout)', () async {
      final (rpc, _) = client([(200, '', {})]);
      expect(await rpc.call('tryton', 'm', []), isNull);
    });

    test('JSON error tuple is still mapped', () async {
      final (rpc, _) = client([
        (
          200,
          jsonEncode({
            'id': 1,
            'error': ['ConcurrencyException', 'Records were modified']
          }),
          _jsonHeaders
        )
      ]);
      await expectLater(rpc.call('tryton', 'm', []),
          throwsA(isA<ConcurrencyException>()));
    });

    test('serverVersion uses the same handling', () async {
      final (rpc, _) = client([(403, _html, _htmlHeaders)]);
      await expectLater(
          rpc.serverVersion(), throwsA(isA<RpcHttpException>()));
    });
  });

  group('listDatabases (common.db.list)', () {
    test('is sent to /rpc/ without database', () async {
      final (rpc, adapter) =
          client([(200, _ok(['demo', 'tryton']), _jsonHeaders)]);
      expect(await rpc.listDatabases(), ['demo', 'tryton']);
      expect(adapter.paths, ['/rpc/']);
    });

    test('403 = list disabled → empty list (free-text field)', () async {
      final (rpc, _) = client([(403, _html, _htmlHeaders)]);
      expect(await rpc.listDatabases(), isEmpty);
    });

    test('other HTTP errors are reported', () async {
      final (rpc, _) = client([(500, _html, _htmlHeaders)]);
      await expectLater(rpc.listDatabases(),
          throwsA(isA<RpcHttpException>()
              .having((e) => e.statusCode, 'statusCode', 500)));
    });

    test('serverVersion also uses /rpc/', () async {
      final (rpc, adapter) = client([(200, _ok('8.0'), _jsonHeaders)]);
      expect(await rpc.serverVersion(), '8.0');
      expect(adapter.paths, ['/rpc/']);
    });
  });
}

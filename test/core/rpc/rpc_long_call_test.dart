import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';

/// Answers after [delay] (fake time) or, with [hold], when the request is
/// cancelled.
class _SlowAdapter implements HttpClientAdapter {
  final Duration delay;
  final bool hold;
  int requests = 0;
  _SlowAdapter({this.delay = Duration.zero, this.hold = false});

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests++;
    if (hold) {
      await cancelFuture;
      throw DioException.requestCancelled(
          requestOptions: options, reason: 'cancelled');
    }
    await Future<void>.delayed(delay);
    return ResponseBody.fromString(
        jsonEncode({'id': 1, 'result': 'done'}), 200, headers: {
      'content-type': ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Long server calls (spec T1, Python `jsonrpc.py`: CONNECT_TIMEOUT = 5,
/// no read timeout; no automatic repetition after a broken connection).
void main() {
  RpcClient client(HttpClientAdapter adapter) => RpcClient(
        baseUrl: 'http://localhost:8000',
        dio: Dio(RpcClient.defaultOptions())..httpClientAdapter = adapter,
      );

  group('timeouts', () {
    test('short connect timeout, no read timeout', () {
      final options = RpcClient.defaultOptions();
      expect(options.connectTimeout, const Duration(seconds: 10));
      expect(options.receiveTimeout, isNull);
      expect(options.sendTimeout, isNull);
    });

    // fake time of testWidgets: the 10 minutes pass at once
    testWidgets('an answer after 10 minutes is no error (module activation)',
        (tester) async {
      final rpc = client(_SlowAdapter(delay: const Duration(minutes: 10)));
      Object? result;
      Object? error;
      rpc
          .call('tryton', 'wizard.ir.module.activate_upgrade.execute', [])
          .then((r) => result = r, onError: (Object e) => error = e);
      await tester.pump(const Duration(seconds: 61));
      expect(result, isNull, reason: 'still waiting after 60 s');
      expect(error, isNull);
      expect(rpc.activity.waiting, isTrue);
      await tester.pump(const Duration(minutes: 10));
      await tester.pump();
      expect(error, isNull);
      expect(result, 'done');
      expect(rpc.activity.waiting, isFalse);
    });
  });

  group('error kinds', () {
    DioException dio(DioExceptionType type, [Object? error]) => DioException(
        requestOptions: RequestOptions(path: '/'), type: type, error: error);

    test('while connecting → server unreachable', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.connectionError,
        DioExceptionType.badCertificate,
      ]) {
        expect(RpcClient.networkError(dio(type)), isA<RpcConnectException>(),
            reason: '$type');
      }
      expect(
          RpcClient.networkError(dio(DioExceptionType.unknown,
              const HandshakeException('CERTIFICATE_VERIFY_FAILED'))),
          isA<RpcConnectException>());
    });

    test('closed by the server after sending → connection lost', () {
      expect(
          RpcClient.networkError(dio(
              DioExceptionType.connectionError,
              const HttpException(
                  'Connection closed before full header was received'))),
          isA<RpcConnectionLostException>());
      expect(
          RpcClient.networkError(dio(DioExceptionType.connectionError,
              const SocketException('Connection refused'))),
          isA<RpcConnectException>());
    });

    test('during the request → connection lost (result unknown)', () {
      for (final type in [
        DioExceptionType.receiveTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.unknown,
      ]) {
        expect(RpcClient.networkError(dio(type)),
            isA<RpcConnectionLostException>(),
            reason: '$type');
      }
    });

    test('stopped waiting → RpcWaitAbandonedException', () {
      expect(RpcClient.networkError(dio(DioExceptionType.cancel)),
          isA<RpcWaitAbandonedException>());
    });
  });

  group('waiting', () {
    test('Stop waiting ends the call with RpcWaitAbandonedException, '
        'nothing is sent again', () async {
      final adapter = _SlowAdapter(hold: true);
      final rpc = client(adapter);
      final call = rpc.call('tryton', 'model.party.party.write', []);
      while (adapter.requests == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(rpc.activity.waiting, isTrue);
      rpc.activity.abandon();
      await expectLater(call, throwsA(isA<RpcWaitAbandonedException>()));
      expect(adapter.requests, 1);
      expect(rpc.activity.running, isEmpty);
    });

    test('background calls (counters, completion) are not waited for', () async {
      final rpc = client(_SlowAdapter(hold: true));
      for (final method in [
        'model.party.party.search_count',
        'model.party.party.autocomplete',
        'model.res.notification.get_count',
        'model.ir.model.global_search',
        'model.ir.ui.icon.search_read',
      ]) {
        unawaited(rpc.call('tryton', method, []).catchError((_) => null));
      }
      await Future<void>.delayed(Duration.zero);
      expect(rpc.activity.running, hasLength(5));
      expect(rpc.activity.waiting, isFalse);
      rpc.activity.abandon();
      expect(rpc.activity.running, hasLength(5),
          reason: 'background calls are not stopped');
    });
  });
}

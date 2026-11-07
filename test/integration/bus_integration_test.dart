@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/bus_service.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';

/// Bus of the Tryton test server (spec 2.10, 11 „Bus“), read only: a poll
/// on a fresh client channel stays open without message (long polling).
///
///     TRYTON_PASSWORD=… flutter test --run-skipped -t integration
const _server = 'http://127.0.0.1:8000';
const _database = 'tryton';

void main() {
  final password = Platform.environment['TRYTON_PASSWORD'];

  test('poll 5 s without message: the request stays open, no error',
      () async {
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    final rpc = RpcClient(baseUrl: _server);
    final result = await rpc.call(_database, 'common.db.login', [
      'admin',
      {'password': password},
      'de'
    ], reAuth: false) as List;
    final auth = SessionAuth('admin', result[0] as int, result[1] as String);
    rpc.auth = auth;
    final busUrlHost = result.length > 2 ? result[2] as String? : null;
    expect(busUrlHost, isNotNull, reason: 'bus enabled on the test server');
    expect(busUrlHost, endsWith('/'));

    final bus = BusService();
    final messages = <Map<String, dynamic>>[];
    // a channel of its own: nobody sends there
    bus.register(
        'client:claude-test-${DateTime.now().microsecondsSinceEpoch}',
        messages.add);
    bus.start(host: busUrlHost, database: _database, auth: auth);
    try {
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(bus.running, isTrue);
      expect(bus.unsupported, isFalse);
      expect(bus.lastError, isNull);
      expect(messages, isEmpty);
      expect(bus.requests, 1, reason: 'one long poll, still open');
    } finally {
      bus.stop();
      try {
        await rpc.call(_database, 'common.db.logout', [], reAuth: false);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}

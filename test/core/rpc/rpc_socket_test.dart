import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';

/// Connection problems on real sockets (spec T1): unreachable vs. broken
/// while the server works; no automatic repetition. Own file: the fake
/// HTTP of `testWidgets` would answer every request with 400.
void main() {
  group('real sockets', () {
    test('nothing listening: server unreachable', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final rpc = RpcClient(baseUrl: 'http://127.0.0.1:$port');
      await expectLater(rpc.call('tryton', 'model.res.user.read', []),
          throwsA(isA<RpcConnectException>()));
    });

    test('connection dropped while processing: connection lost, the call '
        'is not sent again', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((client) {
        requests++;
        // the server reads the request and breaks off while "working"
        client.listen((_) => client.destroy());
      });
      addTearDown(server.close);
      final rpc = RpcClient(baseUrl: 'http://127.0.0.1:${server.port}');
      await expectLater(
          rpc.call('tryton', 'wizard.ir.module.activate_upgrade.execute',
              [1, {}, 'upgrade']),
          throwsA(isA<RpcConnectionLostException>()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(requests, 1, reason: 'no automatic repetition');
    });
  });
}

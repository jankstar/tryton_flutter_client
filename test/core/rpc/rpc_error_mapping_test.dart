import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';

void main() {
  group('RpcClient.exceptionFromError – ConcurrencyException', () {
    test('payload is a plain string (verified server format)', () {
      final e = RpcClient.exceptionFromError(
          ['ConcurrencyException', 'Records were modified in the meanwhile']);
      expect(e, isA<ConcurrencyException>());
      expect(e.message, 'Records were modified in the meanwhile');
    });

    test('missing payload falls back to default message', () {
      final e = RpcClient.exceptionFromError(['ConcurrencyException']);
      expect(e, isA<ConcurrencyException>());
      expect(e.message, isNotEmpty);
    });
  });
}

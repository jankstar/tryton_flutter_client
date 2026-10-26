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

  group('RpcClient.exceptionFromError – UserError domain', () {
    test('[domain, fields] list is stored in both parts', () {
      final e = RpcClient.exceptionFromError([
        'UserError',
        [
          'The value is not valid.',
          'Check the field "Code".',
          [
            [
              ['code', '!=', null]
            ],
            {
              'code': {'string': 'Code', 'type': 'char'}
            }
          ]
        ]
      ]) as UserError;
      expect(e.message, 'The value is not valid.');
      expect(e.description, 'Check the field "Code".');
      expect(e.domain, [
        ['code', '!=', null]
      ]);
      expect(e.domainFields, {
        'code': {'string': 'Code', 'type': 'char'}
      });
    });

    test('null domain', () {
      final e = RpcClient.exceptionFromError(
          ['UserError', ['msg', 'desc', null]]) as UserError;
      expect(e.domain, isNull);
      expect(e.domainFields, isNull);
    });

    test('without domain element', () {
      final e = RpcClient.exceptionFromError(['UserError', ['msg', 'desc']])
          as UserError;
      expect(e.description, 'desc');
      expect(e.domain, isNull);
    });

    test('a Map in the domain slot (old assumption) is ignored', () {
      final e = RpcClient.exceptionFromError([
        'UserError',
        ['msg', '', {'a': 1}]
      ]) as UserError;
      expect(e.domain, isNull);
      expect(e.domainFields, isNull);
    });
  });
}

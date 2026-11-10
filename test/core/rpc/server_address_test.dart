import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/server_address.dart';
import 'package:tryton_flutter_client/core/session/session_store.dart';

/// Server address of the login like the Python client: `host[:port]`
/// (port 8000), HTTPS before HTTP, the scheme remembered per host:port.
void main() {
  group('parse', () {
    test('without scheme: port 8000, both schemes to try', () {
      final a = ServerAddress.parse('localhost')!;
      expect(a.scheme, isNull);
      expect(a.hostPort, 'localhost:8000');
      expect(a.candidates, ['https://localhost:8000', 'http://localhost:8000']);
      expect(ServerAddress.parse(' erp.example.com:9000 ')!.candidates,
          ['https://erp.example.com:9000', 'http://erp.example.com:9000']);
      expect(ServerAddress.parse('[::1]:8000')!.hostPort, '[::1]:8000');
    });

    test('with scheme: as given, the default port of the scheme', () {
      expect(ServerAddress.parse('https://erp.example.com/tryton/')!.candidates,
          ['https://erp.example.com:443/tryton']);
      expect(ServerAddress.parse('http://localhost:8000')!.candidates,
          ['http://localhost:8000']);
    });

    test('empty or other schemes: null', () {
      expect(ServerAddress.parse(''), isNull);
      expect(ServerAddress.parse('ftp://host'), isNull);
    });
  });

  group('resolve', () {
    late Map<String, String> known;
    late List<String> probed;
    ServerResolver resolver() => ServerResolver(
        load: () async => {...known}, save: (k) async => known = {...k});
    Future<void> Function(String) server(Set<String> reachable) => (url) async {
          probed.add(url);
          if (!reachable.contains(url)) throw Exception('no connection');
        };

    setUp(() {
      known = {};
      probed = [];
    });

    test('HTTPS first, falls back to HTTP; the scheme is remembered', () async {
      final url = await resolver()
          .resolve('localhost:8000', server({'http://localhost:8000'}));
      expect(url, 'http://localhost:8000');
      expect(probed, ['https://localhost:8000', 'http://localhost:8000']);
      expect(known, {'localhost:8000': 'http'});

      probed.clear();
      expect(
          await resolver()
              .resolve('localhost', server({'http://localhost:8000'})),
          'http://localhost:8000');
      expect(probed, ['http://localhost:8000'], reason: 'remembered first');
    });

    test('HTTPS reachable: HTTPS', () async {
      expect(
          await resolver().resolve('erp.example.com',
              server({'https://erp.example.com:8000', 'http://erp.example.com:8000'})),
          'https://erp.example.com:8000');
      expect(known, {'erp.example.com:8000': 'https'});
    });

    test('the remembered scheme fails: the others are tried', () async {
      known = {'localhost:8000': 'http'};
      expect(
          await resolver()
              .resolve('localhost:8000', server({'https://localhost:8000'})),
          'https://localhost:8000');
      expect(probed, ['http://localhost:8000', 'https://localhost:8000']);
      expect(known, {'localhost:8000': 'https'});
    });

    test('with scheme: no probe; nothing reachable: the error', () async {
      expect(await resolver().resolve('https://h:1', server({})), 'https://h:1');
      expect(probed, isEmpty);
      await expectLater(
          resolver().resolve('nowhere', server({})), throwsException);
      expect(known, isEmpty);
    });
  });

  test('session key: the same with and without scheme', () {
    expect(sessionKey('admin', 'localhost:8000', 'tryton'),
        'admin@localhost:8000/tryton');
    expect(sessionKey('admin', 'http://localhost:8000', 'tryton'),
        sessionKey('admin', 'localhost', 'tryton'));
  });
}

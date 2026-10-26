import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/core/rpc/reauth_service.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';
import 'package:tryton_flutter_client/core/session/session.dart';
import 'package:tryton_flutter_client/core/session/session_store.dart';

class _MemoryStore implements SessionStore {
  StoredSession? value;
  @override
  Future<StoredSession?> read() async => value;
  @override
  Future<void> write(StoredSession session) async => value = session;
  @override
  Future<void> delete() async => value = null;
}

/// Recorded request: path, method, params, Authorization header.
typedef _Req = ({String path, String method, List params, String? auth});

/// Answers via [handler] with (status, json-or-html body).
class _Adapter implements HttpClientAdapter {
  final (int, Object) Function(_Req) handler;
  final requests = <_Req>[];
  _Adapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = jsonDecode(options.data as String) as Map<String, dynamic>;
    expect(body.keys.toSet(), {'id', 'method', 'params'},
        reason: 'JSON-RPC 1.0 style, no jsonrpc field');
    final req = (
      path: options.uri.path,
      method: body['method'] as String,
      params: body['params'] as List,
      auth: options.headers['Authorization'] as String?,
    );
    requests.add(req);
    final (status, out) = handler(req);
    return ResponseBody.fromString(
        out is String ? out : jsonEncode({'id': body['id'], 'result': out}),
        status,
        headers: {
          'content-type': [out is String ? 'text/html' : 'application/json']
        });
  }

  @override
  void close({bool force = false}) {}
}

String _sessionHeader(String login, int uid, String token) =>
    'Session ${base64.encode(utf8.encode('$login:$uid:$token'))}';

void main() {
  late _MemoryStore store;
  late int reAuthRequests;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _MemoryStore();
    reAuthRequests = 0;
    final sub = ReAuthService.reAuthRequests.listen((_) {
      reAuthRequests++;
      ReAuthService.fail();
    });
    addTearDown(sub.cancel);
  });

  (TrytonSession, _Adapter) make((int, Object) Function(_Req) handler) {
    final adapter = _Adapter(handler);
    final rpc = RpcClient(
      baseUrl: 'http://127.0.0.1:8000',
      dio: Dio()..httpClientAdapter = adapter,
      sleep: (_) async {},
    );
    return (TrytonSession(rpcClient: rpc, store: store), adapter);
  }

  (int, Object) server(_Req r) => switch (r.method) {
        'common.db.login' => (200, [1, 'tok123', null]),
        'model.res.user.device.renew' => (200, 'cookie-1'),
        'model.res.user.get_preferences' => (200, {'language': 'de'}),
        'common.db.logout' => (200, true),
        _ => (404, '<html>not found</html>'),
      };

  group('login (B3: session header)', () {
    test('login at <db>/rpc/, token used as Session header and stored',
        () async {
      final (session, adapter) = make(server);
      await session.loginWithParams('tryton', 'admin', {'password': 'pw'});

      final login = adapter.requests.first;
      expect(login.path, '/tryton/rpc/');
      expect(login.method, 'common.db.login');
      expect(login.params[0], 'admin');
      expect(login.auth, isNull);

      final header = _sessionHeader('admin', 1, 'tok123');
      expect(adapter.requests.skip(1).map((r) => r.auth), everyElement(header));
      expect(session.userId, 1);
      expect(session.context['language'], 'de');
      expect(store.value?.token, 'tok123');
      expect(store.value?.database, 'tryton');
      expect(store.value?.baseUrl, 'http://127.0.0.1:8000/');
    });

    test('password is never stored', () async {
      final (session, _) = make(server);
      await session.loginWithParams('tryton', 'admin', {'password': 'geheim'});
      expect(jsonEncode(store.value!.toJson()), isNot(contains('geheim')));
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys()) {
        expect('${prefs.get(k)}', isNot(contains('geheim')));
      }
    });

    test('wrong password (401 HTML) → error, no re-login dialog', () async {
      final (session, _) = make((r) => r.method == 'common.db.login'
          ? (401, '<html>Unauthorized</html>')
          : server(r));
      await expectLater(
          session.loginWithParams('tryton', 'admin', {'password': 'x'}),
          throwsA(isA<RpcHttpException>()
              .having((e) => e.statusCode, 'statusCode', 401)));
      expect(reAuthRequests, 0);
      expect(store.value, isNull);
    });

    test('device cookie alone → LoginException(password) (verified A8)',
        () async {
      SharedPreferences.setMockInitialValues({
        'tryton_device_cookies': jsonEncode({
          'tryton': {'admin': 'cookie-1'}
        })
      });
      final rpc = RpcClient(
        baseUrl: 'http://127.0.0.1:8000',
        dio: Dio()
          ..httpClientAdapter = _ErrorAdapter([
            'LoginException',
            ['password', 'Passwort für admin', 'password']
          ]),
      );
      final session = TrytonSession(rpcClient: rpc, store: store);
      await expectLater(
          session.loginWithParams('tryton', 'admin', {}),
          throwsA(isA<LoginException>()
              .having((e) => e.fieldName, 'fieldName', 'password')
              .having((e) => e.fieldType, 'fieldType', 'password')));
      expect(session.isLoggedIn, isFalse);
      expect(store.value, isNull);
    });
  });

  group('restore (A8: stored token)', () {
    const stored = StoredSession(
      baseUrl: 'http://127.0.0.1:8000/',
      database: 'tryton',
      login: 'admin',
      userId: 1,
      token: 'tok123',
    );

    test('valid token → logged in without password', () async {
      store.value = stored;
      final (session, adapter) = make(server);
      expect(await session.restore(), isTrue);
      expect(session.isLoggedIn, isTrue);
      expect(session.database, 'tryton');
      expect(session.context['language'], 'de');
      final check = adapter.requests.single;
      expect(check.method, 'model.res.user.get_preferences');
      expect(check.auth, _sessionHeader('admin', 1, 'tok123'));
      expect(adapter.requests.any((r) => r.method == 'common.db.login'),
          isFalse);
    });

    test('expired token (401) → deleted, no re-login dialog', () async {
      store.value = stored;
      final (session, _) = make((_) => (401, '<html>Unauthorized</html>'));
      expect(await session.restore(), isFalse);
      expect(store.value, isNull);
      expect(session.isLoggedIn, isFalse);
      expect(session.rpcClient.auth, isNull);
      expect(reAuthRequests, 0);
    });

    test('server error (500) → not logged in, token kept', () async {
      store.value = stored;
      final (session, _) = make((_) => (500, '<html>error</html>'));
      expect(await session.restore(), isFalse);
      expect(store.value, isNotNull);
      expect(session.isLoggedIn, isFalse);
    });

    test('nothing stored → false without request', () async {
      final (session, adapter) = make(server);
      expect(await session.restore(), isFalse);
      expect(adapter.requests, isEmpty);
    });

    test('legacy shared_preferences session entry is removed', () async {
      SharedPreferences.setMockInitialValues({'tryton_session': '{}'});
      final (session, _) = make(server);
      await session.restore();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('tryton_session'), isFalse);
    });
  });

  test('logout → common.db.logout with header, token deleted', () async {
    final (session, adapter) = make(server);
    await session.loginWithParams('tryton', 'admin', {'password': 'pw'});
    await session.logout();
    final logout = adapter.requests.last;
    expect(logout.method, 'common.db.logout');
    expect(logout.auth, _sessionHeader('admin', 1, 'tok123'));
    expect(store.value, isNull);
    expect(session.rpcClient.auth, isNull);
    expect(session.isLoggedIn, isFalse);
  });

  test('logout errors are ignored', () async {
    final (session, _) = make(
        (r) => r.method == 'common.db.logout' ? (500, '<html/>') : server(r));
    await session.loginWithParams('tryton', 'admin', {'password': 'pw'});
    await session.logout();
    expect(store.value, isNull);
  });

  group('StoredSession.fromJson', () {
    test('round trip', () {
      const s = StoredSession(
          baseUrl: 'u', database: 'd', login: 'l', userId: 2, token: 't');
      final back = StoredSession.fromJson(s.toJson())!;
      expect(back.toJson(), s.toJson());
    });
    test('incomplete → null', () {
      expect(StoredSession.fromJson({'base_url': 'u', 'database': 'd'}),
          isNull);
      expect(
          StoredSession.fromJson({
            'base_url': 'u',
            'database': 'd',
            'login': 'l',
            'user_id': 1,
            'token': ''
          }),
          isNull);
    });
  });
}

/// Always answers with the given JSON-RPC error tuple.
class _ErrorAdapter implements HttpClientAdapter {
  final List error;
  _ErrorAdapter(this.error);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode({'id': 1, 'error': error}), 200,
          headers: {
            'content-type': ['application/json']
          });
  @override
  void close({bool force = false}) {}
}

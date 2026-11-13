import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/app.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';
import 'package:tryton_flutter_client/core/rpc/server_address.dart';
import 'package:tryton_flutter_client/core/session/profiles.dart' show demoLogin;
import 'package:tryton_flutter_client/core/session/session.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/auth/login_errors.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

/// A server answering `common.db.*` like trytond 8.0: a wrong password is
/// HTTP 401 (HTML body), a missing one `LoginException(password)`.
class _Server extends RpcClient {
  final calls = <(String, String, List<dynamic>)>[];
  Object? resetError;

  _Server() : super(baseUrl: 'http://localhost:8000/');

  @override
  Future<String> serverVersion() async => '$kClientVersion.0';

  @override
  Future<List<String>> listDatabases() async => ['tryton'];

  @override
  Future<dynamic> call(String database, String method, List<dynamic> params,
      {bool reAuth = true}) async {
    calls.add((database, method, params));
    if (method == 'common.db.reset_password') {
      if (resetError != null) throw resetError!;
      return null;
    }
    if (method == 'common.db.login') {
      final parameters = params[1] as Map;
      if (!parameters.containsKey('password')) {
        throw const LoginException('password', 'Password for admin',
            fieldType: 'password');
      }
      throw const RpcHttpException(401, 'Unauthorized');
    }
    throw UnimplementedError(method);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  final de = lookupAppLocalizations(const Locale('de'));

  test('error codes and their messages (Python common.Login)', () {
    String text(Object e) => localizeLoginError(loginErrorCode(e), de);
    expect(text(const RpcHttpException(401, '<html>')),
        'Falscher Benutzername oder falsches Passwort.');
    expect(text(const RpcHttpException(429, '')),
        'Zu viele Anfragen. Bitte versuchen Sie es später erneut.');
    expect(text(const RpcHttpException(404, '')), 'Datenbank nicht gefunden.');
    expect(text(const RpcHttpException(403, '')), 'Der Server lässt das nicht zu.');
    expect(text(const RpcHttpException(502, 'Bad: Gateway')),
        de.httpError(502, 'Bad: Gateway'));
    expect(text(const RpcNetworkException('timeout')), de.networkError('timeout'));
    expect(localizeLoginError('version_mismatch:7.0:8.0', de),
        de.versionMismatch('7.0', '8.0'));
  });

  AuthState stateOf(AuthNotifier auth) {
    late AuthState state;
    auth.addListener((s) => state = s)();
    return state;
  }

  AuthNotifier notifier(_Server server) => AuthNotifier(
      TrytonSession(rpcClient: server), server,
      resolver: ServerResolver(load: () async => {}, save: (_) async {}));

  test('a wrong password: a message code, the login in the screen language',
      () async {
    final server = _Server();
    final auth = notifier(server);
    await auth.login('http://localhost:8000', 'tryton', 'admin', 'wrong',
        language: 'fr');
    expect(stateOf(auth).errorMessage, 'login_failed');
    final login = server.calls.singleWhere((c) => c.$2 == 'common.db.login');
    expect(login.$3[0], 'admin');
    expect(login.$3[2], 'fr', reason: 'the language of the login screen');
  });

  test('a wrong password after the password prompt: back to the form',
      () async {
    final server = _Server();
    final auth = notifier(server);
    await auth.login('http://localhost:8000', 'tryton', 'admin', '');
    // (an empty map: LoginException(password) – simulated by the test)
    await auth.submitMfaResponse('password', 'wrong');
    expect(stateOf(auth).errorMessage, 'login_failed');
    expect(stateOf(auth).needsMfa, isFalse);
  });

  test('reset password: common.db.reset_password(login, language)', () async {
    final server = _Server();
    await notifier(server).resetPassword(
        'http://localhost:8000', 'tryton', 'admin',
        language: 'de');
    final (db, method, params) = server.calls.single;
    expect((db, method), ('tryton', 'common.db.reset_password'));
    expect(params, ['admin', 'de']);
  });

  testWidgets('login screen: the reset link sends the request and confirms '
      'it', (tester) async {
    final server = _Server();
    await tester.pumpWidget(ProviderScope(
      overrides: [rpcClientProvider.overrideWithValue(server)],
      child: const TrytonFlutterClientApp(),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('login-reset-password')));
    await tester.tap(find.byKey(const ValueKey('login-reset-password')));
    await tester.pumpAndSettle();
    final reset =
        server.calls.where((c) => c.$2 == 'common.db.reset_password').single;
    expect(reset.$3, [demoLogin, 'en']);
    expect(find.textContaining('A request to reset your password'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dialog-ok')));
    await tester.pumpAndSettle();

    server.resetError = const RpcHttpException(429, 'Too Many Requests');
    await tester.tap(find.byKey(const ValueKey('login-reset-password')));
    await tester.pumpAndSettle();
    expect(find.text('Too many requests. Try again later.'), findsOneWidget);
  });

  testWidgets('login screen: a wrong password shows the message, not the '
      'exception', (tester) async {
    final server = _Server();
    await tester.pumpWidget(ProviderScope(
      overrides: [rpcClientProvider.overrideWithValue(server)],
      child: const TrytonFlutterClientApp(),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong user name or password.'), findsOneWidget);
    expect(find.textContaining('RpcHttpException'), findsNothing);
  });
}

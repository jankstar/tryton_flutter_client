import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/rpc_client.dart';
import '../../core/rpc/server_address.dart';
import '../../core/rpc/rpc_exceptions.dart';
import '../../core/session/profiles.dart' show demoServer;
import '../../core/session/session.dart';
import '../views/embedded_tree_widget.dart' show clearEmbeddedViewCache;
import 'login_errors.dart';

/// Singleton RpcClient – URL is set during login
final rpcClientProvider = Provider<RpcClient>((ref) {
  // the server of the login screen replaces it (no local default)
  return RpcClient(baseUrl: 'https://$demoServer');
});

final sessionProvider = Provider<TrytonSession>((ref) {
  return TrytonSession(rpcClient: ref.read(rpcClientProvider));
});

// ─── Auth state ───────────────────────────────────────────────────────────────

enum AuthStatus { unauthenticated, loading, authenticated, error }

class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  final List<String> databases;
  final String? pendingMfaField;
  final String? pendingMfaMessage;
  final String? pendingMfaType;

  /// URL of the server reached last (with the scheme found for an
  /// address without one): HTTPS or plain HTTP in the login screen.
  final String? serverUrl;

  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.errorMessage,
    this.databases = const [],
    this.pendingMfaField,
    this.pendingMfaMessage,
    this.pendingMfaType,
    this.serverUrl,
  });

  bool get needsMfa => pendingMfaField != null;

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    List<String>? databases,
    String? pendingMfaField,
    String? pendingMfaMessage,
    String? pendingMfaType,
    String? serverUrl,
  }) =>
      AuthState(
        status: status ?? this.status,
        errorMessage: errorMessage,
        databases: databases ?? this.databases,
        pendingMfaField: pendingMfaField,
        pendingMfaMessage: pendingMfaMessage,
        pendingMfaType: pendingMfaType,
        serverUrl: serverUrl ?? this.serverUrl,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final TrytonSession _session;
  final RpcClient _rpc;

  /// Address of the next login, resolved in [_doLogin] (errors shown).
  String? _pendingServer;
  String? _pendingDb;
  String? _pendingUsername;
  String _pendingLanguage = 'en';
  Map<String, dynamic> _pendingParams = {};

  AuthNotifier(this._session, this._rpc, {ServerResolver? resolver})
      : _resolver = resolver ?? ServerResolver(),
        super(const AuthState());

  final ServerResolver _resolver;

  /// The URL of the address [input] (`host[:port]` without scheme: HTTPS,
  /// else HTTP, like the Python client) set on the RPC client.
  Future<String> _useServer(String input) async {
    final url = await _resolver.resolve(input, (url) async {
      _rpc.baseUrl = url;
      await _rpc.serverVersion();
    });
    _rpc.baseUrl = url;
    state = state.copyWith(status: state.status, serverUrl: url);
    return url;
  }

  /// Loads the database list. An empty list (disabled on the server, 403)
  /// makes the login screen show a free-text database field.
  Future<void> loadDatabases(String serverUrl) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      await _useServer(serverUrl);
      // Version check first – like SAO does before showing the login dialog.
      await _session.checkCompatibility();
      final dbs = await _session.listDatabases();
      state = state.copyWith(status: AuthStatus.unauthenticated, databases: dbs);
    } on VersionMismatchException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'version_mismatch:${e.serverVersion}:${e.clientVersion}',
      );
    } catch (e) {
      // Like SAO: on error fall back to the free-text field.
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
        databases: const [],
      );
    }
  }

  /// Resumes the session stored in secure storage (task A8). On success
  /// the state becomes authenticated (login screen navigates to the app);
  /// otherwise the login screen stays, pre-filled by the caller.
  Future<bool> tryRestore([String? key]) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    final ok = await _session.restore(key);
    state = state.copyWith(
        status: ok ? AuthStatus.authenticated : AuthStatus.unauthenticated);
    return ok;
  }

  Future<void> login(
    String serverUrl,
    String db,
    String username,
    String password, {
    String language = 'en',
  }) async {
    _pendingServer = serverUrl;
    _pendingDb = db;
    _pendingUsername = username;
    _pendingLanguage = language;
    _pendingParams = {'password': password};
    await _doLogin();
  }

  /// Sends [username] an email to reset the password
  /// (`common.db.reset_password`); errors are thrown (codes via
  /// [loginErrorCode]).
  Future<void> resetPassword(String serverUrl, String db, String username,
      {String language = 'en'}) async {
    await _useServer(serverUrl);
    await _session.resetPassword(db, username, language: language);
  }

  Future<void> submitMfaResponse(String fieldName, String value) async {
    _pendingParams[fieldName] = value;
    await _doLogin();
  }

  Future<void> _doLogin() async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      final server = _pendingServer;
      if (server != null) {
        await _useServer(server);
        _pendingServer = null;
      }
      // Always re-check version before login in case loadDatabases was skipped.
      await _session.checkCompatibility();
      await _session.loginWithParams(
          _pendingDb!, _pendingUsername!, _pendingParams,
          language: _pendingLanguage);
      state = state.copyWith(status: AuthStatus.authenticated);
    } on VersionMismatchException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'version_mismatch:${e.serverVersion}:${e.clientVersion}',
      );
    } on LoginException catch (e) {
      if (e.fieldName.isNotEmpty) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          pendingMfaField: e.fieldName,
          pendingMfaMessage: e.message,
          pendingMfaType: e.fieldType,
        );
      } else {
        state = state.copyWith(
          status: AuthStatus.error,
          errorMessage: e.message,
        );
      }
    } catch (e) {
      // wrong credentials (401): the parameters start again, like the
      // Python client (`common.Login`) – the password form shows again
      _pendingParams = {};
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: loginErrorCode(e),
      );
    }
  }

  /// Re-authenticates with the stored login and a new password.
  /// Called from the compact re-login dialog when the session expires (401).
  /// Throws on failure so the dialog can show the error.
  Future<void> reAuthenticate(String password, {String? language}) async {
    final login = _session.login;
    final database = _session.database;
    if (login == null || database == null) {
      throw Exception('No active session to re-authenticate');
    }
    await _session.loginWithParams(
      database,
      login,
      {'password': password},
      language: language ?? _pendingLanguage,
    );
  }

  /// Sends the user of the current session an email to reset the
  /// password (re-login dialog).
  Future<void> resetSessionPassword({String? language}) async {
    final login = _session.login;
    final database = _session.database;
    if (login == null || database == null) return;
    await _session.resetPassword(database, login,
        language: language ?? _pendingLanguage);
    // Session renewed – auth state stays authenticated
  }

  Future<void> logout() async {
    clearEmbeddedViewCache();
    await _session.logout();
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.read(sessionProvider),
    ref.read(rpcClientProvider),
  );
});

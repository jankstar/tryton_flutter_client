import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rpc/rpc_client.dart';
import '../../core/rpc/rpc_exceptions.dart';
import '../../core/session/session.dart';
import 'user_preferences_provider.dart' show clearUserPreferencesCache;

/// Singleton RpcClient – URL is set during login
final rpcClientProvider = Provider<RpcClient>((ref) {
  return RpcClient(baseUrl: 'http://localhost:8000');
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

  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.errorMessage,
    this.databases = const [],
    this.pendingMfaField,
    this.pendingMfaMessage,
    this.pendingMfaType,
  });

  bool get needsMfa => pendingMfaField != null;

  AuthState copyWith({
    AuthStatus? status,
    String? errorMessage,
    List<String>? databases,
    String? pendingMfaField,
    String? pendingMfaMessage,
    String? pendingMfaType,
  }) =>
      AuthState(
        status: status ?? this.status,
        errorMessage: errorMessage,
        databases: databases ?? this.databases,
        pendingMfaField: pendingMfaField,
        pendingMfaMessage: pendingMfaMessage,
        pendingMfaType: pendingMfaType,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final TrytonSession _session;
  final RpcClient _rpc;

  String? _pendingDb;
  String? _pendingUsername;
  Map<String, dynamic> _pendingParams = {};

  AuthNotifier(this._session, this._rpc) : super(const AuthState());

  Future<void> loadDatabases(String serverUrl, String dbHint) async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      _rpc.baseUrl = serverUrl;
      // Version check first – like SAO does before showing the login dialog.
      await _session.checkCompatibility();
      final dbs = await _session.listDatabases(dbHint);
      state = state.copyWith(status: AuthStatus.unauthenticated, databases: dbs);
    } on VersionMismatchException catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: 'version_mismatch:${e.serverVersion}:${e.clientVersion}',
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> login(
    String serverUrl,
    String db,
    String username,
    String password,
  ) async {
    _rpc.baseUrl = serverUrl;
    _pendingDb = db;
    _pendingUsername = username;
    _pendingParams = {'password': password};
    await _doLogin();
  }

  Future<void> submitMfaResponse(String fieldName, String value) async {
    _pendingParams[fieldName] = value;
    await _doLogin();
  }

  Future<void> _doLogin() async {
    state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
    try {
      // Always re-check version before login in case loadDatabases was skipped.
      await _session.checkCompatibility();
      await _session.loginWithParams(_pendingDb!, _pendingUsername!, _pendingParams);
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
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Re-authenticates with the stored login and a new password.
  /// Called from the compact re-login dialog when the session expires (401).
  /// Throws on failure so the dialog can show the error.
  Future<void> reAuthenticate(String password) async {
    final login = _session.login;
    final database = _session.database;
    if (login == null || database == null) {
      throw Exception('No active session to re-authenticate');
    }
    await _session.loginWithParams(
      database,
      login,
      {'password': password},
    );
    // Session renewed – auth state stays authenticated
  }

  Future<void> logout() async {
    clearUserPreferencesCache();
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

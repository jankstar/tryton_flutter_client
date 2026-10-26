import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Data needed to resume a session on app start (spec 2.5, task A8).
class StoredSession {
  final String baseUrl;
  final String database;
  final String login;
  final int userId;
  final String token;
  final String? busUrlHost;

  const StoredSession({
    required this.baseUrl,
    required this.database,
    required this.login,
    required this.userId,
    required this.token,
    this.busUrlHost,
  });

  Map<String, dynamic> toJson() => {
        'base_url': baseUrl,
        'database': database,
        'login': login,
        'user_id': userId,
        'token': token,
        'bus_url_host': busUrlHost,
      };

  /// Returns null for incomplete or malformed data.
  static StoredSession? fromJson(Map<String, dynamic> j) {
    final baseUrl = j['base_url'], db = j['database'], login = j['login'];
    final uid = j['user_id'], token = j['token'];
    if (baseUrl is! String || db is! String || login is! String ||
        uid is! int || token is! String || token.isEmpty) {
      return null;
    }
    return StoredSession(
      baseUrl: baseUrl,
      database: db,
      login: login,
      userId: uid,
      token: token,
      busUrlHost: j['bus_url_host'] as String?,
    );
  }
}

/// Persists the session token. Must be secure storage – the token grants
/// full access as the user until it expires (`[session] max_age`).
abstract class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> delete();
}

/// [SessionStore] in the OS keychain/keystore via flutter_secure_storage.
class SecureSessionStore implements SessionStore {
  static const _key = 'tryton_session_v1';

  // macOS: legacy keychain → no `keychain-access-groups` entitlement and no
  // provisioning profile needed (see flutter_secure_storage README).
  final FlutterSecureStorage _storage;
  SecureSessionStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  @override
  Future<StoredSession?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return StoredSession.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      // Unreadable/corrupt entry → treat as no session.
      return null;
    }
  }

  @override
  Future<void> write(StoredSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
  }
}

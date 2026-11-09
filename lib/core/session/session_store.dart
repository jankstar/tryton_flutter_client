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

  /// `login@host:port/database` – one stored session per profile, like
  /// the device cookies (spec 2.5.3, H6).
  String get key => sessionKey(login, baseUrl, database);

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

/// `login@host:port/database` (the key of sessions and device cookies).
String sessionKey(String login, String baseUrl, String database) {
  final uri = Uri.parse(baseUrl);
  return '$login@${uri.host}:${uri.port}/$database';
}

/// Persists the session tokens, one per [StoredSession.key]. Must be
/// secure storage – a token grants full access as the user until it
/// expires (`[session] max_age`).
abstract class SessionStore {
  /// The session of [key]; without key the one written last.
  Future<StoredSession?> read([String? key]);
  Future<void> write(StoredSession session);

  /// Removes the session of [key] (without key: the one written last).
  Future<void> delete([String? key]);
}

/// [SessionStore] in the OS keychain/keystore via flutter_secure_storage:
/// `tryton_session_v2/<key>` per session and `tryton_session_last` (the
/// key written last). The single session of `tryton_session_v1` is moved
/// to its key on the first read.
class SecureSessionStore implements SessionStore {
  static const _legacyKey = 'tryton_session_v1';
  static const _prefix = 'tryton_session_v2/';
  static const _lastKey = 'tryton_session_last';

  // macOS: legacy keychain → no `keychain-access-groups` entitlement and no
  // provisioning profile needed (see flutter_secure_storage README).
  final FlutterSecureStorage _storage;
  SecureSessionStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            );

  StoredSession? _decode(String? raw) {
    if (raw == null) return null;
    try {
      return StoredSession.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      // Unreadable/corrupt entry → treat as no session.
      return null;
    }
  }

  /// Moves the session of the former single entry to its key.
  Future<void> _migrate() async {
    final legacy = _decode(await _storage.read(key: _legacyKey));
    if (legacy != null) await write(legacy);
    await _storage.delete(key: _legacyKey);
  }

  @override
  Future<StoredSession?> read([String? key]) async {
    try {
      await _migrate();
      key ??= await _storage.read(key: _lastKey);
      if (key == null) return null;
      return _decode(await _storage.read(key: '$_prefix$key'));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(StoredSession session) async {
    await _storage.write(
        key: '$_prefix${session.key}', value: jsonEncode(session.toJson()));
    await _storage.write(key: _lastKey, value: session.key);
  }

  @override
  Future<void> delete([String? key]) async {
    try {
      key ??= await _storage.read(key: _lastKey);
      if (key == null) return;
      await _storage.delete(key: '$_prefix$key');
    } catch (_) {}
  }
}

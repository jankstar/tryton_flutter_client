import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../rpc/rpc_client.dart';
import '../rpc/rpc_exceptions.dart';

/// The Tryton major.minor version this client was built against.
/// Only major.minor is compared (patch is ignored), identical to SAO.
const kClientVersion = '8.0';

const _deviceCookieKey = 'tryton_device_cookies';
const _sessionKey = 'tryton_session';

class TrytonSession {
  final RpcClient rpcClient;
  String? database;
  String? login;
  int? userId;
  String? busUrlHost;
  late final String clientId;
  Map<String, dynamic> context = {};

  TrytonSession({required this.rpcClient}) {
    clientId = const Uuid().v4();
    context = {'client': clientId};
  }

  bool get isLoggedIn => userId != null && userId! > 0;

  /// Returns the available databases for the configured server.
  Future<List<String>> listDatabases(String dbName) async {
    final result = await rpcClient.call(dbName, 'common.db.list', []);
    if (result is List) return result.cast<String>();
    return [];
  }

  /// Checks that the server's major.minor version matches [kClientVersion].
  /// Throws [VersionMismatchException] if incompatible – identical to SAO's check.
  Future<void> checkCompatibility() async {
    final raw = await rpcClient.serverVersion();
    final serverMajorMinor = raw.split('.').take(2).join('.');
    if (serverMajorMinor != kClientVersion) {
      throw VersionMismatchException(serverMajorMinor, kClientVersion);
    }
  }

  /// Performs the login. On MFA the method throws [LoginException];
  /// the caller must prompt for the additional field and call [loginWithParams] again.
  Future<void> loginWithParams(
    String db,
    String username,
    Map<String, dynamic> parameters, {
    String language = 'de',
  }) async {
    final deviceCookie = await _loadDeviceCookie(db, username);
    if (deviceCookie != null) parameters['device_cookie'] = deviceCookie;

    final result = await rpcClient.sessionPost(db, 'login', {
      'id': 0,
      'method': 'common.db.login',
      'params': [username, parameters, language],
    });

    // Successful login: [user_id, bus_url_host]
    if (result is List && result.length >= 2 && result[0] is int && result[0] > 0) {
      database = db;
      login = username;
      userId = result[0] as int;
      busUrlHost = result[1]?.toString();
      context = {'client': clientId};
      await _renewDeviceCookie(db, username);
      // Load user preferences into context so every subsequent RPC gets the
      // correct language (like SAO's reload_context / session.context.language).
      await reloadContext();
      await _storeSession(); // persist for next app start
      return;
    }

    // false or null = failed without exception
    throw const LoginException('', 'Login failed');
  }

  Future<void> logout() async {
    if (database == null) return;
    try {
      await rpcClient.sessionPost(database!, 'logout', {});
    } finally {
      await _clearStoredSession();
      database = null;
      login = null;
      userId = null;
      busUrlHost = null;
      context = {'client': clientId};
      await rpcClient.clearCookies();
    }
  }

  // ─── Context reload (like SAO's reload_context) ──────────────────────────

  /// Calls get_preferences(context_only=true) and merges the result into
  /// session.context so every subsequent RPC carries language, employee, etc.
  /// Mirrors SAO's Session.reload_context().
  Future<void> reloadContext() async {
    if (database == null) return;
    try {
      final prefs = await rpcClient.call(
        database!,
        'model.res.user.get_preferences',
        [true, context],
      );
      if (prefs is Map<String, dynamic>) {
        // Drop locale sub-object and rec_name keys (same filter as SAO)
        prefs.removeWhere((k, _) => k == 'locale' || k.endsWith('.rec_name'));
        context.addAll(prefs);
      }
    } catch (_) {
      // Non-critical: context may stay minimal; server falls back to English.
    }
  }

  // ─── Session persistence (like SAO's localStorage) ────────────────────────

  /// Saves session data so the app can reconnect on next start without login.
  Future<void> _storeSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode({
      'database': database,
      'login': login,
      'user_id': userId,
      'base_url': rpcClient.baseUrl,
    }));
  }

  Future<void> _clearStoredSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  /// Tries to restore a previous session using the device cookie.
  /// Returns true if successful (no login needed), false otherwise.
  static Future<bool> tryRestore(RpcClient rpcClient) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionKey);
      if (raw == null) return false;

      final data = jsonDecode(raw) as Map<String, dynamic>;
      final db = data['database'] as String?;
      final username = data['login'] as String?;
      final baseUrl = data['base_url'] as String?;

      if (db == null || username == null || baseUrl == null) return false;

      // Restore server URL
      rpcClient.baseUrl = baseUrl;

      // Try login with device cookie (no password needed)
      final session = TrytonSession(rpcClient: rpcClient);
      session.database = db;
      session.login = username;

      final cookies = await session._loadAllDeviceCookies();
      final deviceCookie = cookies[db]?[username] as String?;
      if (deviceCookie == null) return false;

      final params = <String, dynamic>{'device_cookie': deviceCookie};
      try {
        await session.loginWithParams(db, username, params);
        // loginWithParams already calls reloadContext() on success.
        return true;
      } catch (_) {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// Renews the device cookie for passwordless device recognition.
  Future<void> _renewDeviceCookie(String db, String username) async {
    try {
      final cookies = await _loadAllDeviceCookies();
      final existing = cookies[db]?[username] as String?;
      final newCookie = await rpcClient.call(
        db,
        'model.res.user.device.renew',
        [existing, context],
      );
      if (newCookie is String) {
        cookies.putIfAbsent(db, () => {})[username] = newCookie;
        await _saveAllDeviceCookies(cookies);
      }
    } catch (_) {
      // Device cookie is optional – ignore errors
    }
  }

  Future<String?> _loadDeviceCookie(String db, String username) async {
    final cookies = await _loadAllDeviceCookies();
    return cookies[db]?[username] as String?;
  }

  Future<Map<String, dynamic>> _loadAllDeviceCookies() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deviceCookieKey);
    if (raw == null) return {};
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> _saveAllDeviceCookies(Map<String, dynamic> cookies) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceCookieKey, jsonEncode(cookies));
  }
}

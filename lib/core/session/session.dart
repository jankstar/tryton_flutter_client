import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../rpc/rpc_client.dart';
import '../rpc/rpc_exceptions.dart';
import 'session_store.dart';

/// The Tryton major.minor version this client was built against.
/// Only major.minor is compared (patch is ignored), identical to SAO.
const kClientVersion = '8.0';

const _deviceCookieKey = 'tryton_device_cookies';
/// Former non-secret session info in shared_preferences (removed on start).
const _legacySessionKey = 'tryton_session';

class TrytonSession {
  final RpcClient rpcClient;
  final SessionStore _store;
  String? database;
  String? login;
  int? userId;
  String? busUrlHost;
  late final String clientId;
  Map<String, dynamic> context = {};

  TrytonSession({required this.rpcClient, SessionStore? store})
      : _store = store ?? SecureSessionStore() {
    clientId = const Uuid().v4();
    context = {'client': clientId};
  }

  bool get isLoggedIn => userId != null && userId! > 0;

  /// Returns the available databases for the configured server
  /// (empty when the server has the list disabled).
  Future<List<String>> listDatabases() => rpcClient.listDatabases();

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

    // Login at `<db>/rpc/` (spec 2.5.1). A 401 here means wrong
    // credentials – never open the re-login dialog for it.
    final result = await rpcClient.call(
      db,
      'common.db.login',
      [username, parameters, language],
      reAuth: false,
    );

    // Successful login: [user_id, session_token, bus_url_host]
    if (result is List &&
        result.length >= 2 &&
        result[0] is int &&
        (result[0] as int) > 0 &&
        result[1] is String) {
      database = db;
      login = username;
      userId = result[0] as int;
      busUrlHost = result.length > 2 ? result[2]?.toString() : null;
      rpcClient.auth = SessionAuth(username, userId!, result[1] as String);
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
      await rpcClient.call(database!, 'common.db.logout', [], reAuth: false);
    } catch (_) {
      // Spec 2.5.6: errors are ignored.
    } finally {
      await _store.delete();
      _clear();
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
      _mergeContext(prefs);
    } catch (_) {
      // Non-critical: context may stay minimal; server falls back to English.
    }
  }

  /// Replaces the context by the preferences, like the Python client's
  /// `RPCContextReload`: `context_reset()` (only `client` stays) and then
  /// the preferences, so keys no longer sent by the server disappear.
  void _mergeContext(dynamic prefs) {
    if (prefs is Map<String, dynamic>) {
      // Drop locale sub-object and rec_name keys (same filter as SAO)
      prefs.removeWhere((k, _) => k == 'locale' || k.endsWith('.rec_name'));
      context = {'client': clientId, ...prefs};
    }
  }

  // ─── Session persistence (task A8) ────────────────────────────────────────

  void _clear() {
    database = null;
    login = null;
    userId = null;
    busUrlHost = null;
    context = {'client': clientId};
    rpcClient.auth = null;
  }

  /// Saves the session token in secure storage for the next app start.
  Future<void> _storeSession() async {
    final auth = rpcClient.auth;
    if (auth == null || database == null) return;
    try {
      await _store.write(StoredSession(
        baseUrl: rpcClient.baseUrl,
        database: database!,
        login: auth.login,
        userId: auth.userId,
        token: auth.token,
        busUrlHost: busUrlHost,
      ));
    } catch (_) {
      // Keychain not available → session simply is not resumed.
    }
  }

  /// Resumes the stored session (spec 2.5, task A8): sets the token and
  /// checks it with `get_preferences(true)`. The device cookie can NOT be
  /// used for this – it does not replace the password (verified).
  ///
  /// Returns true when the session is valid. An expired/invalid token
  /// (HTTP 401/403) is deleted; on other errors (server unreachable) it is
  /// kept for the next start.
  Future<bool> restore() async {
    await _removeLegacySession();
    final stored = await _store.read();
    if (stored == null) return false;

    rpcClient.baseUrl = stored.baseUrl;
    rpcClient.auth = SessionAuth(stored.login, stored.userId, stored.token);
    context = {'client': clientId};
    try {
      final prefs = await rpcClient.call(
        stored.database,
        'model.res.user.get_preferences',
        [true, context],
        reAuth: false,
      );
      database = stored.database;
      login = stored.login;
      userId = stored.userId;
      busUrlHost = stored.busUrlHost;
      _mergeContext(prefs);
      return true;
    } on RpcHttpException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) await _store.delete();
      _clear();
      return false;
    } catch (_) {
      _clear();
      return false;
    }
  }

  /// The login form pre-fill (server, database, user) of the stored session.
  Future<StoredSession?> storedSession() => _store.read();

  Future<void> _removeLegacySession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacySessionKey);
    } catch (_) {}
  }

  /// Renews the device cookie (spec 2.5.3). The cookie only protects this
  /// device against the brute-force lockout – it does NOT replace the
  /// password (verified: login with only `device_cookie` →
  /// `LoginException(password)`).
  Future<void> _renewDeviceCookie(String db, String username) async {
    try {
      final cookies = await _loadAllDeviceCookies();
      final key = deviceCookieKey(username, rpcClient.baseUrl, db);
      final newCookie = await rpcClient.call(
        db,
        'model.res.user.device.renew',
        [cookies[key], context],
      );
      if (newCookie is String) {
        cookies[key] = newCookie;
        await _saveAllDeviceCookies(cookies);
      }
    } catch (_) {
      // Device cookie is optional – ignore errors
    }
  }

  /// Storage key of a device cookie, like the Python client:
  /// `login@host:port/database`, so two servers with the same database
  /// name do not share a cookie.
  static String deviceCookieKey(String login, String baseUrl, String db) {
    final uri = Uri.parse(baseUrl);
    return '$login@${uri.host}:${uri.port}/$db';
  }

  Future<String?> _loadDeviceCookie(String db, String username) async {
    final cookies = await _loadAllDeviceCookies();
    return cookies[deviceCookieKey(username, rpcClient.baseUrl, db)];
  }

  /// `{key: cookie}`. Entries of the former `{database: {login: cookie}}`
  /// format (without the server) are discarded.
  Future<Map<String, String>> _loadAllDeviceCookies() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_deviceCookieKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is String) e.key.toString(): e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAllDeviceCookies(Map<String, String> cookies) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceCookieKey, jsonEncode(cookies));
  }
}

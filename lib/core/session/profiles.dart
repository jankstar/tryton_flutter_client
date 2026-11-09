import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'session_store.dart';

/// A connection profile (spec 3.1, 16; Python `profiles.cfg`): name,
/// server URL, database and user – never a password.
class ConnectionProfile {
  final String name;
  final String serverUrl;
  final String database;
  final String login;

  const ConnectionProfile({
    required this.name,
    this.serverUrl = '',
    this.database = '',
    this.login = '',
  });

  ConnectionProfile copyWith(
          {String? name, String? serverUrl, String? database, String? login}) =>
      ConnectionProfile(
        name: name ?? this.name,
        serverUrl: serverUrl ?? this.serverUrl,
        database: database ?? this.database,
        login: login ?? this.login,
      );

  /// Key of the stored session and the device cookie of this profile
  /// (`login@host:port/database`); null while incomplete.
  String? get sessionKeyOrNull =>
      serverUrl.isEmpty || database.isEmpty || login.isEmpty
          ? null
          : sessionKey(login, serverUrl, database);

  Map<String, dynamic> toJson() => {
        'name': name,
        'server_url': serverUrl,
        'database': database,
        'login': login,
      };

  static ConnectionProfile? fromJson(dynamic j) {
    if (j is! Map || j['name'] is! String || (j['name'] as String).isEmpty) {
      return null;
    }
    return ConnectionProfile(
      name: j['name'] as String,
      serverUrl: '${j['server_url'] ?? ''}',
      database: '${j['database'] ?? ''}',
      login: '${j['login'] ?? ''}',
    );
  }

  /// The profile serves [host]/[port] and [database] (deep links, E7).
  bool serves(String host, int port, String database) {
    final uri = Uri.tryParse(serverUrl);
    return uri != null &&
        uri.host == host &&
        uri.port == port &&
        this.database == database;
  }

  @override
  bool operator ==(Object other) =>
      other is ConnectionProfile &&
      other.name == name &&
      other.serverUrl == serverUrl &&
      other.database == database &&
      other.login == login;

  @override
  int get hashCode => Object.hash(name, serverUrl, database, login);
}

/// The profiles and the one used last, kept in `shared_preferences`
/// (`tryton_profiles`, `tryton_profile_last`). On the first start the
/// former single settings (`login_server_url`, `login_database`) and the
/// user of the stored session become the profile „Standard“.
class ProfileStore {
  static const profilesKey = 'tryton_profiles';
  static const lastKey = 'tryton_profile_last';
  static const legacyServerKey = 'login_server_url';
  static const legacyDatabaseKey = 'login_database';
  static const defaultName = 'Standard';

  /// The user of the stored session (migration of the former settings).
  final Future<String?> Function()? storedLogin;

  ProfileStore({this.storedLogin});

  /// The profiles in their order (migrated on the first start).
  Future<List<ConnectionProfile>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(profilesKey);
    if (raw != null) {
      try {
        return [
          for (final p in jsonDecode(raw) as List) ?ConnectionProfile.fromJson(p)
        ];
      } catch (_) {
        return const [];
      }
    }
    final profiles = [
      ConnectionProfile(
        name: defaultName,
        serverUrl: prefs.getString(legacyServerKey) ?? 'http://localhost:8000',
        database: prefs.getString(legacyDatabaseKey) ?? '',
        login: await storedLogin?.call() ?? '',
      ),
    ];
    await save(profiles);
    await setLast(defaultName);
    return profiles;
  }

  Future<void> save(List<ConnectionProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        profilesKey, jsonEncode([for (final p in profiles) p.toJson()]));
  }

  /// Name of the profile used last.
  Future<String?> last() async =>
      (await SharedPreferences.getInstance()).getString(lastKey);

  Future<void> setLast(String name) async =>
      (await SharedPreferences.getInstance()).setString(lastKey, name);

  /// [profiles] with [profile] replacing the one of the same name (or
  /// appended).
  static List<ConnectionProfile> put(
      List<ConnectionProfile> profiles, ConnectionProfile profile) {
    final i = profiles.indexWhere((p) => p.name == profile.name);
    return i < 0
        ? [...profiles, profile]
        : [...profiles.sublist(0, i), profile, ...profiles.sublist(i + 1)];
  }

  /// [profiles] with [from] renamed to [to] (null when [to] is empty or
  /// taken by another profile).
  static List<ConnectionProfile>? rename(
      List<ConnectionProfile> profiles, String from, String to) {
    to = to.trim();
    if (to.isEmpty || (to != from && profiles.any((p) => p.name == to))) {
      return null;
    }
    return [
      for (final p in profiles) p.name == from ? p.copyWith(name: to) : p
    ];
  }

  /// A new name `base`, `base 2`, … not used by [profiles].
  static String uniqueName(List<ConnectionProfile> profiles, String base) {
    if (!profiles.any((p) => p.name == base)) return base;
    for (var i = 2;; i++) {
      final name = '$base $i';
      if (!profiles.any((p) => p.name == name)) return name;
    }
  }
}

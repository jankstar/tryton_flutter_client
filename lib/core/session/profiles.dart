import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../rpc/server_address.dart';
import 'session.dart' show kClientVersion;
import 'session_store.dart';

/// The public Tryton demo of the series (`demo<series>.tryton.org`, only
/// HTTPS; Python `dblogin.py` `current_demo`, `config.py` defaults): the
/// profile created when there is none. Server and database follow
/// [kClientVersion] (the series of the version check); the demo login is
/// lower case (`Demo` is refused by the server). Its password (`demo`) is
/// public but never stored or prefilled – the login screen only shows it
/// as a hint.
const demoServer = 'demo$kClientVersion.tryton.org';
const demoDatabase = 'demo$kClientVersion';
const demoLogin = 'demo';

/// Host names of the Tryton demos of every series (Python `DEMO_HOSTNAME`).
final demoHostname = RegExp(r'^demo\d+\.\d+\.tryton\.org$');

/// The demo profile of [series]: name and server `demo<series>.tryton.org`
/// (HTTPS), database `demo<series>`, user `demo`.
ConnectionProfile demoProfile([String series = kClientVersion]) =>
    ConnectionProfile(
      name: 'demo$series.tryton.org',
      serverUrl: 'https://demo$series.tryton.org',
      database: 'demo$series',
      login: demoLogin,
    );

/// Host of the server URL of [profile] (null when malformed).
String? profileHost(ConnectionProfile profile) =>
    ServerAddress.parse(profile.serverUrl)?.host.toLowerCase();

/// [profile] is the Tryton demo of [series].
bool isDemoProfile(ConnectionProfile profile, [String series = kClientVersion]) =>
    profileHost(profile) == 'demo$series.tryton.org';

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
/// user of the stored session become the profile „Standard“; without them
/// – and whenever the list is empty – the demo profile of the series is
/// created; demo profiles of other series are removed (Python
/// `DBLogin.__init__`).
class ProfileStore {
  static const profilesKey = 'tryton_profiles';
  static const lastKey = 'tryton_profile_last';
  static const legacyServerKey = 'login_server_url';
  static const legacyDatabaseKey = 'login_database';
  static const defaultName = 'Standard';

  /// The user of the stored session (migration of the former settings).
  final Future<String?> Function()? storedLogin;

  /// The series of the demo profile (default: the one of this client).
  final String series;

  ProfileStore({this.storedLogin, this.series = kClientVersion});

  /// The profiles in their order (migrated on the first start; the demo
  /// profile created and old demos removed, see [withDemo]).
  Future<List<ConnectionProfile>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(profilesKey);
    List<ConnectionProfile> stored;
    if (raw != null) {
      try {
        stored = [
          for (final p in jsonDecode(raw) as List) ?ConnectionProfile.fromJson(p)
        ];
      } catch (_) {
        stored = const [];
      }
    } else {
      // former settings of an older version
      final legacyServer = prefs.getString(legacyServerKey);
      stored = [
        if (legacyServer != null)
          ConnectionProfile(
            name: defaultName,
            serverUrl: legacyServer,
            database: prefs.getString(legacyDatabaseKey) ?? '',
            login: await storedLogin?.call() ?? '',
          ),
      ];
      if (stored.isNotEmpty) await setLast(defaultName);
    }
    final profiles = withDemo(stored, series);
    if (raw == null || !_sameProfiles(profiles, stored)) await save(profiles);
    return profiles;
  }

  static bool _sameProfiles(List<ConnectionProfile> a, List<ConnectionProfile> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((e) => e);

  /// [profiles] like Python `DBLogin.__init__`: empty → the demo profile
  /// of [series]; profiles of a demo server of another series removed,
  /// and when one was removed and the demo of [series] is missing, it is
  /// added. Other profiles stay as they are (also a deleted demo profile
  /// is not added again while other profiles exist).
  static List<ConnectionProfile> withDemo(List<ConnectionProfile> profiles,
      [String series = kClientVersion]) {
    if (profiles.isEmpty) return [demoProfile(series)];
    final current = 'demo$series.tryton.org';
    final kept = [
      for (final p in profiles)
        if (!(demoHostname.hasMatch(profileHost(p) ?? '') &&
            profileHost(p) != current))
          p
    ];
    if (kept.length < profiles.length &&
        !kept.any((p) => p.name == current || isDemoProfile(p, series))) {
      kept.add(demoProfile(series));
    }
    return kept;
  }

  /// The profile preselected in the login screen: the one used last, else
  /// the demo profile, else the first one.
  static ConnectionProfile? preselected(
          List<ConnectionProfile> profiles, String? last,
          [String series = kClientVersion]) =>
      profiles.where((p) => p.name == last).firstOrNull ??
      profiles.where((p) => isDemoProfile(p, series)).firstOrNull ??
      profiles.firstOrNull;

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

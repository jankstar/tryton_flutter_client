import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/core/session/profiles.dart';
import 'package:tryton_flutter_client/core/session/session_store.dart';

/// Connection profiles (spec 3.1, 16; H6) and the stored sessions per
/// `login@host:port/db`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileStore', () {
    test('migration: the former settings and the user of the stored '
        'session become „Standard“', () async {
      SharedPreferences.setMockInitialValues({
        ProfileStore.legacyServerKey: 'http://srv:8000',
        ProfileStore.legacyDatabaseKey: 'tryton',
      });
      final store = ProfileStore(storedLogin: () async => 'admin');
      final profiles = await store.load();
      expect(profiles, [
        const ConnectionProfile(
            name: 'Standard',
            serverUrl: 'http://srv:8000',
            database: 'tryton',
            login: 'admin'),
      ]);
      expect(await store.last(), 'Standard');
      // saved: the next load reads the profiles, not the old keys
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString(ProfileStore.profilesKey)!), hasLength(1));
    });

    test('create, rename, delete; no passwords stored', () async {
      SharedPreferences.setMockInitialValues({});
      final store = ProfileStore();
      var profiles = await store.load();
      profiles = ProfileStore.put(
          profiles,
          ConnectionProfile(
              name: ProfileStore.uniqueName(profiles, 'Standard'),
              serverUrl: 'http://other:8000',
              database: 'prod',
              login: 'jan'));
      expect(profiles.map((p) => p.name), ['Standard', 'Standard 2']);
      expect(ProfileStore.rename(profiles, 'Standard 2', 'Standard'), isNull,
          reason: 'name taken');
      expect(ProfileStore.rename(profiles, 'Standard 2', '  '), isNull);
      profiles = ProfileStore.rename(profiles, 'Standard 2', 'Prod')!;
      expect(profiles.map((p) => p.name), ['Standard', 'Prod']);
      profiles = [...profiles]..removeWhere((p) => p.name == 'Standard');
      await store.save(profiles);
      await store.setLast('Prod');

      final again = await ProfileStore().load();
      expect(again.single.name, 'Prod');
      expect(again.single.sessionKeyOrNull, 'jan@other:8000/prod');
      expect(await store.last(), 'Prod');
      final raw = (await SharedPreferences.getInstance())
          .getString(ProfileStore.profilesKey)!;
      expect(raw, isNot(contains('password')));
    });

    test('serves host, port and database (deep links)', () {
      const p = ConnectionProfile(
          name: 'x', serverUrl: 'https://erp.example.com', database: 'db');
      expect(p.serves('erp.example.com', 443, 'db'), isTrue);
      expect(p.serves('erp.example.com', 8000, 'db'), isFalse);
      expect(p.serves('erp.example.com', 443, 'other'), isFalse);
    });
  });

  group('SecureSessionStore', () {
    StoredSession session(String login, String db) => StoredSession(
        baseUrl: 'http://srv:8000',
        database: db,
        login: login,
        userId: 1,
        token: 'tok-$login-$db');

    test('one session per login@host:port/db; without key the last one',
        () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureSessionStore();
      await store.write(session('admin', 'a'));
      await store.write(session('jan', 'b'));
      expect((await store.read('admin@srv:8000/a'))?.token, 'tok-admin-a');
      expect((await store.read('jan@srv:8000/b'))?.token, 'tok-jan-b');
      expect((await store.read())?.token, 'tok-jan-b', reason: 'last');
      await store.delete('admin@srv:8000/a');
      expect(await store.read('admin@srv:8000/a'), isNull);
      expect(await store.read('jan@srv:8000/b'), isNotNull,
          reason: 'the other profile keeps its session');
    });

    test('the single session of tryton_session_v1 moves to its key',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        'tryton_session_v1': jsonEncode(session('admin', 'tryton').toJson()),
      });
      final store = SecureSessionStore();
      expect((await store.read('admin@srv:8000/tryton'))?.token,
          'tok-admin-tryton');
      expect((await store.read())?.login, 'admin');
    });
  });
}

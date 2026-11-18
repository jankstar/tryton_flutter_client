import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/core/session/profiles.dart';
import 'package:tryton_flutter_client/core/session/session.dart'
    show kAppVersion, kClientVersion;
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

    test('empty profile list (new installation): the demo profile of the '
        'series, no password, no localhost', () async {
      SharedPreferences.setMockInitialValues({});
      final store = ProfileStore();
      final profiles = await store.load();
      expect(profiles, [
        const ConnectionProfile(
            name: 'demo8.0.tryton.org',
            serverUrl: 'https://demo8.0.tryton.org',
            database: 'demo8.0',
            login: 'demo'),
      ]);
      expect(isDemoProfile(profiles.single), isTrue);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(ProfileStore.profilesKey)!;
      expect(raw, isNot(contains('localhost')));
      expect(raw, isNot(contains('password')), reason: 'the password is not stored');
      // no profile used last: the demo profile is preselected
      expect(await store.last(), isNull);
      expect(ProfileStore.preselected(profiles, null), profiles.single);
    });

    test('a stored empty list (all deleted) gives the demo profile again',
        () async {
      SharedPreferences.setMockInitialValues({ProfileStore.profilesKey: '[]'});
      expect((await ProfileStore().load()).single.name, 'demo8.0.tryton.org');
    });

    test('existing profiles: no demo profile (also after deleting it)',
        () async {
      const firma = ConnectionProfile(
          name: 'Firma', serverUrl: 'erp.example.com', database: 'f', login: 'jan');
      SharedPreferences.setMockInitialValues({
        ProfileStore.profilesKey: jsonEncode([firma.toJson()]),
      });
      expect(await ProfileStore().load(), [firma]);
      expect(ProfileStore.preselected([firma], null), firma);
    });

    test('old demo7.6.tryton.org is removed, demo8.0 added; others stay',
        () async {
      const firma = ConnectionProfile(
          name: 'Firma', serverUrl: 'erp.example.com', database: 'f', login: 'jan');
      const old = ConnectionProfile(
          name: 'demo7.6.tryton.org',
          serverUrl: 'demo7.6.tryton.org',
          database: 'demo7.6',
          login: 'demo');
      const oldHttps = ConnectionProfile(
          name: 'Alte Demo', serverUrl: 'https://demo6.0.tryton.org:443', database: 'demo6.0');
      SharedPreferences.setMockInitialValues({
        ProfileStore.profilesKey:
            jsonEncode([old.toJson(), firma.toJson(), oldHttps.toJson()]),
        ProfileStore.lastKey: 'demo7.6.tryton.org',
      });
      final store = ProfileStore();
      final profiles = await store.load();
      expect(profiles.map((p) => p.name), ['Firma', 'demo8.0.tryton.org']);
      expect(profiles.last, demoProfile('8.0'));
      // saved: the next start reads the cleaned list
      final raw = (await SharedPreferences.getInstance())
          .getString(ProfileStore.profilesKey)!;
      expect(raw, isNot(contains('demo7.6')));
      // the profile used last is gone: the demo profile is preselected
      expect(ProfileStore.preselected(profiles, await store.last()), profiles.last);
    });

    test('nothing removed: the deleted demo profile is not added again',
        () {
      const firma = ConnectionProfile(name: 'Firma', serverUrl: 'erp.example.com');
      const other = ConnectionProfile(name: 'Test', serverUrl: 'demo.example.org');
      expect(ProfileStore.withDemo([firma, other], '8.0'), [firma, other]);
      // the current demo kept under another name: no second one
      const renamed = ConnectionProfile(
          name: 'Meine Demo', serverUrl: 'demo8.0.tryton.org', database: 'demo8.0');
      const old = ConnectionProfile(name: 'x', serverUrl: 'demo7.6.tryton.org');
      expect(ProfileStore.withDemo([renamed, old], '8.0'), [renamed]);
    });

    test('the series comes from the app version (TRYTON_SERIES / pubspec)',
        () async {
      expect(demoServer, 'demo$kClientVersion.tryton.org');
      expect(demoDatabase, 'demo$kClientVersion');
      expect(demoProfile(), demoProfile(kClientVersion));
      expect(kAppVersion, startsWith('$kClientVersion.'));
      // another series: demo8.2, and the 8.0 demo is an old one then
      SharedPreferences.setMockInitialValues({
        ProfileStore.profilesKey: jsonEncode([demoProfile('8.0').toJson()]),
      });
      final profiles = await ProfileStore(series: '8.2').load();
      expect(profiles, [
        const ConnectionProfile(
            name: 'demo8.2.tryton.org',
            serverUrl: 'https://demo8.2.tryton.org',
            database: 'demo8.2',
            login: 'demo'),
      ]);
    });

    test('create, rename, delete; no passwords stored', () async {
      SharedPreferences.setMockInitialValues({});
      final store = ProfileStore();
      var profiles = await store.load();
      profiles = ProfileStore.rename(profiles, demoProfile().name, 'Standard')!;
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

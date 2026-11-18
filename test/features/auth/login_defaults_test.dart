import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/app.dart';
import 'package:tryton_flutter_client/core/session/profiles.dart';

/// The login screen on the first start: the profile of the Tryton demo of
/// the series (English, `demo<series>.tryton.org`, user demo) without its
/// password – only a hint names it; saved values win.
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  String textOf(WidgetTester tester, String label) => tester
      .widget<TextField>(find.ancestor(
          of: find.text(label), matching: find.byType(TextField)))
      .controller!
      .text;

  testWidgets('first start: demo profile preselected, no password, hint',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: TrytonFlutterClientApp()));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(find.text(demoServer), findsWidgets, reason: 'profile name');
    expect(textOf(tester, 'Server URL'), 'https://$demoServer');
    expect(textOf(tester, 'Database'), demoDatabase);
    expect(textOf(tester, 'Username'), 'demo');
    expect(textOf(tester, 'Password'), '');
    expect(find.text('Demo server: password “demo”'), findsOneWidget);
    expect(find.textContaining('localhost'), findsNothing);
  });

  testWidgets('hint in German, only for the demo profile', (tester) async {
    SharedPreferences.setMockInitialValues({
      'tryton_login_language': 'de',
      ProfileStore.profilesKey: jsonEncode([
        demoProfile().toJson(),
        const ConnectionProfile(
                name: 'Firma', serverUrl: 'erp.example.com', database: 'f', login: 'jan')
            .toJson(),
      ]),
    });
    await tester.pumpWidget(const ProviderScope(child: TrytonFlutterClientApp()));
    await tester.pumpAndSettle();
    expect(find.text('Demo-Server: Passwort „demo“'), findsOneWidget,
        reason: 'no profile used last: the demo profile');
  });

  testWidgets('saved values of another server: no demo, no password',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ProfileStore.profilesKey: jsonEncode([
        const ConnectionProfile(
                name: 'Firma',
                serverUrl: 'erp.example.com',
                database: 'firma',
                login: 'jan')
            .toJson(),
      ]),
      ProfileStore.lastKey: 'Firma',
    });
    await tester.pumpWidget(const ProviderScope(child: TrytonFlutterClientApp()));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'Server URL'), 'erp.example.com');
    expect(textOf(tester, 'Database'), 'firma');
    expect(textOf(tester, 'Username'), 'jan');
    expect(textOf(tester, 'Password'), '');
    expect(find.textContaining('Demo server'), findsNothing);
  });
}

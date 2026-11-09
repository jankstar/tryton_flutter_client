import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/session/profiles.dart';
import 'package:tryton_flutter_client/features/auth/profile_editor.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

/// Profile editor (spec 3.1, Python `DBListEditor`).
void main() {
  const standard = ConnectionProfile(
      name: 'Standard',
      serverUrl: 'http://srv:8000',
      database: 'tryton',
      login: 'admin');

  /// Opens the editor; [result] receives its answer.
  Future<void> open(WidgetTester tester,
      void Function(({List<ConnectionProfile> profiles, String? selected})?) result,
      {ServerProbe? probe}) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result(await showProfileEditor(context,
              profiles: const [standard],
              selected: 'Standard',
              probe: probe ??
                  (url) async => (version: '8.0.3', databases: ['tryton', 'test']))),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('create, rename (taken name refused), fields, delete',
      (tester) async {
    ({List<ConnectionProfile> profiles, String? selected})? answer;
    await open(tester, (r) => answer = r);
    expect(find.byKey(const ValueKey('profile-Standard')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-New profile')), findsOneWidget);
    // a new profile takes the server of the one selected before
    expect(
        tester.widget<TextField>(find.byKey(const ValueKey('profile-server'))).controller!.text,
        'http://srv:8000');

    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Standard');
    await tester.tap(find.byKey(const ValueKey('profile-rename')));
    await tester.pumpAndSettle();
    expect(find.text('This profile name is already used.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Prod');
    await tester.tap(find.byKey(const ValueKey('profile-rename')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-Prod')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('profile-database')), 'prod');
    await tester.enterText(find.byKey(const ValueKey('profile-login')), 'jan');

    // delete Standard
    await tester.tap(find.byKey(const ValueKey('profile-Standard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-ok')));
    await tester.pumpAndSettle();

    expect(answer!.profiles, [
      const ConnectionProfile(
          name: 'Prod', serverUrl: 'http://srv:8000', database: 'prod', login: 'jan'),
    ]);
    expect(answer!.selected, 'Prod');
  });

  testWidgets('server check: database list, incompatible version, no '
      'connection', (tester) async {
    ({String? version, List<String>? databases}) probe =
        (version: '8.0.3', databases: <String>['tryton', 'test']);
    await open(tester, (_) {}, probe: (url) async => probe);
    await tester.tap(find.byKey(const ValueKey('profile-check')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-database-list')), findsOneWidget);
    expect(find.text('Tryton 8.0.3'), findsOneWidget);

    probe = (version: '7.6.1', databases: <String>['tryton']);
    await tester.tap(find.byKey(const ValueKey('profile-check')));
    await tester.pumpAndSettle();
    expect(find.text('Incompatible version of the server.'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-database')), findsOneWidget,
        reason: 'free text');

    probe = (version: null, databases: null);
    await tester.tap(find.byKey(const ValueKey('profile-check')));
    await tester.pumpAndSettle();
    expect(find.text('Could not connect to the server.'), findsOneWidget);
  });
}

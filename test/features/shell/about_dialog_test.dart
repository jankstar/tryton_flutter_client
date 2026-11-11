import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/session/session.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/shell/about_dialog.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

/// "About …" (spec 11.12, Python about.py): logo, version, comments,
/// Credits/License/Copyright, links, narrow screens (the licences of the
/// app: app_licenses_test.dart).
class _Server extends RpcClient {
  _Server() : super(baseUrl: 'http://localhost:8000');

  @override
  Future<String> serverVersion() async => '8.0.5';
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  /// Opens a text of the About dialog: the asset loads in real time.
  Future<void> openText(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<List<String>> pump(WidgetTester tester,
      {Size size = const Size(1200, 900), bool loggedIn = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    final rpc = _Server();
    final session = TrytonSession(rpcClient: rpc);
    if (loggedIn) {
      session
        ..userId = 1
        ..database = 'tryton'
        ..login = 'admin';
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [
        rpcClientProvider.overrideWithValue(rpc),
        sessionProvider.overrideWithValue(session),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showAboutTryton(context, openUrl: opened.add),
                child: const Text('open about'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open about'));
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('Tryton logo, version, copyright and links like the Python '
      'client; no comments, no server facts', (tester) async {
    final opened = await pump(tester);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byKey(const ValueKey('about-logo')), findsOneWidget);
    expect(find.text(appName), findsOneWidget);
    // a local build: no release label → development version, no badge
    expect(find.text('Version $kAppVersion (development)'), findsOneWidget);
    expect(find.byKey(const ValueKey('prerelease-badge')), findsNothing);
    expect(find.text('modularity, scalability and security'), findsNothing);
    for (final text in ['8.0.5', 'admin']) {
      expect(find.text(text), findsNothing, reason: text);
    }
    expect(find.text('Copyright (C) 2026 jankstar'), findsOneWidget);
    expect(find.textContaining('Copyright (C) 2004-2026 Tryton'), findsOneWidget);

    // the warranty note of Gtk.AboutDialog (GPL 3.0), the licence a link
    final warranty = tester
        .widget<Text>(find.byKey(const ValueKey('about-warranty')))
        .textSpan!
        .toPlainText();
    expect(
        warranty,
        'This program comes with absolutely no warranty.\n'
        'See the GNU General Public License, version 3 or later for details.');

    await tester.tap(find.byKey(const ValueKey('about-link-$appProjectUrl')));
    await tester.tap(find.byKey(const ValueKey('about-link-$trytonUrl')));
    await tester.tapOnText(find.textRange
        .ofSubstring('GNU General Public License, version 3 or later'));
    expect(opened, [appProjectUrl, trytonUrl, gplUrl]);
  });

  testWidgets('Credits, License and Copyright open their texts',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('about-credits')));
    await tester.pumpAndSettle();
    expect(find.text('Cédric Krier <cedric.krier@b2ck.com>'), findsOneWidget);
    expect(find.text('jankstar'), findsOneWidget);
    expect(find.text('Svenska'), findsOneWidget);
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();

    await openText(tester, 'about-license');
    expect(find.byKey(const ValueKey('about-text-LICENSE')), findsOneWidget);
    expect(find.textContaining('GNU GENERAL PUBLIC LICENSE'), findsOneWidget);
    await tester.tap(find.text('Close').last);
    await tester.pump(const Duration(milliseconds: 300));

    await openText(tester, 'about-copyright');
    final copyright = tester.widget<SelectableText>(find.descendant(
        of: find.byKey(const ValueKey('about-text-COPYRIGHT')),
        matching: find.byType(SelectableText)));
    expect(copyright.data, contains('tryton_flutter_client'));
    expect(copyright.style?.fontFamily, 'monospace');
  });

  testWidgets('narrow screen: a full-screen page instead of a dialog',
      (tester) async {
    await pump(tester, size: const Size(390, 800));
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('about-content')), findsOneWidget);
    expect(find.text('About…'), findsOneWidget, reason: 'title of the page');
    expect(tester.takeException(), isNull);
  });

  testWidgets('release label: version text and the test version badge',
      (tester) async {
    late AppLocalizations l;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        l = AppLocalizations.of(context)!;
        return const Column(children: [
          PrereleaseBadge(label: '8.0.0-beta.1'),
          PrereleaseBadge(label: '8.0.0'),
        ]);
      }),
    ));
    expect(appVersionText(l, label: '8.0.0-beta.1', build: '42'),
        '8.0.0-beta.1 (Build 42)');
    expect(appVersionText(l, label: '8.0.0', build: ''), '8.0.0');
    expect(appVersionText(l, label: '', build: ''), '$kAppVersion (Entwicklung)');
    expect(isPrerelease('8.0.0-beta.1'), isTrue);
    expect(isPrerelease('8.0.0-dev.7'), isTrue);
    expect(isPrerelease('8.0.0'), isFalse);
    expect(find.text('Testversion'), findsOneWidget, reason: 'only the beta');
  });

  test('documentation of the series like the Python client', () {
    expect(documentationUrl('8.0'), 'https://docs.tryton.org/8.0');
    expect(documentationUrl('7.5'), 'https://docs.tryton.org/latest');
    expect(documentationUrl(), 'https://docs.tryton.org/$kClientVersion');
  });
}

@Tags(['integration'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/core/session/profiles.dart' show demoServer;
import 'package:tryton_flutter_client/features/auth/login_screen.dart';
import 'package:tryton_flutter_client/features/shell/about_dialog.dart';
import 'package:tryton_flutter_client/features/auth/user_preferences_provider.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';
import 'package:tryton_flutter_client/features/shell/tab_strip.dart';
import 'package:tryton_flutter_client/features/tabs/user_chip.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

/// Screenshots of the tab bar of the shell (no server): many tabs with
/// the "all tabs" button, its list open, and few tabs.
///
///     SCREENSHOT_DIR=/tmp/shots flutter test --run-skipped -t integration \
///       test/integration/tab_bar_screenshot_test.dart
Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = '$sdk/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$dir/$f');
      if (!file.existsSync()) continue;
      loader.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Roboto', [
    for (final f in Directory(dir).listSync())
      if (f.path.split('/').last.startsWith('Roboto-')) f.path.split('/').last
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

const _titles = [
  'Parteien', 'Kundenrechnungen', 'Lieferantenrechnungen', 'Wirtschaftseinheiten',
  'Gebäude', 'Abrechnungseinheiten', 'Mietverträge', 'Zahlungen', 'Kontoauszüge',
  'Buchungssätze', 'Aufgaben', 'Zeitplaner',
];

void main() {
  final out = Platform.environment['SCREENSHOT_DIR'];

  for (final (name, count, open) in [
    ('tabs-many', 12, false),
    ('tabs-many-list', 12, true),
    ('tabs-few', 3, false),
  ]) {
    testWidgets('screenshot $name', (tester) async {
      if (out == null) {
        markTestSkipped('SCREENSHOT_DIR not set');
        return;
      }
      await tester.runAsync(_loadFonts);
      const size = Size(900, 620);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      final tabs = [
        for (var i = 0; i < count; i++)
          AppTab(
              id: 't$i',
              title: 'Menü / ${_titles[i]}',
              attributes: const ScreenAttributes('party.party')),
      ];
      final theme = AppTheme.polarFox.buildThemeData();
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ProviderScope(
          overrides: [
            preferencesProvider.overrideWith(
                (ref) => {'status_bar': 'Administrator [EUR]'}),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'Roboto')),
            locale: const Locale('de'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(builder: (context) {
              final cs = Theme.of(context).colorScheme;
              return Scaffold(
                body: Column(children: [
                  // like AppShell._tabBar
                  Container(
                    height: 40,
                    color: cs.surfaceContainerHighest,
                    child: Row(children: [
                      const SizedBox(
                          width: 40, child: Icon(Icons.menu_open, size: 18)),
                      Expanded(
                        child: TabStrip(
                          tabs: tabs,
                          activeIndex: count - 1,
                          onActivate: (_) {},
                          onClose: (_) {},
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 428),
                        child: const UserChip(),
                      ),
                      const SizedBox(width: 4),
                    ]),
                  ),
                  const Expanded(child: SizedBox()),
                ]),
              );
            }),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      if (open) {
        await tester.tap(find.byKey(const ValueKey('tabs-all')));
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(out).createSync(recursive: true);
        File('$out/flutter-$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    });
  }

  _aboutScreenshot(out);

  // the login screen with the connection reached (lock icon)
  for (final (name, url) in [
    ('login-http', 'http://localhost:8000'),
    ('login-https', 'https://erp.example.com:8000'),
  ]) {
    testWidgets('screenshot $name', (tester) async {
      if (out == null) {
        markTestSkipped('SCREENSHOT_DIR not set');
        return;
      }
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await tester.runAsync(_loadFonts);
      const size = Size(700, 820);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final boundary = GlobalKey();
      final theme = AppTheme.polarFox.buildThemeData();
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _ReachedAuth(ref, url)),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'Roboto')),
            locale: const Locale('de'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LoginScreen(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, demoServer).first,
          url.startsWith('https') ? 'erp.example.com' : 'localhost:8000');
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(out).createSync(recursive: true);
        File('$out/flutter-$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    });
  }
}

/// Screenshot of "About …" (dialog).
void _aboutScreenshot(String? out) {
  testWidgets('screenshot about', (tester) async {
    if (out == null) {
      markTestSkipped('SCREENSHOT_DIR not set');
      return;
    }
    await tester.runAsync(_loadFonts);
    const size = Size(760, 760);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    final theme = AppTheme.polarFox.buildThemeData();
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'Roboto')),
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showAboutTryton(context, openUrl: (_) {}),
                  child: const Text('about'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('about'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(out).createSync(recursive: true);
      File('$out/flutter-about.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}

/// Auth state after reaching [url] (no server needed).
class _ReachedAuth extends AuthNotifier {
  _ReachedAuth(Ref ref, String url)
      : super(ref.read(sessionProvider), ref.read(rpcClientProvider)) {
    state = AuthState(serverUrl: url);
  }

  @override
  Future<void> loadDatabases(String serverUrl) async {}
}

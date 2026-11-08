@Tags(['integration'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/auth/user_preferences_provider.dart';
import 'package:tryton_flutter_client/features/model/metadata_service.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/views/screen_widget.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

/// Screenshots of forms of the test server (read only) for comparing the
/// layout with the reference clients (spec 9.2.2):
///
///     SCREENSHOT_DIR=/tmp/shots TRYTON_PASSWORD=… \
///       flutter test --run-skipped -t integration test/integration/form_screenshots_test.dart
///
/// Without `SCREENSHOT_DIR` the test does nothing. Real fonts (Roboto and
/// the Material icons of the Flutter SDK) replace the test font.
const _server = 'http://127.0.0.1:8000';
const _database = 'tryton';

/// Forms to take: name, model, id (null: the list), context, size.
const _forms = [
  ('parties-list', 'party.party', null, <String, dynamic>{}, Size(1040, 900)),
  ('party', 'party.party', 44, <String, dynamic>{}, Size(1040, 1400)),
  ('party-narrow', 'party.party', 44, <String, dynamic>{}, Size(420, 1800)),
  ('invoice', 'account.invoice', 1920, {'type': 'out'}, Size(1040, 1400)),
  ('billing-unit', 'real_estate.billing_unit', 1, <String, dynamic>{}, Size(1040, 1400)),
];

Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = '$sdk/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('$dir/$f');
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    for (final f in Directory(dir).listSync())
      if (f.path.split('/').last.startsWith('Roboto-')) f.path.split('/').last
  ]);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final password = env['TRYTON_PASSWORD'];
  final out = env['SCREENSHOT_DIR'];

  for (final (name, model, id, context, size) in _forms) {
    testWidgets('screenshot $name', (tester) async {
      if (password == null || out == null) {
        markTestSkipped('TRYTON_PASSWORD / SCREENSHOT_DIR not set');
        return;
      }
      HttpOverrides.global = null;
      late RpcClient rpc;
      late ModelService svc;
      late Map<String, dynamic> preferences;
      await tester.runAsync(() async {
        await _loadFonts();
        rpc = RpcClient(baseUrl: _server);
        final result = await rpc.call(_database, 'common.db.login', [
          'admin',
          {'password': password},
          'de'
        ], reAuth: false) as List;
        rpc.auth = SessionAuth('admin', result[0] as int, result[1] as String);
        var ctx = <String, dynamic>{};
        svc = ModelService(
            rpc: rpc, getContext: () => ctx, getDatabase: () => _database);
        final prefs = await svc.execute<Map<String, dynamic>>(
            'res.user', 'get_preferences', [true]);
        ctx = {
          for (final e in prefs.entries)
            if (e.key != 'locale' && !e.key.endsWith('.rec_name')) e.key: e.value
        };
        preferences = await svc.execute<Map<String, dynamic>>(
            'res.user', 'get_preferences', [false]);
        await (svc.metadata = MetadataService(svc))
            .load(locale: preferences['locale'] as Map<String, dynamic>?);
      });
      addTearDown(() => tester.runAsync(() async {
            try {
              await rpc.call(_database, 'common.db.logout', [], reAuth: false);
            } catch (_) {}
          }));
      // (the live binding takes the surface size, not the view's)
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ProviderScope(
          overrides: [
            rpcClientProvider.overrideWithValue(rpc),
            modelServiceProvider.overrideWithValue(svc),
            preferencesProvider.overrideWith((ref) => preferences),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            // the window size of the screenshot (narrow layout < 600 px)
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(size: size),
                child: child!),
            theme: ThemeData(fontFamily: 'Roboto'),
            locale: const Locale('de'),
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              FlutterQuillLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: ScreenWidget(
                attributes: ScreenAttributes(model,
                    mode: id == null ? const ['tree'] : const ['form'],
                    resId: id,
                    context: context),
                title: name),
          ),
        ),
      ));
      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await render.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(out).createSync(recursive: true);
        File('$out/flutter-$name.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
      });
    });
  }
}

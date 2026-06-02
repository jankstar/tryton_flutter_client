import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/l10n/locale_provider.dart';
import 'core/rpc/reauth_service.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/relogin_dialog.dart';
import 'features/model/model_service.dart';
import 'features/tabs/model_browser_screen.dart';
import 'features/views/dynamic_form_screen.dart';
import 'features/views/list_view_screen.dart';
import 'l10n/app_localizations.dart';

final _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/models',
      builder: (context, state) => const ModelBrowserScreen(),
      routes: [
        GoRoute(
          path: ':model',
          builder: (ctx, state) {
            final model = state.pathParameters['model']!;
            final title = state.uri.queryParameters['title'] ?? model;
            // Decode domain from URL (encoded as JSON by _openAction)
            final domainJson = state.uri.queryParameters['domain'];
            List<dynamic> domain = const [];
            if (domainJson != null && domainJson.isNotEmpty) {
              try {
                final decoded = jsonDecode(Uri.decodeComponent(domainJson));
                if (decoded is List) domain = decoded;
              } catch (_) {}
            }
            final q = state.uri.queryParameters;
            final contextModel = q['context_model'] != null
                ? Uri.decodeComponent(q['context_model']!)
                : null;
            final contextDomain = q['context_domain'] != null
                ? Uri.decodeComponent(q['context_domain']!)
                : null;
            final actionId = q['action_id'] != null
                ? int.tryParse(q['action_id']!)
                : null;
            return ListViewScreen(
              model: model,
              title: title,
              initialDomain: domain,
              contextModel: contextModel,
              contextDomain: contextDomain,
              actionId: actionId,
            );
          },
          routes: [
            GoRoute(
              path: 'new',
              builder: (ctx, state) {
                final model = state.pathParameters['model']!;
                final title = state.uri.queryParameters['title'] ?? model;
                final domain = _decodeDomain(state.uri.queryParameters['domain']);
                return DynamicFormScreen(
                    model: model, title: title, recordId: -1,
                    screenDomain: domain);
              },
            ),
            GoRoute(
              path: ':id',
              builder: (ctx, state) {
                final model = state.pathParameters['model']!;
                final id = int.parse(state.pathParameters['id']!);
                final title = state.uri.queryParameters['title'] ?? model;
                final domain = _decodeDomain(state.uri.queryParameters['domain']);
                return DynamicFormScreen(
                    model: model, title: title, recordId: id,
                    screenDomain: domain);
              },
            ),
          ],
        ),
      ],
    ),
  ],
);

// Border radius matching OutlineInputBorder default (4px) for visual consistency.
const _kRadius = BorderRadius.all(Radius.circular(4));
const _kShape = RoundedRectangleBorder(borderRadius: _kRadius);

ThemeData _buildTheme(Brightness brightness) {
  final cs = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0055A5),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: _kShape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: _kShape),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: _kShape),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(shape: _kShape),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: _kShape),
    ),
  );
}

List<dynamic> _decodeDomain(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const [];
  try {
    final decoded = jsonDecode(Uri.decodeComponent(encoded));
    if (decoded is List) return decoded;
  } catch (_) {}
  return const [];
}

class TrytonFlutterClientApp extends ConsumerStatefulWidget {
  const TrytonFlutterClientApp({super.key});

  @override
  ConsumerState<TrytonFlutterClientApp> createState() => _TrytonFlutterClientAppState();
}

class _TrytonFlutterClientAppState extends ConsumerState<TrytonFlutterClientApp> {
  StreamSubscription<Completer<void>>? _reAuthSub;

  @override
  void initState() {
    super.initState();
    _reAuthSub = ReAuthService.reAuthRequests.listen((completer) {
      if (mounted) {
        showReLoginDialog(context);
      } else {
        ReAuthService.fail();
      }
    });
  }

  /// After login: read res.user.language.code from the server and apply it.
  Future<void> _applyServerLocale() async {
    try {
      final session = ref.read(sessionProvider);
      final svc = ref.read(modelServiceProvider);
      if (session.userId == null) return;
      final users = await svc.read('res.user', [session.userId!], ['language']);
      if (users.isEmpty) return;
      final lang = users.first['language'];
      // language comes as [id, rec_name] from read(); rec_name is the language
      // name, not the code. We need a second read on ir.lang for the code.
      int? langId;
      if (lang is List && lang.isNotEmpty) langId = lang[0] as int?;
      if (lang is int) langId = lang;
      if (langId == null) return;
      final langs = await svc.read('ir.lang', [langId], ['code']);
      if (langs.isEmpty) return;
      final code = langs.first['code']?.toString();
      await ref.read(localeProvider.notifier).applyServerLanguage(code);
    } catch (_) {
      // Language loading is non-critical; keep current locale.
    }
  }

  @override
  void dispose() {
    _reAuthSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);

    // When login completes, load the server language and persist it.
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.status == AuthStatus.authenticated && prev?.status != AuthStatus.authenticated) {
        _applyServerLocale();
      }
    });

    return MaterialApp.router(
      title: 'Tryton Flutter Client',
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      routerConfig: _router,
    );
  }
}

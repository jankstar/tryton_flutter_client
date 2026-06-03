import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/l10n/locale_provider.dart';
import 'core/rpc/reauth_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/auth/auth_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/relogin_dialog.dart';
import 'features/model/model_service.dart';
import 'features/shell/app_shell.dart';
import 'l10n/app_localizations.dart';

final _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/app',   builder: (context, state) => const AppShell()),
  ],
);



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
    final currentTheme = ref.watch(themeProvider);

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
      theme: currentTheme.buildThemeData(),
      themeMode: ThemeMode.light,
      routerConfig: _router,
    );
  }
}

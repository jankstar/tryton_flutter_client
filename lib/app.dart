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
import 'features/auth/session_bootstrap.dart';
import 'features/model/metadata_service.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/relogin_dialog.dart';
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

  /// Start sequence after login (spec 3.2): see [SessionBootstrap].
  Future<void> _startSession() async {
    // The metadata service is attached to the ModelService on first read.
    ref.read(metadataServiceProvider);
    try {
      await ref.read(sessionBootstrapProvider).run();
    } catch (_) {
      // The app stays usable; menu/user chip show their error state.
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
        _startSession();
      } else if (next.status == AuthStatus.unauthenticated &&
          prev?.status == AuthStatus.authenticated) {
        // Logout: preferences (menu, user chip) and metadata are cleared.
        ref.read(sessionBootstrapProvider).clear();
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
      // Writing direction of the user's language (language_direction).
      builder: (context, child) => Directionality(
        textDirection: ref.watch(textDirectionProvider),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/theme/app_theme.dart';
import 'package:tryton_flutter_client/core/theme/tryton_colors.dart';
import 'package:tryton_flutter_client/features/auth/user_preferences_provider.dart';
import 'package:tryton_flutter_client/features/tabs/user_chip.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

/// The user menu (SAO user dropdown, Python application menu): on the
/// coloured tab bar its icons keep the colour of the main menu (the popup
/// would take the light icon colour of the bar), and the help group has
/// no dead caption entry – the divider sets it apart like in SAO.
void main() {
  for (final appTheme in [AppTheme.blueOcean, AppTheme.polarFox]) {
    testWidgets('${appTheme.label}: icons like the main menu, no dead '
        '„Help“ caption', (tester) async {
      final theme = appTheme.buildThemeData();
      final tc = theme.extension<TrytonColors>()!;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          preferencesProvider
              .overrideWith((ref) => {'status_bar': 'Administrator'}),
        ],
        child: MaterialApp(
          theme: theme,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // like AppShell's tab bar: the light colour of the band
          home: Scaffold(
            body: Container(
              color: tc.tabBarBackground,
              height: 40,
              child: IconTheme.merge(
                data: IconThemeData(color: tc.tabBarForeground),
                child: const Align(
                    alignment: Alignment.centerRight, child: UserChip()),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.byType(UserChip));
      await tester.pumpAndSettle();

      final popup = find.byWidgetPredicate((w) => w is PopupMenuItem);
      for (final icon in [
        Icons.settings_outlined,
        Icons.menu_book_outlined,
        Icons.keyboard_outlined,
        Icons.info_outline,
        Icons.palette_outlined,
      ]) {
        final widget = tester.widget<Icon>(
            find.descendant(of: popup, matching: find.byIcon(icon)));
        expect(widget.color, tc.menuIcon, reason: '$icon');
      }
      // the help entries stay (Python), without the caption
      expect(find.byKey(const ValueKey('user-menu-documentation')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('user-menu-shortcuts')), findsOneWidget);
      expect(find.byKey(const ValueKey('user-menu-about')), findsOneWidget);
      expect(find.descendant(of: popup, matching: find.text('Help')),
          findsNothing);
    });
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/auth/user_preferences_provider.dart';
import 'package:tryton_flutter_client/features/tabs/user_chip.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

/// The user chip in a narrow tab bar shortens the name, at last shows
/// only the avatar, instead of overflowing (window or menu resized).
void main() {
  testWidgets('no overflow at any width of the tab bar', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final errors = <String>[];
    for (var width = 700.0; width >= 200; width -= 5) {
      tester.view.physicalSize = Size(width, 200);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          preferencesProvider.overrideWith((ref) => {
                'status_bar': 'Administrator, Hausverwaltung Musterstadt GmbH',
              }),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // like AppShell._buildTabBar
          home: Scaffold(
            body: SizedBox(
              height: 40,
              child: Row(children: [
                const SizedBox(width: 40),
                const Expanded(child: SizedBox()),
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: math.max(0, (width - 44) / 2)),
                  child: const UserChip(),
                ),
                const SizedBox(width: 4),
              ]),
            ),
          ),
        ),
      ));
      final e = tester.takeException();
      if (e != null) errors.add('$width: $e');
      // wide: name shown; very narrow: only the avatar
      if (width == 700 || width == 200) {
        expect(find.byKey(const ValueKey('user-chip-name')),
            width == 700 ? findsOneWidget : findsNothing);
      }
      // at the right edge (before the 4 px gap)
      expect(tester.getRect(find.byType(UserChip)).right,
          closeTo(width - 4, 0.5), reason: 'width $width');
    }
    expect(errors, isEmpty);
  });
}

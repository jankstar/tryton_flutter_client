import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';
import 'package:tryton_flutter_client/features/shell/tab_strip.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

/// The tab strip of the shell: the active tab in view, mouse wheel,
/// "all tabs" button when not all fit.
void main() {
  List<AppTab> tabs(int n) => [
        for (var i = 0; i < n; i++)
          AppTab(
              id: 't$i',
              title: 'Menu / Tab number $i',
              attributes: const ScreenAttributes('party.party')),
      ];

  Future<(List<int>, List<int>)> pump(WidgetTester tester, int count,
      {int active = 0, double width = 500}) async {
    final activated = <int>[], closed = <int>[];
    tester.view.physicalSize = Size(width, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var list = tabs(count);
    var index = active;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => SizedBox(
            height: 40,
            child: TabStrip(
              tabs: list,
              activeIndex: index,
              onActivate: (i) {
                activated.add(i);
                set(() => index = i);
              },
              onClose: (i) {
                closed.add(i);
                set(() => list = [...list]..removeAt(i));
              },
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return (activated, closed);
  }

  Rect chip(WidgetTester tester, int i) =>
      tester.getRect(find.widgetWithText(InputChip, 'Tab number $i'));

  testWidgets('few tabs: no "all tabs" button', (tester) async {
    await pump(tester, 2);
    expect(find.byKey(const ValueKey('tabs-all')), findsNothing);
  });

  testWidgets('many tabs: the active one is scrolled into view; the button '
      'lists all tabs, a click activates, × closes', (tester) async {
    final (activated, closed) = await pump(tester, 15, active: 14);
    final button = find.byKey(const ValueKey('tabs-all'));
    expect(button, findsOneWidget);
    expect(chip(tester, 14).right, lessThanOrEqualTo(tester.getRect(button).left),
        reason: 'last tab visible left of the button');

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tabs-all-3')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tabs-all-3')));
    await tester.pumpAndSettle();
    expect(activated, [3]);
    expect(chip(tester, 3).left, greaterThanOrEqualTo(0),
        reason: 'scrolled back to tab 3');

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tabs-all-close-5')));
    await tester.pumpAndSettle();
    expect(closed, [5]);
    expect(find.text('Tab number 5'), findsNothing);
  });

  testWidgets('the mouse wheel scrolls the strip', (tester) async {
    await pump(tester, 15);
    final before = chip(tester, 0).left;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final at = tester.getCenter(find.byKey(const ValueKey('tab-strip')));
    await tester.sendEventToBinding(pointer.hover(at));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pump();
    expect(chip(tester, 0).left, lessThan(before - 200));
  });
}

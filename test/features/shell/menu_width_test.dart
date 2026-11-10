import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/features/shell/menu_width.dart';

/// The divider between menu and tabs: drag, limits, saved like the
/// language and restored at the start.
void main() {
  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Row(children: [
            Consumer(
              builder: (context, ref, _) =>
                  SizedBox(width: ref.watch(menuWidthProvider)),
            ),
            const MenuResizeHandle(maxWidth: 500),
            const Expanded(child: SizedBox()),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  Finder handle() => find.byKey(const ValueKey('menu-resize'));

  testWidgets('the saved width is restored at the start', (tester) async {
    SharedPreferences.setMockInitialValues({MenuWidthNotifier.prefKey: 320.0});
    final container = await pump(tester);
    expect(container.read(menuWidthProvider), 320);
  });

  testWidgets('dragging changes and saves the width; limits; double click '
      'resets', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = await pump(tester);
    expect(container.read(menuWidthProvider), MenuWidthNotifier.defaultWidth);

    await tester.drag(handle(), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(container.read(menuWidthProvider), closeTo(350, 1));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(MenuWidthNotifier.prefKey), closeTo(350, 1));

    // at most the room the window allows, at least the minimum
    await tester.drag(handle(), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(container.read(menuWidthProvider), 500);
    await tester.drag(handle(), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(container.read(menuWidthProvider), MenuWidthNotifier.minWidth);

    await tester.tap(handle());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle());
    await tester.pumpAndSettle();
    expect(container.read(menuWidthProvider), MenuWidthNotifier.defaultWidth);
    expect(prefs.getDouble(MenuWidthNotifier.prefKey), MenuWidthNotifier.defaultWidth);
  });

  testWidgets('a shrinking window: the menu follows at once without '
      'overflow; opening and closing are animated', (tester) async {
    var open = true;
    late StateSetter update;
    Widget app(double window) => MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(builder: (context, set) {
              update = set;
              // like the AppShell: the menu at most window − 360
              final width = (window - 360).clamp(200.0, 600.0);
              return Row(children: [
                MenuSlot(
                    open: open,
                    width: width,
                    child: const ColoredBox(
                        key: ValueKey('menu'), color: Colors.blue)),
                const Expanded(child: SizedBox()),
              ]);
            }),
          ),
        );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (var window = 1000.0; window >= 560; window -= 7) {
      tester.view.physicalSize = Size(window, 600);
      await tester.pumpWidget(app(window));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: 'window $window');
      expect(tester.getSize(find.byType(MenuSlot)).width,
          (window - 360).clamp(200.0, 600.0));
    }
    update(() => open = false);
    await tester.pump(const Duration(milliseconds: 90));
    final half = tester.getSize(find.byType(MenuSlot)).width;
    expect(half, greaterThan(0), reason: 'animated');
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(MenuSlot)).width, 0);
  });
}

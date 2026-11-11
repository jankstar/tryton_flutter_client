import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/shared/widgets/shrink_to_fit.dart';

/// ShrinkToFit: normal layout while the width suffices, scaled down
/// below the minimum width (no overflow), taps still reach the child.
void main() {
  Future<int> pump(WidgetTester tester, double width) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: ShrinkToFit(
              child: OutlinedButton.icon(
                key: const ValueKey('button'),
                icon: const Icon(Icons.check),
                label: const Text('Confirm'),
                onPressed: () => pressed++,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('button')));
    await tester.pump();
    return pressed;
  }

  testWidgets('enough width: the button fills it, unscaled', (tester) async {
    expect(await pump(tester, 300), 1);
    expect(tester.getSize(find.byKey(const ValueKey('button'))).width, 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('too narrow: scaled down instead of overflowing, still '
      'tappable', (tester) async {
    expect(await pump(tester, 30), 1);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ShrinkToFit)).width, 30);
    // painted within the 30 px (scaled), laid out at its minimum width
    final rect = tester.getRect(find.byKey(const ValueKey('button')));
    expect(rect.width, lessThanOrEqualTo(30.01));
  });
}

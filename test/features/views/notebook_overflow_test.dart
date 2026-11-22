import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'form_harness.dart';

/// A notebook whose page tabs do not fit gets the „all pages“ button on
/// the right (like the shell's tab bar): it lists the pages, the active
/// one checked, and a choice shows that page.
void main() {
  const names = [
    'General',
    'Supplier',
    'Identifiers',
    'Banking',
    'Relations',
    'Accounting',
    'Stock',
    'Sale',
  ];
  FakeFormRpc server() => FakeFormRpc({
    'model.test.form.fields_view_get': (_) => formView(
      '<form><notebook>'
      '${[for (var i = 0; i < names.length; i++) '<page string="${names[i]}" id="p$i">'
            '<label name="f$i"/><field name="f$i"/></page>'].join()}'
      '</notebook></form>',
      {
        for (var i = 0; i < names.length; i++)
          'f$i': {'type': 'char', 'string': 'Field $i'},
      },
    ),
    'model.test.form.read': (_) => [
      {
        'id': 1,
        for (var i = 0; i < names.length; i++) 'f$i': 'value $i',
        '_timestamp': '1',
      },
    ],
    'model.ir.model.search_read': (_) => <dynamic>[],
    'model.ir.model.get_notification': (_) => <String, dynamic>{},
    'model.test.form.resources': (_) => <String, dynamic>{},
  });

  testWidgets('narrow: the button lists all pages, a choice shows it', (
    tester,
  ) async {
    await pumpForm(
      tester,
      server(),
      model: 'test.form',
      recordId: 1,
      size: const Size(420, 800),
    );
    final button = find.byKey(const ValueKey('notebook-all'));
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: button, matching: find.text('8')),
      findsOneWidget,
      reason: 'the number of pages',
    );

    await tester.tap(button);
    await tester.pumpAndSettle();
    for (var i = 0; i < names.length; i++) {
      expect(find.byKey(ValueKey('notebook-all-$i')), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('notebook-all-0')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
      reason: 'the active page checked',
    );

    await tester.tap(find.byKey(const ValueKey('notebook-all-7')));
    await tester.pumpAndSettle();
    expect(find.text('value 7'), findsOneWidget, reason: 'the last page');
    expect(find.text('value 0'), findsNothing);
    // its tab scrolled into view
    expect(find.widgetWithText(Tab, 'Sale').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide: all tabs fit, no button', (tester) async {
    await pumpForm(tester, server(), model: 'test.form', recordId: 1);
    expect(find.byKey(const ValueKey('notebook-all')), findsNothing);
    expect(find.text('Sale'), findsOneWidget);
  });
}

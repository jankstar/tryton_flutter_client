import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/views/record_menu.dart';

import 'form_harness.dart';

/// Narrow tabs hide toolbar buttons by level (SAO tab.js `hidden-xs`,
/// `hidden-sm`); their functions stay in the record menu at the title.
void main() {
  FakeFormRpc server() => FakeFormRpc({
        'model.test.form.fields_view_get': (_) => formView(
            '<form><field name="name"/></form>',
            {'name': {'type': 'char', 'string': 'Name'}}),
        'model.test.form.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'N$id', '_timestamp': '1'}
            ],
        'model.test.form.resources': (_) =>
            {'attachment_count': 0, 'note_count': 0, 'note_unread': 0},
        'model.test.form.view_toolbar_get': (_) => {
              'print': [
                {'id': 3, 'name': 'Label', 'type': 'ir.action.report'},
                {'id': 4, 'name': 'Letter', 'type': 'ir.action.report'},
              ],
            },
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  test('the highest level that leaves the title its width', () {
    final items = [
      for (var i = 0; i < 4; i++) const ToolbarSlot(0, SizedBox()),
      const ToolbarSlot(1, SizedBox(), slots: 2),
      const ToolbarSlot(2, SizedBox()),
      const ToolbarSlot(3, SizedBox()),
    ];
    double width(int slots) =>
        toolbarTitleWidth + slots * toolbarButtonWidth;
    expect(toolbarLevel(width(8), items), 3);
    expect(toolbarLevel(width(7), items), 2);
    expect(toolbarLevel(width(6), items), 1);
    expect(toolbarLevel(width(5), items), 0);
    expect(toolbarLevel(100, items), 0, reason: 'level 0 always');
  });

  bool shown(String tooltip) =>
      find.byTooltip(tooltip).hitTestable().evaluate().isNotEmpty;

  testWidgets('wide tab: all buttons', (tester) async {
    await pumpForm(tester, server(), model: 'test.form', recordId: 1);
    for (final t in ['Previous', 'Save', 'Duplicate', 'Reports', 'Close']) {
      expect(shown(t), isTrue, reason: t);
    }
    expect(find.byKey(const ValueKey('toolbar-hidden')), findsNothing);
  });

  testWidgets('narrow tab: only the main buttons; the record menu still '
      'opens the hidden print menu', (tester) async {
    await pumpForm(tester, server(),
        model: 'test.form', recordId: 1, size: const Size(420, 900));
    for (final t in ['Save', 'Reload', 'Close']) {
      expect(shown(t), isTrue, reason: t);
    }
    for (final t in ['Previous', 'Duplicate', 'Reports', 'Launch actions']) {
      expect(shown(t), isFalse, reason: t);
    }
    expect(tester.takeException(), isNull, reason: 'no overflow');

    await tester.tap(find.byKey(const ValueKey('record-title')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('record-menu-print')));
    await tester.pumpAndSettle();
    expect(find.text('Label'), findsOneWidget);
    expect(find.text('Letter'), findsOneWidget);
  });
}

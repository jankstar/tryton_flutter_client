import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/views/record_menu.dart';

import 'form_harness.dart';

/// Narrow tabs (decision 2026-11-22): the buttons leave the bar only at its
/// right end into a „⋯“ menu before Close (always shown), so no button
/// moves within the bar; compact buttons (40 px) in every theme; the title
/// is shortened first. The functions stay in the record menu at the title
/// as well.
void main() {
  const order = [
    'toolbar-switch',
    'toolbar-previous',
    'toolbar-position',
    'toolbar-next',
    'toolbar-new',
    'toolbar-save',
    'toolbar-reload',
    'toolbar-attach',
    'toolbar-note',
    'toolbar-chat',
    'toolbar-action',
    'toolbar-relate',
    'toolbar-print',
    'toolbar-email',
  ];

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

  test('as many from the left as fit beside „⋯“ and Close', () {
    final items = [
      for (var i = 0; i < 6; i++)
        const ToolbarSlot(SizedBox(),
            group: ToolbarGroup.records, actions: [RecordAction.reload]),
      const ToolbarSlot(SizedBox(), group: ToolbarGroup.close),
    ];
    final all = toolbarTitleWidth + toolbarWidth(items);
    expect(toolbarShown(all, items), 6, reason: 'everything fits');
    // one button less: the „⋯“ button needs a place as well
    expect(toolbarShown(all - 1, items), 4);
    expect(toolbarShown(0, items), 0, reason: 'Close and „⋯“ stay');
  });

  test('the position never stays without „next“', () {
    final items = [
      const ToolbarSlot(SizedBox(),
          group: ToolbarGroup.navigation, actions: [RecordAction.previous]),
      const ToolbarSlot(SizedBox(),
          group: ToolbarGroup.navigation, width: toolbarPositionWidth),
      const ToolbarSlot(SizedBox(),
          group: ToolbarGroup.navigation, actions: [RecordAction.next]),
      const ToolbarSlot(SizedBox(),
          group: ToolbarGroup.records, actions: [RecordAction.newRecord]),
      const ToolbarSlot(SizedBox(), group: ToolbarGroup.close),
    ];
    // room for previous and the position beside „⋯“ and Close, not for
    // next
    final width = toolbarTitleWidth +
        toolbarWidth([items[0], items[1], items[4]]) +
        toolbarButtonWidth +
        toolbarGroupGap;
    expect(toolbarWidth(items), greaterThan(width - toolbarTitleWidth),
        reason: 'not everything fits');
    expect(toolbarShown(width, items), 1, reason: 'previous only');
  });

  /// The `toolbar-*` buttons shown, from left to right.
  List<String> shown(WidgetTester tester) {
    final found = <(double, String)>[];
    for (final key in [...order, 'toolbar-more', 'toolbar-close']) {
      final f = find.byKey(ValueKey(key)).hitTestable();
      if (f.evaluate().isEmpty) continue;
      found.add((tester.getTopLeft(f.first).dx, key));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, key) in found) key];
  }

  testWidgets('wide tab: all buttons, compact (40 px), no „⋯“',
      (tester) async {
    await pumpForm(tester, server(), model: 'test.form', recordId: 1);
    expect(shown(tester), [...order, 'toolbar-close']);
    expect(find.byKey(const ValueKey('toolbar-more')), findsNothing);
    expect(
        tester
            .getSize(find.descendant(
                of: find.byKey(const ValueKey('toolbar-new')),
                matching: find.byType(IconButton)))
            .width,
        toolbarButtonWidth);
  });

  for (final (name, width) in [('medium', 700.0), ('narrow', 420.0)]) {
    testWidgets('$name tab: buttons leave only at the right end, „⋯“ before '
        'Close; the record menu still opens the hidden print menu',
        (tester) async {
      await pumpForm(tester, server(),
          model: 'test.form', recordId: 1, size: Size(width, 900));
      final bar = shown(tester);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(bar.sublist(bar.length - 2), ['toolbar-more', 'toolbar-close']);
      final kept = bar.sublist(0, bar.length - 2);
      expect(kept, order.sublist(0, kept.length),
          reason: 'a prefix of the bar: nothing from the middle is missing');
      expect(kept.length, lessThan(order.length));

      // the „⋯“ menu: the missing ones in the order of the bar
      await tester.tap(find.byKey(const ValueKey('toolbar-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('toolbar-more-print')), findsOneWidget);
      expect(find.byKey(const ValueKey('toolbar-more-email')), findsOneWidget);
      // the report menu opens from „⋯“ (its button stays offstage)
      await tester.tap(find.byKey(const ValueKey('toolbar-more-print')));
      await tester.pumpAndSettle();
      expect(find.text('Label'), findsNWidgets(2), reason: 'open and print');
      await tester.tapAt(const Offset(5, 500));
      await tester.pumpAndSettle();

      // and from the record menu at the title
      await tester.tap(find.byKey(const ValueKey('record-title')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('record-menu-print')));
      await tester.pumpAndSettle();
      expect(find.text('Letter'), findsNWidgets(2));
    });
  }
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';

import 'form_harness.dart';

/// The bar of SAO (`tab.js` `menu_def`), the same for list and form so no
/// button moves when switching: switch · previous · position · next |
/// new · save · reload | attachment · note · chat | action · relate ·
/// report · email | close. Copy, delete, logs and revisions are in the
/// record menu only.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  const expected = [
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
    'toolbar-close',
  ];

  FakeFormRpc server() => FakeFormRpc({
        'model.test.form.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'view_id': 2,
                'arch': '<tree><field name="name"/></tree>',
                'fields': {
                  'name': {'type': 'char', 'string': 'Name'}
                },
              }
            : formView('<form><label name="name"/><field name="name"/></form>',
                {'name': {'type': 'char', 'string': 'Name'}}),
        'model.test.form.search': (_) => [1, 2],
        'model.test.form.search_count': (_) => 2,
        'model.test.form.read': (p) => [
              for (final id in p[0] as List)
                {
                  'id': id,
                  'name': 'N$id',
                  'rec_name': 'N$id',
                  '_timestamp': '1',
                  '_write': true,
                  '_delete': true,
                }
            ],
        'model.test.form.resources': (_) =>
            {'attachment_count': 0, 'note_count': 0, 'note_unread': 0},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  /// The `toolbar-*` buttons from left to right.
  List<String> bar(WidgetTester tester) {
    final found = <(double, String)>[];
    for (final key in expected) {
      final f = find.byKey(ValueKey(key));
      if (f.evaluate().isEmpty) continue;
      found.add((tester.getTopLeft(f.first).dx, key));
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, key) in found) key];
  }

  testWidgets('list and form: the same buttons in the same order, the '
      'position between previous and next', (tester) async {
    await pumpScreen(tester, server(), const ScreenAttributes('test.form'),
        settle: false);
    await pumpFrames(tester, 20);
    expect(bar(tester), expected, reason: 'list');
    final listX = {
      for (final key in expected)
        key: tester.getTopLeft(find.byKey(ValueKey(key)).first).dx
    };

    // open the form (double click)
    await tester.tap(find.text('N1'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('N1'));
    await pumpFrames(tester, 20);
    expect(find.byKey(const ValueKey('list-column-menu')), findsNothing,
        reason: 'the form');
    expect(bar(tester), expected, reason: 'form');
    for (final key in ['toolbar-chat', 'toolbar-print', 'toolbar-close']) {
      expect(tester.getTopLeft(find.byKey(ValueKey(key)).first).dx, listX[key],
          reason: '$key keeps its place');
    }
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('toolbar-position')),
            matching: find.text('1/2')),
        findsOneWidget);

    // like SAO only in the record menu
    for (final tip in ['Duplicate', 'Delete', 'View logs', 'Revisions']) {
      expect(find.byTooltip(tip), findsNothing, reason: tip);
    }
  }, variant: desktop);

  testWidgets('chat: always shown, disabled for a model without chat; not '
      'in the record menu then', (tester) async {
    await pumpScreen(tester, server(), const ScreenAttributes('test.form'),
        settle: false);
    await pumpFrames(tester, 20);
    final chat = tester.widget<IconButton>(find.byKey(const ValueKey('chat-button')));
    expect(chat.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('record-title')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('record-menu-chat')), findsNothing);
  }, variant: desktop);

  testWidgets('previous / next in the list move the selection (SAO)',
      (tester) async {
    await pumpScreen(tester, server(), const ScreenAttributes('test.form'),
        settle: false);
    await pumpFrames(tester, 20);
    await tester.tap(find.text('N1'));
    await tester.pump(kDoubleTapTimeout);
    await pumpFrames(tester, 5);
    String position() => tester
        .widget<Text>(find.descendant(
            of: find.byKey(const ValueKey('toolbar-position')),
            matching: find.byType(Text)))
        .data!;
    expect(position(), '1/2');
    await tester.tap(find.byKey(const ValueKey('toolbar-next')));
    await pumpFrames(tester, 5);
    expect(position(), '2/2');
    await tester.tap(find.byKey(const ValueKey('toolbar-previous')));
    await pumpFrames(tester, 5);
    expect(position(), '1/2');
    expect(find.byKey(const ValueKey('list-column-menu')), findsOneWidget,
        reason: 'still the list');
  }, variant: desktop);
}

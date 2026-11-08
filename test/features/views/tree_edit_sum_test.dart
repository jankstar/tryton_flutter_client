import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

import 'form_harness.dart';

/// Editable lists edit one cell (Python list_gtk/editabletree.py), sums
/// are exact decimals with the digits of the currency (spec 9.3.4).
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  FakeFormRpc server(String arch, List<Map<String, dynamic>> rows,
          [Map<String, Object? Function(List<dynamic>)> extra = const {}]) =>
      FakeFormRpc({
        'model.test.line.fields_view_get': (p) => {
              'type': 'tree',
              'view_id': 9,
              'arch': arch,
              'fields': {
                'name': {'type': 'char', 'string': 'Name'},
                'note': {'type': 'char', 'string': 'Note', 'readonly': true},
                'amount': {
                  'type': 'numeric',
                  'string': 'Amount',
                  'digits': '"currency"'
                },
                'currency': {
                  'type': 'many2one',
                  'string': 'Currency',
                  'relation': 'test.currency'
                },
              },
            },
        'model.test.line.search': (_) => [for (final r in rows) r['id']],
        'model.test.line.search_count': (_) => rows.length,
        'model.test.line.read': (p) => [
              for (final id in p[0] as List)
                {
                  ...rows.firstWhere((r) => r['id'] == id),
                  'currency': 1,
                  'currency.': {'rec_name': 'EUR'},
                  '_timestamp': '1',
                  '_write': true,
                  '_delete': true,
                }
            ],
        'model.test.line.write': (_) => null,
        'model.test.line.default_get': (_) => <String, dynamic>{},
        'model.test.line.create': (_) => [99],
        'model.test.line.view_toolbar_get': (_) => <String, dynamic>{},
        'model.test.line.resources': (_) => <String, dynamic>{},
        'model.test.currency.get_digits': (_) => [16, 2],
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        ...extra,
      });

  final rows = [
    {'id': 1, 'name': 'A', 'note': 'n1', 'amount': const TrytonDecimal('0.1')},
    {'id': 2, 'name': 'B', 'note': 'n2', 'amount': const TrytonDecimal('0.2')},
  ];

  Future<void> pump(WidgetTester tester, FakeFormRpc rpc) => pumpScreen(
      tester, rpc, const ScreenAttributes('test.line', mode: ['tree']));

  Future<void> click(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key,
      {bool shift = false}) async {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
  }

  /// Keys of the shown cell editors (`edit-<id>-<column>`).
  List<String> editors(WidgetTester tester) => [
        for (final e in find
            .byWidgetPredicate((w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.startsWith('edit-'))
            .evaluate())
          (e.widget.key as ValueKey<String>).value
      ];

  String editorText(WidgetTester tester) => tester
      .widget<TextField>(find.descendant(
          of: find.byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith('edit-')),
          matching: find.byType(TextField)))
      .controller!
      .text;

  testWidgets('editable list: only the clicked cell is edited; Tab/Shift+Tab '
      'columns (readonly skipped), Down/Up rows, Enter beyond the first row '
      '(new_position 0) a new line', (tester) async {
    final rpc = server('<tree editable="1"><field name="name"/>'
        '<field name="note"/><field name="amount"/></tree>', rows);
    await pump(tester, rpc);
    await click(tester, 'A');
    expect(editors(tester), ['edit-1-name#0'], reason: 'one cell only');
    expect(find.text('n1'), findsOneWidget, reason: 'other cells show values');

    // a readonly cell: the row is the cursor row, nothing edited
    await click(tester, 'n1');
    expect(editors(tester), isEmpty);
    await click(tester, 'A');

    await key(tester, LogicalKeyboardKey.tab);
    expect(editors(tester), ['edit-1-amount#0'], reason: 'note is readonly');
    await key(tester, LogicalKeyboardKey.tab, shift: true);
    expect(editors(tester), ['edit-1-name#0']);

    await tester.enterText(find.descendant(
        of: find.byKey(const ValueKey('edit-1-name#0')),
        matching: find.byType(TextField)), 'A2');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(rpc.named('model.test.line.write').single.params, [
      [1],
      {'name': 'A2'}
    ], reason: 'leaving the row saves it (root list)');
    expect(editors(tester), ['edit-2-name#0'], reason: 'same column, next row');
    expect(editorText(tester), 'B');

    // root list: new_position 0 – Enter goes up (Python `_key_up`), above
    // the first row a new line
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(editors(tester), ['edit-1-name#0']);
    expect(rpc.named('model.test.line.default_get'), isEmpty);
    await key(tester, LogicalKeyboardKey.enter);
    expect(rpc.named('model.test.line.default_get'), hasLength(1),
        reason: 'a new line above the first row');
    final keys = editors(tester);
    expect(keys, hasLength(1));
    expect(keys.single, endsWith('-name#0'), reason: 'first editable column');
    expect(keys.single, isNot('edit-2-name#0'));
  }, variant: desktop);

  testWidgets('sum: exact decimals with the digits of the currency',
      (tester) async {
    final rpc = server(
        '<tree><field name="name"/><field name="amount" sum="1"/></tree>', rows);
    await pump(tester, rpc);
    await tester.pumpAndSettle();
    final sum = find.byKey(const ValueKey('sum-amount#0'));
    expect(tester.widget<Text>(sum).data, '0.30\n0.30',
        reason: '0.1 + 0.2 as Decimal, 2 digits of get_digits');
    expect(rpc.named('model.test.currency.get_digits'), isNotEmpty);
  }, variant: desktop);

  testWidgets('sum of a hidden optional column: no sum row (like Python/SAO); '
      'shown when the column is shown', (tester) async {
    final rpc = server(
        '<tree><field name="name"/><field name="amount" sum="1" optional="1"/>'
            '</tree>',
        rows,
        {'model.ir.ui.view_tree_optional.set_optional': (_) => null});
    await pump(tester, rpc);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('list-sum-row')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('list-column-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate(
        (w) => w is CheckedPopupMenuItem<String> && w.value == 'amount'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('list-sum-row')), findsOneWidget);
  }, variant: desktop);
}

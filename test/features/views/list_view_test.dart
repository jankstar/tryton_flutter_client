import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

import 'form_harness.dart';

/// List view (spec 9.3, E20–E23, E6).
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// A list of `test.line` with [arch]; [rows] are the records.
  FakeFormRpc server(String arch, Map<String, dynamic> fields,
          List<Map<String, dynamic>> rows,
          [Map<String, Object? Function(List<dynamic>)> extra = const {}]) =>
      FakeFormRpc({
        'model.test.line.fields_view_get': (p) => p[1] == 'tree'
            ? {'type': 'tree', 'view_id': 7, 'arch': arch, 'fields': fields}
            : {
                'type': 'form',
                'view_id': 8,
                'arch': '<form><field name="name"/></form>',
                'fields': fields,
              },
        'model.test.line.search': (_) => [for (final r in rows) r['id']],
        'model.test.line.search_count': (_) => rows.length,
        'model.test.line.read': (p) => [
              for (final id in p[0] as List)
                {
                  ...rows.firstWhere((r) => r['id'] == id),
                  '_timestamp': '1',
                  '_write': true,
                  '_delete': true,
                }
            ],
        'model.test.line.write': (_) => null,
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.line.resources': (_) => <String, dynamic>{},
        'model.test.line.view_toolbar_get': (_) => <String, dynamic>{},
        ...extra,
      });

  Future<void> pumpList(WidgetTester tester, FakeFormRpc rpc,
          {Map<String, dynamic> context = const {}}) =>
      pumpScreen(tester, rpc,
          ScreenAttributes('test.line', mode: const ['tree'], context: context),
          settle: false);

  Future<void> settle(WidgetTester tester) => pumpFrames(tester, 20);

  const nameAmount = {
    'name': {'type': 'char', 'string': 'Name', 'required': true},
    'amount': {'type': 'numeric', 'string': 'Amount', 'digits': '[16, 2]'},
  };
  final lines = [
    {'id': 1, 'name': 'A', 'amount': const TrytonDecimal('1.5')},
    {'id': 2, 'name': 'B', 'amount': const TrytonDecimal('2')},
    {'id': 3, 'name': 'C', 'amount': const TrytonDecimal('3.25')},
  ];

  testWidgets('sum row: selected and all loaded records', (tester) async {
    final rpc = server('<tree><field name="name"/>'
        '<field name="amount" sum="1"/></tree>', nameAmount, lines);
    await pumpList(tester, rpc);
    await settle(tester);
    expect(find.byKey(const ValueKey('list-sum-row')), findsOneWidget);
    final sum = find.byKey(const ValueKey('sum-amount#0'));
    expect(tester.widget<Text>(sum).data, '6.75\n6.75');
    // select row A (checkbox): selected / all
    final rowA = find.ancestor(of: find.text('A'), matching: find.byType(InkWell)).first;
    await tester.tap(find.descendant(of: rowA, matching: find.byType(Checkbox)));
    await settle(tester);
    expect(tester.widget<Text>(sum).data, '1.50\n6.75');
  });

  testWidgets('columns per occurrence, widget date/time, tree_invisible '
      'PYSON, optional column menu → set_optional', (tester) async {
    final rpc = server(
        '<tree><field name="name"/>'
            '<field name="created" widget="date" string="Date"/>'
            '<field name="created" widget="time" string="Hour"/>'
            '<field name="amount" tree_invisible="{&quot;__class__&quot;: '
            '&quot;Eval&quot;, &quot;v&quot;: &quot;hide_amount&quot;, '
            '&quot;d&quot;: false}"/>'
            '<field name="code" optional="1"/></tree>',
        {
          ...nameAmount,
          'created': {
            'type': 'timestamp',
            'string': 'Created',
            'format': '"%H:%M:%S.%f"'
          },
          'code': {'type': 'char', 'string': 'Code'},
        },
        [
          {
            'id': 1,
            'name': 'A',
            'amount': const TrytonDecimal('1'),
            'code': 'X1',
            'created': DateTime(2026, 11, 7, 9, 5, 3, 120),
          }
        ],
        {'model.ir.ui.view_tree_optional.set_optional': (_) => null});
    await pumpList(tester, rpc, context: {'hide_amount': true});
    await settle(tester);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Hour'), findsOneWidget);
    expect(find.text('11/07/26'), findsOneWidget, reason: 'date part (%x)');
    expect(find.text('09:05:03.120000'), findsOneWidget,
        reason: 'time part with fractions of seconds');
    expect(find.text('Amount'), findsNothing, reason: 'tree_invisible PYSON');
    expect(find.text('Code'), findsNothing, reason: 'optional="1" hidden');

    await tester.tap(find.byKey(const ValueKey('list-column-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'Code'));
    await tester.pumpAndSettle();
    expect(find.text('Code'), findsOneWidget);
    expect(find.text('X1'), findsOneWidget);
    expect(rpc.named('model.ir.ui.view_tree_optional.set_optional').single.params,
        [
          7,
          {'code': false}
        ]);
  });

  testWidgets('editable row: form widgets, validation when leaving, saved',
      (tester) async {
    final rpc = server('<tree editable="1"><field name="name"/>'
        '<field name="amount"/></tree>', nameAmount, lines);
    await pumpList(tester, rpc);
    await settle(tester);
    await tester.tap(find.text('A'));
    await settle(tester);
    // the row of A is edited with the form widgets
    final name = textFieldOf('Name');
    expect(tester.widget<TextField>(name).controller!.text, 'A');
    await tester.enterText(name, '');
    await tester.tap(find.text('B'));
    await settle(tester);
    // required name: the row keeps the cursor
    expect(find.byType(SnackBar), findsOneWidget);
    expect(textFieldOf('Name'), findsOneWidget);
    expect(rpc.named('model.test.line.write'), isEmpty);

    await tester.enterText(textFieldOf('Name'), 'A2');
    await tester.tap(find.text('B'));
    await settle(tester);
    expect(rpc.named('model.test.line.write').single.params, [
      [1],
      {'name': 'A2'}
    ]);
    // now B is edited
    expect(tester.widget<TextField>(textFieldOf('Name')).controller!.text, 'B');
  }, variant: desktop);

  testWidgets('drag and drop: set_sequence renumbers, saved with Save',
      (tester) async {
    final rpc = server(
        '<tree sequence="sequence"><field name="name"/></tree>',
        {
          'name': {'type': 'char', 'string': 'Name'},
          'sequence': {'type': 'integer', 'string': 'Sequence'},
        },
        [
          {'id': 1, 'name': 'A', 'sequence': 1},
          {'id': 2, 'name': 'B', 'sequence': 2},
          {'id': 3, 'name': 'C', 'sequence': 3},
        ]);
    await pumpList(tester, rpc);
    await settle(tester);
    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(3));
    // C to the top
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(2, 0);
    await settle(tester);
    final names = [
      for (final t in ['A', 'B', 'C']) tester.getTopLeft(find.text(t)).dy
    ];
    expect(names[2] < names[0] && names[0] < names[1], isTrue,
        reason: 'C, A, B');
    await tester.tap(find.byKey(const ValueKey('list-save')));
    await settle(tester);
    final writes = {
      for (final w in rpc.named('model.test.line.write'))
        for (var i = 0; i < w.params.length; i += 2)
          for (final id in w.params[i] as List) id: (w.params[i + 1] as Map)['sequence']
    };
    // Python set_sequence: only what the new order needs (C keeps 3)
    expect(writes, {1: 4, 2: 5});
  });

  testWidgets('copy selected rows (Ctrl+C): tab-separated', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final rpc = server('<tree><field name="name"/><field name="amount"/></tree>',
        nameAmount, lines);
    await pumpList(tester, rpc);
    await settle(tester);
    await tester.tap(find.text('A'));
    await settle(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(tester);
    expect(copied, 'A\t1.50');
  }, variant: desktop);

  testWidgets('tree state: selection restored (get), stored on close (set)',
      (tester) async {
    final rpc = server('<tree tree_state="1"><field name="name"/></tree>',
        nameAmount, lines, {
      'model.ir.ui.view_tree_state.get': (p) => ['[]', '[[2]]'],
      'model.ir.ui.view_tree_state.set': (_) => null,
    });
    await pumpList(tester, rpc);
    await settle(tester);
    final get = rpc.named('model.ir.ui.view_tree_state.get').single;
    expect(get.params, ['test.line', '[]', null]);
    final rowB = find.ancestor(of: find.text('B'), matching: find.byType(InkWell)).first;
    expect(
        tester
            .widget<Checkbox>(find.descendant(of: rowB, matching: find.byType(Checkbox)))
            .value,
        isTrue);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(rpc.named('model.ir.ui.view_tree_state.set').single.params, [
      'test.line',
      '[]',
      null,
      '[]',
      '[[2]]'
    ]);
  });

  testWidgets('column width: drag the header edge → set_width',
      (tester) async {
    final rpc = server('<tree><field name="name"/><field name="amount"/></tree>',
        nameAmount, lines, {
      'model.ir.ui.view_tree_width.set_width': (_) => null,
    });
    await pumpList(tester, rpc);
    await settle(tester);
    final header = find.byKey(const ValueKey('header-name#0'));
    final before = tester.getSize(header).width;
    final edge = tester.getTopRight(header) + const Offset(-3, 20);
    await tester.dragFrom(edge, const Offset(60, 0));
    await settle(tester);
    expect(tester.getSize(header).width, greaterThan(before + 30));
    final call = rpc.named('model.ir.ui.view_tree_width.set_width').single;
    expect(call.params[0], 'test.line');
    final widths = call.params[1] as Map;
    expect((widths['name'] as List).single, greaterThan(before.round()));
    expect(widths['amount'], [null], reason: 'last column not stored');
  });
}

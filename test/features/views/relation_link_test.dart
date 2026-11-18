import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';
import 'package:tryton_flutter_client/features/views/record_form.dart';
import 'package:tryton_flutter_client/features/views/tree_view.dart';

import 'form_harness.dart';

/// Issue #4: many2one and reference values of non-editable lists are links
/// that open the record in a new tab (SAO `Many2OneColumn` /
/// `ReferenceColumn`).
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);
  const full = {'read': 1, 'write': 1, 'create': 1, 'delete': 1};

  const fields = {
    'name': {'type': 'char', 'string': 'Name'},
    'party': {
      'type': 'many2one',
      'string': 'Party',
      'relation': 'test.party',
      'context': '{"party_ctx": 1}',
    },
    'secret': {
      'type': 'many2one',
      'string': 'Secret',
      'relation': 'test.secret',
    },
    'contract': {
      'type': 'reference',
      'string': 'Document',
      'selection': [
        ['test.contract', 'Contract']
      ],
    },
  };

  FakeFormRpc server({bool editable = false}) => FakeFormRpc({
        'model.ir.model.list_models': (_) =>
            ['test.occ', 'test.party', 'test.secret', 'test.contract'],
        'model.ir.model.access.get_access': (p) => {
              for (final m in p[0] as List)
                m: m == 'test.secret'
                    ? {'read': 0, 'write': 0, 'create': 0, 'delete': 0}
                    : full,
            },
        'model.test.occ.fields_view_get': (p) => p[1] == 'form'
            ? formView('<form><field name="name"/></form>', fields)
            : {
                'type': 'tree',
                'view_id': 3,
                'arch': '<tree${editable ? ' editable="1"' : ''}>'
                    '<field name="name"/>'
                    '<field name="party" view_ids="10,11,12"/>'
                    '<field name="secret"/><field name="contract"/></tree>',
                'fields': fields,
              },
        'model.test.occ.search': (_) => [1, 2],
        'model.test.occ.search_count': (_) => 2,
        'model.test.occ.read': (p) => [
              for (final id in p[0] as List)
                id == 1
                    ? {
                        'id': 1,
                        'name': 'Occ 1',
                        'party': 5,
                        'party.': {'rec_name': 'P5'},
                        'secret': 7,
                        'secret.': {'rec_name': 'S7'},
                        'contract': 'test.contract,3',
                        'contract.': {'rec_name': 'C3'},
                        '_timestamp': '1',
                      }
                    : {
                        'id': 2,
                        'name': 'Occ 2',
                        'party': null,
                        'secret': null,
                        'contract': null,
                        '_timestamp': '1',
                      },
            ],
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  Future<FakeFormRpc> pumpList(WidgetTester tester, {bool editable = false}) async {
    final rpc = server(editable: editable);
    await pumpScreen(tester, rpc, const ScreenAttributes('test.occ', mode: ['tree', 'form']),
        metadata: true);
    return rpc;
  }

  List<AppTab> tabs(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(TreeView)))
          .read(tabsProvider)
          .tabs;

  // single taps of the rows wait for the double tap timeout
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  Finder link(String key) => find.byKey(ValueKey(key));

  bool selected(WidgetTester tester, int row) {
    final material = find
        .ancestor(of: find.text('Occ ${row + 1}'), matching: find.byType(Material))
        .first;
    return tester
            .widget<Checkbox>(
                find.descendant(of: material, matching: find.byType(Checkbox)))
            .value ==
        true;
  }

  testWidgets('many2one: link with hand cursor; a click opens the tab like SAO',
      (tester) async {
    await pumpList(tester);
    expect(link('link-1-party#0'), findsOneWidget);
    final region = tester.widget<MouseRegion>(find
        .descendant(of: link('link-1-party#0'), matching: find.byType(MouseRegion))
        .first);
    expect(region.cursor, SystemMouseCursors.click);

    // underlined while hovered
    TextStyle? style() => tester
        .widget<Text>(find.descendant(of: link('link-1-party#0'), matching: find.text('P5')))
        .style;
    expect(style()?.decoration, isNot(TextDecoration.underline));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('P5')));
    await tester.pump();
    expect(style()?.decoration, TextDecoration.underline);
    expect(style()?.color,
        Theme.of(tester.element(find.text('P5'))).colorScheme.primary);

    await tester.tap(find.text('P5'));
    expect(tabs(tester), hasLength(1), reason: 'opened at once');
    await settle(tester);
    final tab = tabs(tester).single;
    expect(tab.title, 'Party');
    expect(tab.attributes.model, 'test.party');
    expect(tab.attributes.resId, 5);
    expect(tab.attributes.mode, ['form']);
    expect(tab.attributes.viewIds, [11, 12], reason: 'without the tree view');
    expect(tab.attributes.context['party_ctx'], 1);
    expect(selected(tester, 0), isFalse, reason: 'the row is not selected');
  }, variant: desktop);

  testWidgets('double click on the link does not open the row', (tester) async {
    await pumpList(tester);
    await tester.tap(find.text('P5'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('P5'));
    await settle(tester);
    expect(find.byType(RecordForm), findsNothing);
    expect(tabs(tester), hasLength(1));
    expect(selected(tester, 0), isFalse);

    // beside the link the row behaves as before: double click opens it
    await tester.tap(find.text('Occ 1'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Occ 1'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordForm), findsOneWidget);
  }, variant: desktop);

  testWidgets('a click beside the link selects the row', (tester) async {
    await pumpList(tester);
    final cell = tester.getRect(link('link-1-party#0'));
    await tester.tapAt(cell.centerRight + const Offset(30, 0));
    await settle(tester);
    expect(selected(tester, 0), isTrue);
    expect(tabs(tester), isEmpty);
  }, variant: desktop);

  testWidgets('reference: model from the value, no view ids', (tester) async {
    await pumpList(tester);
    expect(link('link-1-contract#0'), findsOneWidget);
    await tester.tap(find.text('C3'));
    await tester.pumpAndSettle();
    final tab = tabs(tester).single;
    expect(tab.title, 'Document');
    expect(tab.attributes.model, 'test.contract');
    expect(tab.attributes.resId, 3);
    expect(tab.attributes.mode, ['form']);
    expect(tab.attributes.viewIds, isEmpty);
  }, variant: desktop);

  testWidgets('no link: empty value, no read right, editable list',
      (tester) async {
    await pumpList(tester);
    expect(find.text('S7'), findsOneWidget);
    expect(link('link-1-secret#0'), findsNothing, reason: 'no read right');
    expect(link('link-2-party#0'), findsNothing, reason: 'empty');
    expect(link('link-2-contract#0'), findsNothing, reason: 'empty');
    await tester.tap(find.text('S7'));
    await settle(tester);
    expect(selected(tester, 0), isTrue, reason: 'a plain cell');
    expect(tabs(tester), isEmpty);
  }, variant: desktop);

  testWidgets('editable list: no links', (tester) async {
    await pumpList(tester, editable: true);
    expect(find.text('P5'), findsOneWidget);
    expect(link('link-1-party#0'), findsNothing);
    expect(link('link-1-contract#0'), findsNothing);
  }, variant: desktop);

  testWidgets('touch: a tap on the link opens the record, not the row',
      (tester) async {
    await pumpList(tester);
    await tester.tap(find.text('P5'));
    await settle(tester);
    expect(tabs(tester).single.attributes.resId, 5);
    expect(find.byType(RecordForm), findsNothing);
    // beside it the tap does what it did before on touch: opens the row
    await tester.tap(find.text('Occ 1'));
    await settle(tester);
    expect(find.byType(RecordForm), findsOneWidget);
  });

  testWidgets('x2many list: links too', (tester) async {
    final rpc = FakeFormRpc({
      'model.test.form.fields_view_get': (_) => formView(
              '<form><field name="lines" colspan="4"/></form>', {
            'lines': {
              'type': 'one2many',
              'string': 'Lines',
              'relation': 'test.occ',
              'relation_field': 'parent'
            },
          }),
      'model.test.form.read': (_) => [
            {
              'id': 1,
              'lines': [1, 2],
              '_timestamp': '1'
            }
          ],
      ...server().handlers,
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1, metadata: true);
    expect(link('x2m-link-1-party#0'), findsOneWidget);
    expect(link('x2m-link-2-party#0'), findsNothing);
    await tester.tap(find.text('P5'));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(RecordForm).first));
    expect(container.read(tabsProvider).tabs.single.attributes.resId, 5);
  }, variant: desktop);
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

import 'form_harness.dart';

/// The common tree view of main and x2many lists (spec 9.2.7, 9.3.4):
/// editable x2many rows with sums, context menu, paste, `add_remove`.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// Clipboard of the platform channel with [text] (pasted).
  void clipboard(WidgetTester tester, String text) {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': text};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, buttons: kSecondaryButton);
    await tester.pumpAndSettle();
  }

  testWidgets('x2many: editable row and sums inside the form, saved by the '
      'parent as write command', (tester) async {
    final rpc = FakeFormRpc({
      'model.test.form.fields_view_get': (_) => formView(
          '<form><field name="lines"/></form>', {
            'lines': {
              'type': 'one2many',
              'string': 'Lines',
              'relation': 'test.line',
              'relation_field': 'move',
            },
          }),
      'model.test.form.read': (p) => [
            {
              'id': 1,
              '_timestamp': '1',
              'lines': [11, 12]
            }
          ],
      'model.test.form.write': (_) => null,
      'model.test.line.fields_view_get': (p) => {
            'type': 'tree',
            'arch': '<tree editable="1"><field name="name"/>'
                '<field name="debit" sum="1"/></tree>',
            'fields': {
              'name': {'type': 'char', 'string': 'Name'},
              'debit': {'type': 'numeric', 'string': 'Debit', 'digits': '[16, 2]'},
              'move': {'type': 'many2one', 'string': 'Move', 'relation': 'test.form'},
            },
          },
      'model.test.line.read': (p) => [
            for (final id in p[0] as List)
              {
                'id': id,
                'name': 'L$id',
                'debit': TrytonDecimal('${id - 10}.5'),
                '_timestamp': '1',
              }
          ],
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
      'model.test.form.resources': (_) => <String, dynamic>{},
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final sum = find.byKey(const ValueKey('x2m-sum-debit#0'));
    expect(tester.widget<Text>(sum).data, '4.00\n4.00', reason: '1.5 + 2.5');
    // the column menu of the main list in the form too
    expect(find.byKey(const ValueKey('x2m-column-menu')), findsOneWidget);

    // a click on the debit cell edits only that cell (Python set_cursor)
    await tester.tap(find.text('1.50'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    final debit = textFieldOf('Debit');
    expect(debit, findsOneWidget);
    expect(find.byKey(const ValueKey('x2m-edit-11-name#0')), findsNothing,
        reason: 'only the clicked cell');
    expect(find.byKey(const ValueKey('x2m-edit-11-debit#0')), findsOneWidget);
    await tester.enterText(debit, '4');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(sum).data, '4.00\n6.50', reason: 'selected / all');

    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
    final write = rpc.named('model.test.form.write').single.params;
    // like Python One2Many.get: a changed record is added and written
    final commands = (write[1] as Map)['lines'] as List;
    expect(commands[0], [
      'add',
      [11]
    ]);
    expect(commands[1][0], 'write');
    expect(commands[1][1], [11]);
    expect('${(commands[1][2] as Map)['debit']}', startsWith('4'));
  }, variant: desktop);

  /// A list of `test.line` (name, partner, amount) with [arch].
  FakeFormRpc listServer(String arch, List<Map<String, dynamic>> rows,
          [Map<String, Object? Function(List<dynamic>)> extra = const {}]) =>
      FakeFormRpc({
        'model.test.line.fields_view_get': (p) => {
              'type': 'tree',
              'view_id': 7,
              'arch': arch,
              'fields': {
                'name': {'type': 'char', 'string': 'Name'},
                'partner': {
                  'type': 'many2one',
                  'string': 'Partner',
                  'relation': 'test.party'
                },
                'amount': {'type': 'numeric', 'string': 'Amount', 'digits': '[16, 2]'},
                'date': {'type': 'date', 'string': 'Date'},
              },
            },
        'model.test.line.search': (_) => [for (final r in rows) r['id']],
        'model.test.line.search_count': (_) => rows.length,
        'model.test.line.read': (p) => [
              for (final id in p[0] as List)
                {
                  ...rows.firstWhere((r) => r['id'] == id),
                  'rec_name': 'Line $id',
                  '_timestamp': '1',
                  '_write': true,
                  '_delete': true,
                }
            ],
        'model.test.line.write': (_) => null,
        'model.test.line.view_toolbar_get': (_) => {
              'action': [
                {'id': 3, 'name': 'Check', 'type': 'ir.action.wizard'}
              ],
              'print': [
                {'id': 4, 'name': 'Label', 'type': 'ir.action.report'}
              ],
            },
        'model.test.party.view_toolbar_get': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.line.resources': (_) => <String, dynamic>{},
        ...extra,
      });

  final rows = [
    {'id': 1, 'name': 'A', 'partner': 5, 'partner.': {'rec_name': 'Acme'}, 'amount': const TrytonDecimal('1.5')},
    {'id': 2, 'name': 'B', 'partner': null, 'amount': const TrytonDecimal('2')},
  ];

  testWidgets('context menu: copy cell/row, record functions with the '
      'submenus of view_toolbar_get, submenu of the many2one column; '
      'several rows: copy column/rows', (tester) async {
    final clip = <String?>[];
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clip.add((call.arguments as Map)['text'] as String?);
      }
      return null;
    });
    final rpc = listServer('<tree><field name="name"/><field name="partner"/>'
        '<field name="amount"/></tree>', rows);
    await pumpScreen(tester, rpc,
        const ScreenAttributes('test.line', mode: ['tree']));
    await rightClick(tester, find.text('A'));
    for (final key in [
      'ctx-copy', 'ctx-copy-row', 'ctx-logs', 'ctx-attachments', 'ctx-notes',
      'ctx-action', 'ctx-relate', 'ctx-report', 'ctx-print', 'ctx-email',
      'ctx-column-partner#0',
    ]) {
      expect(find.byKey(ValueKey(key)), findsWidgets, reason: key);
    }
    expect(find.byKey(const ValueKey('ctx-paste')), findsNothing,
        reason: 'not editable');
    expect(find.byKey(const ValueKey('ctx-copy-rows')), findsNothing);
    MenuItemButton entry(String key) =>
        tester.widget<MenuItemButton>(find.byKey(ValueKey(key)).first);
    expect(entry('ctx-relate').onPressed, isNull, reason: 'no relate action');
    expect(entry('ctx-email').onPressed, isNull);
    expect(find.byType(SubmenuButton), findsNWidgets(4),
        reason: 'actions, report, print, column partner');
    expect(rpc.named('model.test.line.view_toolbar_get'), isNotEmpty);
    expect(rpc.named('model.test.party.view_toolbar_get'), isNotEmpty,
        reason: 'toolbar of the linked record');

    // Actions ▸ lists the action of the model
    await tester.tap(find.byKey(const ValueKey('ctx-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ctx-action-3')), findsOneWidget);
    // the partner submenu: Edit… for the linked record
    await tester.tap(find.byKey(const ValueKey('ctx-column-partner#0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ctx-edit')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ctx-copy-row')));
    await tester.pumpAndSettle();
    expect(clip.last, 'A\tAcme\t1.50');

    // the cell of the clicked column
    await rightClick(tester, find.text('Acme'));
    await tester.tap(find.byKey(const ValueKey('ctx-copy')));
    await tester.pumpAndSettle();
    expect(clip.last, 'Acme');

    // two rows selected: column and rows, no record functions
    // the checkbox reacts at once (not held by the row's double tap)
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pump();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(2)).value, isTrue);
    await tester.pumpAndSettle();
    await rightClick(tester, find.text('Acme'));
    expect(find.byKey(const ValueKey('ctx-copy-column')), findsOneWidget);
    expect(find.byKey(const ValueKey('ctx-copy-rows')), findsOneWidget);
    expect(find.byKey(const ValueKey('ctx-copy')), findsNothing);
    expect(find.byKey(const ValueKey('ctx-logs')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ctx-copy-column')));
    await tester.pumpAndSettle();
    // Python csv: a row of one empty field is written as ""
    expect(clip.last, 'Acme\n""\n');
  }, variant: desktop);

  testWidgets('paste rows (editable list): from the current record on, '
      'values converted, many2one by search, new rows created', (tester) async {
    // A (current), B (next) are overwritten, the third line is new
    clipboard(tester, 'A2\t2.5\t01/02/26\tAcme\nB2\t3\t\tZed\nC\t4\n');
    final rpc = listServer(
        '<tree editable="1"><field name="name"/><field name="amount"/>'
            '<field name="date"/><field name="partner"/></tree>',
        [
          {'id': 1, 'name': 'A', 'partner': null, 'amount': const TrytonDecimal('1.5')},
          {'id': 2, 'name': 'B', 'partner': null, 'amount': const TrytonDecimal('2')},
        ],
        {
          'model.test.party.search_read': (p) =>
              '${p[0]}'.contains('Acme')
                  ? [
                      {'id': 5, 'rec_name': 'Acme'}
                    ]
                  : [
                      {'id': 6, 'rec_name': 'Zed 1'},
                      {'id': 7, 'rec_name': 'Zed 2'}
                    ],
          'model.test.line.default_get': (_) => <String, dynamic>{},
          'model.test.line.create': (p) => [3],
        });
    await pumpScreen(tester, rpc,
        const ScreenAttributes('test.line', mode: ['tree']));
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    // right click on the selection column of the edited row
    await rightClick(tester, find.byType(Checkbox).at(1));
    expect(find.byKey(const ValueKey('ctx-paste')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ctx-paste')));
    await tester.pumpAndSettle();

    final writes = {
      for (final w in rpc.named('model.test.line.write'))
        (w.params[0] as List).single: w.params[1] as Map
    };
    expect(writes.keys, [1, 2], reason: 'each row saved (root list)');
    expect(writes[1]!['name'], 'A2');
    expect('${writes[1]!['amount']}', '2.5', reason: 'DomainParser conversion');
    expect(writes[1]!['date'], const TrytonDate(2026, 1, 2));
    expect(writes[1]!['partner'], 5, reason: 'one hit of rec_name ilike');
    expect('${rpc.named('model.test.party.search_read').first.params[0]}',
        contains('%Acme%'));
    expect(writes[2]!['name'], 'B2');
    expect(writes[2]!.containsKey('partner'), isFalse,
        reason: 'two hits: no value (unchanged empty)');

    expect(rpc.named('model.test.line.default_get'), hasLength(1));
    final created = (rpc.named('model.test.line.create').single.params[0] as List)
        .single as Map;
    expect(created['name'], 'C');
    expect('${created['amount']}', '4');
  }, variant: desktop);

  testWidgets('context menu of an x2many row: no record functions while the '
      'parent is modified', (tester) async {
    final rpc = FakeFormRpc({
      'model.test.form.fields_view_get': (_) => formView(
          '<form><field name="name"/><field name="lines"/></form>', {
            'name': {'type': 'char', 'string': 'Name'},
            'lines': {
              'type': 'one2many',
              'string': 'Lines',
              'relation': 'test.line',
            },
          }),
      'model.test.form.read': (p) => [
            {'id': 1, '_timestamp': '1', 'name': 'F', 'lines': [11]}
          ],
      'model.test.line.fields_view_get': (p) => {
            'type': 'tree',
            'arch': '<tree><field name="name"/></tree>',
            'fields': {
              'name': {'type': 'char', 'string': 'Name'},
            },
          },
      'model.test.line.read': (p) => [
            for (final id in p[0] as List)
              {'id': id, 'name': 'L$id', '_timestamp': '1'}
          ],
      'model.test.line.view_toolbar_get': (_) => <String, dynamic>{},
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
      'model.test.form.resources': (_) => <String, dynamic>{},
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await rightClick(tester, find.text('L11'));
    expect(find.byKey(const ValueKey('ctx-logs')), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.enterText(textFieldOf('Name'), 'Changed');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await rightClick(tester, find.text('L11'));
    expect(find.byKey(const ValueKey('ctx-copy-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('ctx-logs')), findsNothing,
        reason: 'parent modified');
  }, variant: desktop);

  testWidgets('add_remove: the entry completes, the chosen record is added',
      (tester) async {
    final rpc = FakeFormRpc({
      'model.test.form.fields_view_get': (_) => formView(
          '<form><field name="tags"/></form>', {
            'tags': {
              'type': 'many2many',
              'string': 'Tags',
              'relation': 'test.tag',
              'add_remove': [
                ['active', '=', true]
              ],
            },
          }),
      'model.test.form.read': (p) => [
            {'id': 1, '_timestamp': '1', 'tags': <int>[]}
          ],
      'model.test.form.write': (_) => null,
      'model.test.tag.fields_view_get': (p) => {
            'type': 'tree',
            'arch': '<tree><field name="name"/></tree>',
            'fields': {
              'name': {'type': 'char', 'string': 'Name'},
            },
          },
      'model.test.tag.autocomplete': (p) => [
            {'id': 7, 'name': 'Blue'}
          ],
      'model.test.tag.read': (p) => [
            for (final id in p[0] as List) {'id': id, 'name': 'Blue'}
          ],
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
      'model.test.form.resources': (_) => <String, dynamic>{},
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final entry = find.byKey(const ValueKey('x2m-add-entry'));
    expect(entry, findsOneWidget);
    await tester.enterText(entry, 'Bl');
    await tester.pumpAndSettle();
    final complete = rpc.named('model.test.tag.autocomplete').last.params;
    expect(complete[0], 'Bl');
    expect('${complete[1]}', contains('active'), reason: 'add_remove domain');
    await tester.tap(find.text('Blue').last);
    await tester.pumpAndSettle();
    expect(find.text('Blue'), findsOneWidget, reason: 'row of the table');

    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
    expect(rpc.named('model.test.form.write').single.params[1], {
      'tags': [
        ['add', [7]]
      ]
    });
  }, variant: desktop);
}

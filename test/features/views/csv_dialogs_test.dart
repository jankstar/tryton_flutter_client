import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/shared/utils/file_actions.dart';

import 'form_harness.dart';

class _FakeFiles extends FileActions {
  List<PickedFile> picks = const [];
  final opened = <String>[];
  final written = <(String, List<int>)>[];

  @override
  Future<List<PickedFile>> pick({bool multiple = false, bool images = false}) async =>
      picks;

  @override
  Future<String> writeTemp(String name, List<int> bytes) async {
    written.add((name, bytes));
    return '/tmp/$name';
  }

  @override
  Future<void> open(String path) async => opened.add(path);
}

/// CSV export and import, predefined exports, revisions of a list
/// (spec 11.7–11.9, F9).
void main() {
  late _FakeFiles files;
  setUp(() => FileActions.instance = files = _FakeFiles());
  tearDown(() => FileActions.instance = FileActions());

  final formFields = {
    'name': {'type': 'char', 'string': 'Name'},
    'state': {
      'type': 'selection',
      'string': 'State',
      'selection': [
        ['draft', 'Draft']
      ]
    },
  };
  final allFields = {
    ...formFields,
    'party': {'type': 'many2one', 'string': 'Party', 'relation': 'test.party'},
    'lines': {'type': 'one2many', 'string': 'Lines', 'relation': 'test.line'},
    'total': {'type': 'numeric', 'string': 'Total', 'readonly': true},
    'id': {'type': 'integer', 'string': 'ID', 'readonly': true},
  };

  FakeFormRpc server(Map<String, Object? Function(List<dynamic>)> extra) =>
      FakeFormRpc({
        'model.test.form.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'view_id': 2,
                'arch': '<tree><field name="name"/></tree>',
                'fields': {'name': formFields['name']},
              }
            : formView('<form><field name="name"/><field name="state"/></form>',
                formFields),
        'model.test.form.read': (p) => [
              for (final id in p[0] as List)
                {
                  'id': id,
                  'name': 'N$id',
                  'state': 'draft',
                  'rec_name': 'N$id',
                  '_timestamp': '1',
                }
            ],
        'model.test.form.fields_get': (_) => allFields,
        'model.test.party.fields_get': (_) => {
              'name': {'type': 'char', 'string': 'Name'},
            },
        'model.test.line.fields_get': (_) => {
              'product': {'type': 'char', 'string': 'Product'},
            },
        'model.ir.lang.search_read': (_) => <dynamic>[],
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.form.resources': (_) => <String, dynamic>{},
        ...extra,
      });

  /// An entry of the record menu at the title (spec 10.3).
  Future<void> openMenu(WidgetTester tester, String entry) async {
    await tester.tap(find.byKey(const ValueKey('record-title')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(entry)));
    await tester.pumpAndSettle();
  }

  testWidgets('export: fields of the view, relation expanded, Open writes '
      'the CSV, Save Export stores a predefined export', (tester) async {
    final rpc = server({
      'model.ir.export.get': (_) => <dynamic>[],
      'model.ir.export.set': (_) => 42,
      'model.test.form.export_data': (p) => [
            ['Name', 'State', 'Party/Name'],
            ['N1', 'Draft', 'Acme, Inc.'],
          ],
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await openMenu(tester, 'record-menu-export');
    expect(find.byKey(const ValueKey('csv-export-dialog')), findsOneWidget);
    expect(rpc.named('model.ir.export.get').single.params[0], 'test.form');
    // the fields of the form view (selection as text)
    final selected = find.byKey(const ValueKey('csv-selected-fields'));
    expect(find.descendant(of: selected, matching: find.text('Name')), findsOneWidget);
    expect(find.descendant(of: selected, matching: find.text('State (string)')),
        findsOneWidget);
    // readonly fields are exported, relations expandable
    expect(find.byKey(const ValueKey('csv-field-total')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('csv-expand-party')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('csv-field-party/name')));
    // the row also has a double tap
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('csv-add')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: selected, matching: find.text('Party/Name')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('csv-open')));
    await tester.pumpAndSettle();
    // form: the current record is "selected"
    expect(rpc.named('model.test.form.export_data').single.params, [
      [1],
      ['name', 'state.translated', 'party/name'],
      true,
    ]);
    final (name, bytes) = files.written.single;
    expect(name, 'form.csv');
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF], reason: 'utf_8_sig');
    expect(utf8.decode(bytes.skip(3).toList()),
        'Name,State,Party/Name\r\nN1,Draft,"Acme, Inc."\r\n');
    expect(files.opened, ['/tmp/form.csv']);

    await tester.tap(find.byKey(const ValueKey('csv-save-export')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('dialog-ask')), 'Quick');
    await tester.tap(find.byKey(const ValueKey('dialog-ok')));
    await tester.pumpAndSettle();
    expect(rpc.named('model.ir.export.set').single.params[0], {
      'header': true,
      'records': 'selected',
      'ignore_search_limit': false,
      'name': 'Quick',
      'resource': 'test.form',
      'export_fields': [
        {'name': 'name'},
        {'name': 'state.translated'},
        {'name': 'party/name'},
      ],
    });
    await tester.tap(find.byKey(const ValueKey('csv-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('csv-export-dialog')), findsNothing);
  });

  testWidgets('export: Copy URL puts the data URL of the export into the '
      'clipboard (spec 11.9)', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final rpc = server({'model.ir.export.get': (_) => <dynamic>[]});
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await openMenu(tester, 'record-menu-export');
    await tester.tap(find.byKey(const ValueKey('csv-header')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('csv-copy-url')));
    await tester.pumpAndSettle();
    // the form's record (selected), the fields of the view, no header
    // http on port 80: without port like the Python client
    expect(copied, startsWith('http://localhost/'));
    expect(
        copied,
        endsWith('/data/test.form?d=%5B1%5D&f=name&f=state.translated'
            '&enc=utf_8_sig&dl=%2C&qc=%22&h=0&loc=1'));
    expect(find.text('URL copied.'), findsOneWidget);
  });

  testWidgets('export: a predefined export sets fields and options',
      (tester) async {
    final rpc = server({
      'model.ir.export.get': (_) => [
            {
              'id': 7,
              'name': 'Lines',
              'header': false,
              'records': 'listed',
              'ignore_search_limit': true,
              'export_fields.': [
                {'id': 1, 'name': 'name'},
                {'id': 2, 'name': 'lines/product'},
              ],
            }
          ],
      'model.ir.export.update': (_) => null,
      'model.test.form.export_data_domain': (p) => [
            ['N1', 'x'],
          ],
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await openMenu(tester, 'record-menu-export');
    await tester.tap(find.byKey(const ValueKey('csv-predef-1-null')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lines').last);
    await tester.pumpAndSettle();
    final selected = find.byKey(const ValueKey('csv-selected-fields'));
    expect(find.descendant(of: selected, matching: find.text('Lines/Product')),
        findsOneWidget, reason: 'parent expanded for the path');
    expect(find.descendant(of: selected, matching: find.text('State (string)')),
        findsNothing);
    await tester.tap(find.byKey(const ValueKey('csv-open')));
    await tester.pumpAndSettle();
    final call = rpc.named('model.test.form.export_data_domain').single;
    expect(call.params[1], ['name', 'lines/product']);
    expect(call.params[2], 0, reason: 'search limit ignored: offset 0');
    expect(call.params[3], isNull, reason: 'no limit');
    expect(call.params[5], false, reason: 'no header');
    expect(utf8.decode(files.written.single.$2.skip(3).toList()), 'N1,x\r\n');

    await tester.tap(find.byKey(const ValueKey('csv-save-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dialog-ok')));
    await tester.pumpAndSettle();
    expect(rpc.named('model.ir.export.update').single.params, [
      7,
      {'header': false, 'records': 'listed', 'ignore_search_limit': true},
      ['name', 'lines/product'],
    ]);
  });

  testWidgets('import: Auto-Detect maps labels and paths, import_data with '
      'the rows after the header; unknown header', (tester) async {
    final rpc = server({
      'model.test.form.import_data': (p) => (p[1] as List).length,
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await openMenu(tester, 'record-menu-import');
    expect(find.byKey(const ValueKey('csv-import-dialog')), findsOneWidget);
    // only writable fields and id; only One2Many expandable
    expect(find.byKey(const ValueKey('csv-field-total')), findsNothing);
    expect(find.byKey(const ValueKey('csv-field-id')), findsOneWidget);
    expect(find.byKey(const ValueKey('csv-expand-party')), findsNothing);
    expect(find.byKey(const ValueKey('csv-expand-lines')), findsOneWidget);

    files.picks = [
      (
        name: 'data.csv',
        bytes: Uint8List.fromList(
            utf8.encode('Name,lines/product,Party\r\nA,x,P\r\n,y,\r\n'))
      )
    ];
    await tester.tap(find.byKey(const ValueKey('csv-import-pick')));
    await tester.pumpAndSettle();
    expect(find.text('data.csv'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('csv-autodetect')));
    await tester.pumpAndSettle();
    final selected = find.byKey(const ValueKey('csv-selected-fields'));
    expect(find.descendant(of: selected, matching: find.text('Lines/Product')),
        findsOneWidget, reason: 'technical path, parent expanded');
    expect(find.descendant(of: selected, matching: find.text('Party')),
        findsOneWidget, reason: 'label');
    final skip = tester.widget<TextField>(find.byKey(const ValueKey('csv-skip')));
    expect(skip.controller!.text, '1');

    await tester.tap(find.byKey(const ValueKey('csv-import')));
    await tester.pumpAndSettle();
    expect(rpc.named('model.test.form.import_data').single.params, [
      ['name', 'lines/product', 'party'],
      [
        ['A', 'x', 'P'],
        ['', 'y', ''],
      ],
    ]);
    expect(find.text('Records imported: 2'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('csv-import-dialog')), findsNothing);

    // unknown column header
    await openMenu(tester, 'record-menu-import');
    files.picks = [
      (name: 'bad.csv', bytes: Uint8List.fromList(utf8.encode('Name,Unknown\r\n')))
    ];
    await tester.tap(find.byKey(const ValueKey('csv-import-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('csv-autodetect')));
    await tester.pumpAndSettle();
    expect(find.text('Unknown column header "Unknown"'), findsOneWidget);
  });

  testWidgets('list: predefined export in the print menu, revisions of the '
      'selection', (tester) async {
    final rpc = server({
      'model.ir.model.list_models': (_) => ['test.form'],
      'model.ir.model.access.get_access': (p) => {
            for (final m in p[0] as List)
              m: {'read': 1, 'write': 1, 'create': 1, 'delete': 1}
          },
      'model.ir.model.list_history': (_) => ['test.form'],
      'model.test.form.search': (_) => [1, 2],
      'model.test.form.search_count': (_) => 2,
      'model.test.form.view_toolbar_get': (_) => {
            'exports': [
              {
                'id': 7,
                'name': 'Quick List',
                'header': true,
                'records': 'listed',
                'export_fields.': [
                  {'name': 'name'}
                ],
              }
            ],
          },
      'model.test.form.export_data': (p) => [
            ['Name'],
            for (final id in p[0] as List) ['N$id'],
          ],
      'model.test.form.history_revisions': (_) => [
            [DateTime(2026, 1, 2, 3, 4, 5), 1, 'Admin'],
          ],
    });
    await pumpScreen(tester, rpc, const ScreenAttributes('test.form', mode: ['tree']),
        metadata: true);
    await tester.tap(find.byIcon(Icons.open_in_new));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('export-7')));
    await tester.pumpAndSettle();
    expect(rpc.named('model.test.form.export_data').single.params, [
      [1, 2],
      ['name'],
      true,
    ]);
    expect(files.written.single.$1, 'quick-list.csv');
    expect(utf8.decode(files.written.single.$2), 'Name\r\nN1\r\nN2\r\n',
        reason: 'default parameters: utf-8 without BOM, ","');

    await tester.longPress(find.text('N1'));
    await tester.pumpAndSettle();
    await openMenu(tester, 'record-menu-revision');
    expect(rpc.named('model.test.form.history_revisions').single.params, [
      [1]
    ]);
    await tester.tap(find.textContaining('Admin'));
    await tester.pumpAndSettle();
    final search = rpc.named('model.test.form.search').last;
    expect(search.context['_datetime'], DateTime(2026, 1, 2, 3, 4, 5, 1));
    expect(find.textContaining(' @ '), findsOneWidget, reason: 'title');
  });
}

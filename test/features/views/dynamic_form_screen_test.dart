import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tryton_flutter_client/features/views/embedded_tree_widget.dart';

import 'form_harness.dart';

/// DynamicFormScreen on the data layer (D1) with a fake RPC.
void main() {
  const arch = '<form col="4">'
      '<label name="name"/><field name="name"/>'
      '<label name="code"/><field name="code"/>'
      '</form>';

  Map<String, Object? Function(List<dynamic>)> handlers({
    Map<String, dynamic> fields = const {},
    Map<String, dynamic> values = const {},
  }) =>
      {
        'model.test.form.fields_view_get': (_) => formView(arch, {
              'name': {
                'type': 'char',
                'string': 'Name',
                'on_change': ['name'],
              },
              'code': {'type': 'char', 'string': 'Code'},
              ...fields,
            }),
        'model.test.form.read': (p) => [
              {
                'id': 1,
                'name': 'Old',
                'code': '',
                'rec_name': 'Old',
                '_timestamp': '1.0',
                ...values,
              }
            ],
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => {
              'test.form': ['name']
            },
        'model.test.form.resources': (_) =>
            {'attachment_count': 2, 'note_count': 1, 'note_unread': 1},
      };

  testWidgets('changing a field runs on_change through the record',
      (tester) async {
    final rpc = FakeFormRpc({
      ...handlers(),
      'model.test.form.on_change_name': (p) => {'code': 'AUTO'},
      'model.test.form.on_change_notify': (p) => [
            ['warning', 'Check the code']
          ],
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    expect(find.text('Old'), findsOneWidget);

    await tester.enterText(textFieldOf('Name'), 'New');
    await tester.pump();
    // Text fields write on focus loss only.
    expect(rpc.named('model.test.form.on_change_name'), isEmpty);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    final call = rpc.named('model.test.form.on_change_name').single;
    expect(call.params, [
      {'name': 'New', 'id': 1}
    ]);
    expect(find.text('AUTO'), findsOneWidget);
    // on_change_notify message in the info bar above the form
    expect(find.text('Check the code'), findsOneWidget);
    // attachment/note badges from resources()
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
  });

  testWidgets('an empty required field blocks saving', (tester) async {
    final rpc = FakeFormRpc({
      ...handlers(fields: {
        'code': {'type': 'char', 'string': 'Code', 'required': true},
      }),
      'model.test.form.on_change_name': (p) => <String, dynamic>{},
      'model.test.form.write': (p) => null,
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);

    await tester.enterText(textFieldOf('Name'), 'New');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    expect(find.text('Record not valid'), findsOneWidget);
    expect(find.text('"Code" is required.'), findsOneWidget);
    expect(rpc.named('model.test.form.write'), isEmpty);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.enterText(textFieldOf('Code'), 'C1');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();

    final write = rpc.named('model.test.form.write').single;
    expect(write.params, [
      [1],
      {'name': 'New', 'code': 'C1'}
    ]);
    expect(write.context['_timestamp'], {'test.form,1': '1.0'});
  });

  testWidgets('a new child line is written as create command of the parent',
      (tester) async {
    const linesArch = '<form col="4">'
        '<label name="name"/><field name="name"/>'
        '<field name="lines" colspan="4"/>'
        '</form>';
    final lineFields = {
      'qty': {'type': 'float', 'string': 'Qty'},
      'parent': {'type': 'many2one', 'relation': 'test.form', 'string': 'Parent'},
    };
    final rpc = FakeFormRpc({
      ...handlers(values: {'lines': <int>[]}),
      'model.test.form.fields_view_get': (_) => formView(linesArch, {
            'name': {'type': 'char', 'string': 'Name'},
            'lines': {
              'type': 'one2many',
              'string': 'Lines',
              'relation': 'test.line',
              'relation_field': 'parent',
            },
          }),
      'model.test.line.fields_view_get': (p) => p[1] == 'tree'
          ? {
              'arch': '<tree><field name="qty"/></tree>',
              'fields': lineFields,
              'type': 'tree',
            }
          : formView('<form><label name="qty"/><field name="qty"/></form>',
              lineFields),
      'model.test.line.default_get': (_) => {'qty': 1.0},
      'model.test.form.write': (_) => null,
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);

    final list = find.byType(EmbeddedTreeWidget);
    await tester.tap(find.descendant(of: list, matching: find.byIcon(Icons.add)));
    await tester.pumpAndSettle();
    expect(rpc.named('model.test.line.default_get'), hasLength(1));

    await tester.enterText(textFieldOf('Qty'), '3');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    // back to the table: the new line is shown
    await tester.tap(find.descendant(of: list, matching: find.byIcon(Icons.arrow_back)));
    await tester.pumpAndSettle();
    expect(find.descendant(of: list, matching: find.byType(DataTable)), findsOneWidget);
    // The child is not saved on its own.
    expect(rpc.calls.where((c) => c.method.startsWith('model.test.line.') &&
        !c.method.endsWith('fields_view_get') && !c.method.endsWith('default_get')), isEmpty);

    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
    final write = rpc.named('model.test.form.write').single;
    expect(write.params, [
      [1],
      {
        'lines': [
          [
            'create',
            [
              {'qty': 3.0}
            ]
          ]
        ]
      }
    ]);
  });

  testWidgets('deleting a line only marks it; saved as delete command',
      (tester) async {
    const linesArch = '<form col="4">'
        '<label name="name"/><field name="name"/>'
        '<field name="lines" colspan="4"/>'
        '</form>';
    final lineFields = {
      'qty': {'type': 'float', 'string': 'Qty'},
      'parent': {'type': 'many2one', 'relation': 'test.form', 'string': 'Parent'},
    };
    final rpc = FakeFormRpc({
      ...handlers(values: {'lines': [10]}),
      'model.test.form.fields_view_get': (_) => formView(linesArch, {
            'name': {'type': 'char', 'string': 'Name'},
            'lines': {
              'type': 'one2many',
              'string': 'Lines',
              'relation': 'test.line',
              'relation_field': 'parent',
            },
          }),
      'model.test.line.fields_view_get': (p) => {
            'arch': '<tree><field name="qty"/></tree>',
            'fields': lineFields,
            'type': 'tree',
          },
      'model.test.line.read': (p) => [
            {'id': 10, 'qty': 7.0, '_timestamp': '10.0'}
          ],
      'model.test.form.write': (_) => null,
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1, settle: false);
    final list = find.byType(EmbeddedTreeWidget);
    // row loaded through the child record
    expect(find.text('7.00'), findsOneWidget);

    await tester.tap(find.descendant(of: list, matching: find.byType(Checkbox)).last);
    await pumpFrames(tester, 2);
    await tester.tap(find.descendant(of: list, matching: find.byIcon(Icons.delete_outline)));
    await pumpFrames(tester);
    expect(rpc.calls.where((c) => c.method == 'model.test.line.delete'), isEmpty);

    await tester.tap(find.byIcon(Icons.save));
    await pumpFrames(tester);
    final write = rpc.named('model.test.form.write').single;
    expect(write.params, [
      [1],
      {
        'lines': [
          ['delete', [10]]
        ]
      }
    ]);
    expect(write.context['_timestamp'],
        {'test.form,1': '1.0', 'test.line,10': '10.0'});
  });

  testWidgets('save prompt before reload: Cancel / No / Yes (10.4)',
      (tester) async {
    final rpc = FakeFormRpc({
      ...handlers(),
      'model.test.form.on_change_name': (p) => <String, dynamic>{},
      'model.test.form.write': (_) => null,
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    int reads() => rpc.named('model.test.form.read').length;

    Future<void> modifyAndReload(String answer) async {
      await tester.enterText(textFieldOf('Name'), 'Changed');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(find.textContaining('This record has been modified'), findsOneWidget);
      await tester.tap(find.text(answer));
      await tester.pumpAndSettle();
    }

    final initialReads = reads();
    await modifyAndReload('Cancel');
    expect(reads(), initialReads, reason: 'Cancel: stays, nothing reloaded');
    expect(find.text('Changed'), findsOneWidget);

    await modifyAndReload('No');
    expect(rpc.named('model.test.form.write'), isEmpty);
    expect(reads(), initialReads + 1, reason: 'No: changes discarded');
    expect(find.text('Old'), findsOneWidget);

    await modifyAndReload('Yes');
    expect(rpc.named('model.test.form.write').single.params, [
      [1],
      {'name': 'Changed'}
    ]);
    expect(reads(), greaterThan(initialReads + 1));
  });
}

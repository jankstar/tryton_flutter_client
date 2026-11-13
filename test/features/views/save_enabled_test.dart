import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'form_harness.dart';

/// Save is enabled at the first keystroke, not only when the input
/// writes its value on focus loss (Python `send_modified` →
/// `screen.modified()` with `view.modified`) – also in an inline x2many
/// form and a many2one; not in an editable list (Python
/// `ListView.modified` is false).
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  bool saveEnabled(WidgetTester tester) => tester
      .widget<IconButton>(find
          .ancestor(of: find.byTooltip('Save'), matching: find.byType(IconButton))
          .first)
      .onPressed !=
      null;

  FakeFormRpc server(String mode) => FakeFormRpc({
        'model.test.form.fields_view_get': (_) => formView(
                '<form><label name="name"/><field name="name"/>'
                '<label name="partner"/><field name="partner"/>'
                '<field name="lines" mode="$mode" colspan="4"/></form>', {
              'name': {'type': 'char', 'string': 'Name'},
              'partner': {
                'type': 'many2one',
                'string': 'Partner',
                'relation': 'test.partner'
              },
              'lines': {
                'type': 'one2many',
                'string': 'Lines',
                'relation': 'test.line'
              },
            }),
        'model.test.form.read': (_) => [
              {
                'id': 1,
                '_timestamp': '1',
                'name': 'N',
                'partner': null,
                'lines': [11]
              }
            ],
        'model.test.form.write': (_) => null,
        'model.test.line.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'arch': '<tree editable="1"><field name="desc"/></tree>',
                'fields': {
                  'desc': {'type': 'char', 'string': 'Desc'}
                },
              }
            : formView('<form><label name="desc"/><field name="desc"/></form>',
                {
                    'desc': {'type': 'char', 'string': 'Desc'}
                  }),
        'model.test.line.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'desc': 'L$id', '_timestamp': '1'}
            ],
        'model.test.line.view_toolbar_get': (_) => <String, dynamic>{},
        'model.test.partner.autocomplete': (_) => <dynamic>[],
        'model.test.form.resources': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  testWidgets('a field of the form: enabled while typing, disabled again '
      'when the old text is typed back', (tester) async {
    await pumpForm(tester, server('form'), model: 'test.form', recordId: 1);
    expect(saveEnabled(tester), isFalse);
    await tester.enterText(textFieldOf('Name'), 'Neu');
    await tester.pump();
    expect(saveEnabled(tester), isTrue);
    await tester.enterText(textFieldOf('Name'), 'N');
    await tester.pump();
    expect(saveEnabled(tester), isFalse, reason: 'the value of the record');
  }, variant: desktop);

  testWidgets('a field of an inline x2many form: enabled at once; Save '
      'writes the typed text', (tester) async {
    final rpc = server('form');
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.enterText(textFieldOf('Desc'), 'Neu');
    await tester.pump();
    expect(saveEnabled(tester), isTrue);
    await tester.enterText(textFieldOf('Desc'), 'L11');
    await tester.pump();
    expect(saveEnabled(tester), isFalse);

    await tester.enterText(textFieldOf('Desc'), 'Neu');
    await tester.pump();
    await tester.tap(find.byTooltip('Save'));
    await pumpFrames(tester, 20);
    final write = rpc.named('model.test.form.write').single;
    expect('${write.params[1]}', contains('Neu'),
        reason: 'the inline text without leaving the field');
    expect(saveEnabled(tester), isFalse, reason: 'saved');
  }, variant: desktop);

  testWidgets('a many2one with typed text: enabled at once', (tester) async {
    await pumpForm(tester, server('form'), model: 'test.form', recordId: 1);
    await tester.enterText(textFieldOf('Partner'), 'abc');
    await tester.pump();
    expect(saveEnabled(tester), isTrue);
  }, variant: desktop);

  testWidgets('a cell of an editable x2many list: only when the cell is '
      'left (like Python)', (tester) async {
    await pumpForm(tester, server('tree'), model: 'test.form', recordId: 1);
    await tester.tap(find.text('L11'));
    await pumpFrames(tester, 20);
    final cell = find.widgetWithText(TextField, 'L11');
    expect(cell, findsOneWidget, reason: 'the cell is edited');
    await tester.enterText(cell, 'Neu');
    await tester.pump();
    expect(saveEnabled(tester), isFalse);
  }, variant: desktop);
}

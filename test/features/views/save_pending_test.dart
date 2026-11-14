import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'form_harness.dart';

/// Saving right after typing (the focus still in the field) saves the
/// typed value and the result of its on_change with the first click –
/// like the Python client (`sig_save` → `set_value` of the views, then
/// the record's queue, then save; spec ABNAHME F02/D06).
///
/// The clicks are real mouse clicks: press, hold, release. The press
/// itself takes the focus from the field; Save must stay enabled while
/// the on_change runs, else the release is lost.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// A mouse click on [finder] that holds the button 120 ms.
  Future<void> click(WidgetTester tester, Finder finder) async {
    final gesture = await tester.startGesture(tester.getCenter(finder),
        kind: PointerDeviceKind.mouse);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up();
  }

  /// Parent `test.form` (name with on_change → code) with the lines
  /// [11] of `test.line` (desc with on_change → qty) shown as [mode];
  /// the on_change answers after 100 ms, the write after [writeDelay].
  FakeFormRpc server(String mode,
      {bool editable = false, int writeDelay = 0}) {
    const later = Duration(milliseconds: 100);
    final childFields = {
      'desc': {'type': 'char', 'string': 'Desc', 'on_change': ['desc']},
      'qty': {'type': 'integer', 'string': 'Qty'},
    };
    return FakeFormRpc({
      'model.test.form.fields_view_get': (_) => formView(
              '<form><label name="name"/><field name="name"/>'
              '<label name="code"/><field name="code"/>'
              '<field name="lines" mode="$mode" colspan="4"/></form>', {
            'name': {'type': 'char', 'string': 'Name', 'on_change': ['name']},
            'code': {'type': 'char', 'string': 'Code'},
            'lines': {
              'type': 'one2many',
              'string': 'Lines',
              'relation': 'test.line'
            },
          }),
      'model.test.form.read': (_) => [
            {'id': 1, '_timestamp': '1', 'name': 'N', 'code': '', 'lines': [11]}
          ],
      'model.test.form.on_change_name': (_) => Future<dynamic>.delayed(
          later, () => <String, dynamic>{'code': 'FROM-ON-CHANGE'}),
      'model.test.form.write': (_) => Future<dynamic>.delayed(
          Duration(milliseconds: writeDelay), () => null),
      'model.test.line.fields_view_get': (p) => p[1] == 'tree'
          ? {
              'type': 'tree',
              'arch': '<tree${editable ? ' editable="1"' : ''}>'
                  '<field name="desc"/><field name="qty"/></tree>',
              'fields': childFields,
            }
          : formView(
              '<form><label name="desc"/><field name="desc"/>'
              '<label name="qty"/><field name="qty"/></form>',
              childFields),
      'model.test.line.read': (p) => [
            for (final id in p[0] as List)
              {'id': id, 'desc': 'L$id', 'qty': 1, '_timestamp': '1'}
          ],
      'model.test.line.on_change_desc': (_) => Future<dynamic>.delayed(
          later, () => <String, dynamic>{'qty': 7}),
      'model.test.line.on_change_notify': (_) => <dynamic>[],
      'model.test.form.on_change_notify': (_) => <dynamic>[],
      'model.test.line.view_toolbar_get': (_) => <String, dynamic>{},
      'model.test.form.resources': (_) => <String, dynamic>{},
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
    });
  }

  Map<dynamic, dynamic> written(FakeFormRpc rpc) {
    final writes = rpc.named('model.test.form.write');
    expect(writes, hasLength(1), reason: 'saved once, with the first click');
    return writes.single.params[1] as Map;
  }

  testWidgets('inline form of a one2many: the typed value and its '
      'on_change result', (tester) async {
    final rpc = server('form');
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(textFieldOf('Desc'), kind: PointerDeviceKind.mouse);
    await tester.enterText(textFieldOf('Desc'), 'Neu');
    await tester.pump();
    await click(tester, find.byTooltip('Save'));
    await pumpFrames(tester, 20);
    final values = '${written(rpc)}';
    expect(values, contains('desc: Neu'));
    expect(values, contains('qty: 7'), reason: 'the on_change result');
  }, variant: desktop);

  testWidgets('editable row of a one2many list', (tester) async {
    final rpc = server('tree', editable: true);
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(find.text('L11'), kind: PointerDeviceKind.mouse);
    await pumpFrames(tester, 10);
    final cell = find.widgetWithText(TextField, 'L11');
    expect(cell, findsOneWidget, reason: 'the cell is edited');
    await tester.enterText(cell, 'Neu');
    await tester.pump();
    await click(tester, find.byTooltip('Save'));
    await pumpFrames(tester, 20);
    final values = '${written(rpc)}';
    expect(values, contains('desc: Neu'));
    expect(values, contains('qty: 7'), reason: 'the on_change result');
  }, variant: desktop);

  testWidgets('a field of the main form', (tester) async {
    final rpc = server('tree');
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(textFieldOf('Name'), kind: PointerDeviceKind.mouse);
    await tester.enterText(textFieldOf('Name'), 'Neu');
    await tester.pump();
    await click(tester, find.byTooltip('Save'));
    await pumpFrames(tester, 20);
    final values = written(rpc);
    expect(values['name'], 'Neu');
    expect(values['code'], 'FROM-ON-CHANGE', reason: 'the on_change result');
  }, variant: desktop);

  testWidgets('Cmd+S instead of the button', (tester) async {
    final rpc = server('form');
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(textFieldOf('Desc'), kind: PointerDeviceKind.mouse);
    await tester.enterText(textFieldOf('Desc'), 'Neu');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await pumpFrames(tester, 20);
    final values = '${written(rpc)}';
    expect(values, contains('desc: Neu'));
    expect(values, contains('qty: 7'));
  }, variant: desktop);

  testWidgets('a second click while saving writes nothing twice',
      (tester) async {
    final rpc = server('form', writeDelay: 300);
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(textFieldOf('Desc'), kind: PointerDeviceKind.mouse);
    await tester.enterText(textFieldOf('Desc'), 'Neu');
    await tester.pump();
    await click(tester, find.byTooltip('Save'));
    // the write is still running
    await click(tester, find.byTooltip('Save'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await pumpFrames(tester, 30);
    expect('${written(rpc)}', contains('desc: Neu'));
  }, variant: desktop);
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

import 'form_harness.dart';

/// The button at the end of a date field: the picker's day (today
/// preselected) is taken with OK – shown in the field and saved.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  FakeFormRpc server() => FakeFormRpc({
        'model.test.form.fields_view_get': (_) => formView(
            '<form><label name="name"/><field name="name"/>'
            '<label name="day"/><field name="day"/></form>',
            {
              'name': {'type': 'char', 'string': 'Name'},
              'day': {'type': 'date', 'string': 'Day'},
            }),
        'model.test.form.read': (_) => [
              {'id': 1, '_timestamp': '1', 'name': 'N', 'day': null}
            ],
        'model.test.form.write': (_) => null,
        'model.test.form.resources': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  testWidgets('OK in the date picker takes today and saves it', (tester) async {
    final rpc = server();
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final field = find.byKey(const ValueKey('date-day'));
    final input = find.descendant(of: field, matching: find.byType(TextField));
    expect(tester.widget<TextField>(input).controller!.text, '');

    await tester.tap(find.descendant(
        of: field, matching: find.byIcon(Icons.calendar_today)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final today = DateTime.now();
    expect(tester.widget<TextField>(input).controller!.text, isNotEmpty,
        reason: 'the picked day is shown');
    // leaving the field must not undo it
    await tester.tap(textFieldOf('Name'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, isNotEmpty);

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    final write = rpc.named('model.test.form.write').single;
    expect((write.params[1] as Map)['day'],
        TrytonDate(today.year, today.month, today.day));
  }, variant: desktop);

  testWidgets('editable list: OK in the date picker of a cell takes the day',
      (tester) async {
    final rpc = FakeFormRpc({
      'model.test.line.fields_view_get': (p) => {
            'type': 'tree',
            'view_id': 7,
            'arch': '<tree editable="1"><field name="name"/><field name="day"/></tree>',
            'fields': {
              'name': {'type': 'char', 'string': 'Name'},
              'day': {'type': 'date', 'string': 'Day'},
            },
          },
      'model.test.line.search': (_) => [1, 2],
      'model.test.line.search_count': (_) => 2,
      'model.test.line.read': (p) => [
            for (final id in p[0] as List)
              {'id': id, 'name': 'L$id', 'day': null, '_timestamp': '1',
               '_write': true, '_delete': true}
          ],
      'model.test.line.write': (_) => null,
      'model.test.line.resources': (_) => <String, dynamic>{},
      'model.test.line.view_toolbar_get': (_) => <String, dynamic>{},
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
    });
    await pumpScreen(tester, rpc,
        const ScreenAttributes('test.line', mode: ['tree']), settle: false);
    await pumpFrames(tester, 20);
    // click the (empty) day cell of the first row: it is edited
    final name = tester.getRect(find.text('L1'));
    final dayHeader = tester.getRect(find.text('Day'));
    await tester.tapAt(Offset(dayHeader.center.dx, name.center.dy));
    await pumpFrames(tester, 20);
    final icon = find.byIcon(Icons.calendar_today);
    expect(icon, findsOneWidget, reason: 'the cell is edited');
    await tester.tap(icon);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await pumpFrames(tester, 20);

    final today = DateTime.now();
    // leave the row: saved with the day
    await tester.tap(find.text('L2'));
    await pumpFrames(tester, 20);
    final writes = rpc.named('model.test.line.write');
    expect(writes, isNotEmpty, reason: 'the picked day is written');
    expect((writes.first.params[1] as Map)['day'],
        TrytonDate(today.year, today.month, today.day));
  }, variant: desktop);

  testWidgets('context form of a list: OK takes the day and searches with '
      'it', (tester) async {
    final rpc = FakeFormRpc({
      'model.test.ctx.fields_view_get': (_) => formView(
          '<form><label name="from_date"/><field name="from_date"/></form>',
          {'from_date': {'type': 'date', 'string': 'From'}}),
      'model.test.ctx.default_get': (_) => <String, dynamic>{},
      'model.test.line.fields_view_get': (_) => {
            'type': 'tree',
            'view_id': 7,
            'arch': '<tree><field name="name"/></tree>',
            'fields': {'name': {'type': 'char', 'string': 'Name'}},
          },
      'model.test.line.search': (_) => [1],
      'model.test.line.search_count': (_) => 1,
      'model.test.line.read': (p) => [
            for (final id in p[0] as List)
              {'id': id, 'name': 'L$id', '_timestamp': '1'}
          ],
      'model.test.line.view_toolbar_get': (_) => <String, dynamic>{},
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
    });
    await pumpScreen(tester, rpc,
        const ScreenAttributes('test.line',
            mode: ['tree'], contextModel: 'test.ctx'),
        settle: false);
    await pumpFrames(tester, 20);
    final field = find.byKey(const ValueKey('date-from_date'));
    final input = find.descendant(of: field, matching: find.byType(TextField));
    await tester.tap(find.descendant(
        of: field, matching: find.byIcon(Icons.calendar_today)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await pumpFrames(tester, 20);

    final today = DateTime.now();
    expect(tester.widget<TextField>(input).controller!.text, isNotEmpty,
        reason: 'the picked day is shown');
    expect(rpc.named('model.test.line.search').last.context['from_date'],
        TrytonDate(today.year, today.month, today.day));
  }, variant: desktop);

  testWidgets('with the cursor in the field (mouse): OK shows and keeps the '
      'day', (tester) async {
    final rpc = server();
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final field = find.byKey(const ValueKey('date-day'));
    final input = find.descendant(of: field, matching: find.byType(TextField));
    await tester.tap(input, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(
        find.descendant(of: field, matching: find.byIcon(Icons.calendar_today)),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, isNotEmpty,
        reason: 'the picked day is shown');
    await tester.tap(textFieldOf('Name'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, isNotEmpty,
        reason: 'still shown after leaving the field');
    await tester.tap(find.byTooltip('Save'), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    final today = DateTime.now();
    expect((rpc.named('model.test.form.write').single.params[1] as Map)['day'],
        TrytonDate(today.year, today.month, today.day));
  }, variant: desktop);
}

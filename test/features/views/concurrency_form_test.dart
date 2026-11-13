import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';

import 'form_harness.dart';

/// Saving a record changed meanwhile by someone else (Python
/// `process_exception` + `ConcurrencyDialog`): the dialog Cancel / Compare
/// / Write Anyway – not the error message of the form's error handler.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  FakeFormRpc server() {
    late FakeFormRpc rpc;
    rpc = FakeFormRpc({
      'model.test.form.fields_view_get': (_) => formView(
          '<form><label name="name"/><field name="name"/></form>',
          {'name': {'type': 'char', 'string': 'Name'}}),
      'model.test.form.read': (_) => [
            {'id': 1, '_timestamp': '1', 'name': 'Old', 'rec_name': 'Old'}
          ],
      // the record was written by someone else: with _timestamp a conflict
      'model.test.form.write': (_) {
        if (rpc.calls.last.context.containsKey('_timestamp')) {
          throw const ConcurrencyException();
        }
        return null;
      },
      'model.test.form.resources': (_) => <String, dynamic>{},
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
    });
    return rpc;
  }

  Future<void> editAndSave(WidgetTester tester) async {
    await tester.enterText(textFieldOf('Name'), 'Mine');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save'));
    await pumpFrames(tester, 20);
  }

  testWidgets('the concurrency dialog, Write Anyway writes without '
      '_timestamp', (tester) async {
    final rpc = server();
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await editAndSave(tester);
    expect(find.text('Concurrency Warning'), findsOneWidget);
    expect(find.byKey(const ValueKey('dialog-compare')), findsOneWidget);
    expect(find.text('Concurrency Exception'), findsNothing,
        reason: 'not the error message');

    await tester.tap(find.byKey(const ValueKey('dialog-write-anyway')));
    await pumpFrames(tester, 20);
    final writes = rpc.named('model.test.form.write');
    expect(writes, hasLength(2));
    expect(writes.first.context['_timestamp'], {'test.form,1': '1'});
    expect(writes.last.context.containsKey('_timestamp'), isFalse);
    expect((writes.last.params[1] as Map)['name'], 'Mine');
    expect(find.text('Concurrency Warning'), findsNothing);
  }, variant: desktop);

  testWidgets('Cancel: not written again, the change stays', (tester) async {
    final rpc = server();
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await editAndSave(tester);
    await tester.tap(find.byKey(const ValueKey('dialog-cancel')));
    await pumpFrames(tester, 20);
    expect(rpc.named('model.test.form.write'), hasLength(1));
    expect(tester.widget<TextField>(textFieldOf('Name')).controller!.text,
        'Mine');
  }, variant: desktop);
}

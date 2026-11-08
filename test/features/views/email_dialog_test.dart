import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/features/views/email_dialog.dart';
import 'package:tryton_flutter_client/shared/utils/file_actions.dart';

import 'form_harness.dart';

/// Email (spec 11.10, Python `Form.sig_email` + `Email`): template,
/// prefill, completion of the addresses, reports, attachments, files,
/// `ir.email.send`.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  FakeFormRpc server({List<Map<String, dynamic>> emails = const []}) =>
      FakeFormRpc({
        'model.test.form.fields_view_get': (_) => formView(
            '<form><field name="name"/></form>',
            {'name': {'type': 'char', 'string': 'Name'}}),
        'model.test.form.read': (p) => [
              {'id': 1, '_timestamp': '1', 'name': 'Order 1', 'rec_name': 'Order 1'}
            ],
        'model.test.form.view_toolbar_get': (_) => {
              'print': [
                {'id': 7, 'name': 'Invoice', 'type': 'ir.action.report'},
                {'id': 8, 'name': 'Wizard', 'type': 'ir.action.wizard'},
              ],
              'emails': emails,
            },
        'model.test.form.resources': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.ir.email.template.get': (_) => {
              'to': ['Ann <ann@example.com>'],
              'cc': <String>[],
              'subject': 'Your order',
              'body': '<b>Hello</b>',
              'reports': [7],
            },
        'model.ir.email.template.get_default': (_) => {
              'to': ['Bob <bob@example.com>'],
              'subject': '',
            },
        'model.ir.attachment.search_read': (_) => [
              {'id': 9, 'rec_name': 'terms.pdf'},
            ],
        'model.ir.email.complete': (p) => [
              [0.9, 'John <john@example.com>', 'John <john@example.com>'],
            ],
        'model.ir.email.send': (_) => 1,
      });

  Future<void> openEmail(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Email'));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) => tester
      .widget<TextField>(find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(TextField),
          matchRoot: true))
      .controller!
      .text;

  testWidgets('template: chosen (always asked), prefilled by '
      'ir.email.template.get; completion; send with reports, attachments and '
      'files', (tester) async {
    final rpc = server(emails: [
      {'id': 3, 'name': 'Order confirmation'},
    ]);
    final files = _FakeFiles();
    FileActions.instance = files;
    addTearDown(() => FileActions.instance = FileActions());
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await openEmail(tester);

    // one template: asked anyway (Python `alwaysask=True`)
    expect(find.text('Order confirmation'), findsOneWidget);
    await tester.tap(find.text('Order confirmation'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dialog-ok')));
    await tester.pumpAndSettle();

    expect(find.byType(EmailDialog), findsOneWidget);
    expect(rpc.named('model.ir.email.template.get').single.params, [3, 1]);
    expect(text(tester, 'email-to'), 'Ann <ann@example.com>');
    expect(text(tester, 'email-subject'), 'Your order');
    // the report of the template is checked, only reports are offered
    expect(tester.widget<FilterChip>(find.byKey(const ValueKey('email-report-7'))).selected,
        isTrue);
    expect(find.text('Wizard'), findsNothing);
    expect(find.text('terms.pdf'), findsOneWidget, reason: 'attachment');

    // completion of Cc: ir.email.complete(text, limit) after 300 ms
    final cc = find.descendant(
        of: find.byKey(const ValueKey('email-cc')), matching: find.byType(TextField));
    await tester.enterText(cc, 'jo');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(rpc.named('model.ir.email.complete').last.params[0], 'jo');
    await tester.tap(find.byKey(const ValueKey('email-completion-0')));
    await tester.pumpAndSettle();
    expect(text(tester, 'email-cc'), 'John <john@example.com>');

    await tester.tap(find.byKey(const ValueKey('email-attachment-9')));
    await tester.tap(find.byKey(const ValueKey('email-add-file')));
    await tester.pumpAndSettle();
    expect(find.text('note.txt'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('email-send')));
    await tester.pumpAndSettle();
    final send = rpc.named('model.ir.email.send').single.params;
    expect(send[0], 'Ann <ann@example.com>');
    expect(send[1], 'John <john@example.com>');
    expect(send[2], '');
    expect(send[3], 'Your order');
    expect(send[4], contains('Hello'));
    final file = (send[5] as List).single as List;
    expect(file[0], 'note.txt');
    expect((file[1] as TrytonBytes).bytes, [1, 2, 3]);
    expect(send[6], ['test.form', 1]);
    expect(send[7], [7]);
    expect(send[8], [9]);
    expect(find.byType(EmailDialog), findsNothing, reason: 'closed');
  }, variant: desktop);

  testWidgets('without template: get_default; To and subject are required',
      (tester) async {
    final rpc = server();
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await openEmail(tester);
    expect(rpc.named('model.ir.email.template.get_default').single.params,
        ['test.form', 1]);
    expect(text(tester, 'email-to'), 'Bob <bob@example.com>');
    await tester.tap(find.byKey(const ValueKey('email-send')));
    await tester.pumpAndSettle();
    expect(rpc.named('model.ir.email.send'), isEmpty, reason: 'no subject');
    expect(find.byType(EmailDialog), findsOneWidget);
  }, variant: desktop);

  testWidgets('a modified record: save prompt first', (tester) async {
    final rpc = server()..handlers['model.test.form.write'] = (_) => null;
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.enterText(textFieldOf('Name'), 'Changed');
    await tester.pump();
    await openEmail(tester);
    expect(find.byKey(const ValueKey('dialog-yes')), findsOneWidget,
        reason: 'Sur3');
    await tester.tap(find.byKey(const ValueKey('dialog-yes')));
    await tester.pumpAndSettle();
    expect(rpc.named('model.test.form.write'), hasLength(1));
    expect(find.byType(EmailDialog), findsOneWidget);
  }, variant: desktop);
}

class _FakeFiles extends FileActions {
  @override
  Future<List<PickedFile>> pick({bool multiple = false, bool images = false}) async =>
      [(name: 'note.txt', bytes: Uint8List.fromList([1, 2, 3]))];
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/views/record_form.dart';

import 'form_harness.dart';

/// Issue #5: the form popup (spec 11.1, Python `WinForm`) of a many2one
/// (Open) and of an x2many (open / new child): size and the activation
/// of its buttons.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);
  const full = {'read': 1, 'write': 1, 'create': 1, 'delete': 1};

  FakeFormRpc server([Map<String, Map<String, int>> access = const {}]) =>
      FakeFormRpc({
        'model.ir.model.list_models': (_) =>
            ['test.form', 'test.party', 'test.line'],
        'model.ir.model.access.get_access': (p) => {
              for (final m in p[0] as List) m: access[m] ?? full,
            },
        'model.test.form.fields_view_get': (_) => formView(
                '<form><label name="partner"/><field name="partner"/>'
                '<field name="lines" colspan="4"/></form>',
                {
                  'partner': {
                    'type': 'many2one',
                    'string': 'Partner',
                    'relation': 'test.party'
                  },
                  'lines': {
                    'type': 'one2many',
                    'string': 'Lines',
                    'relation': 'test.line',
                    'relation_field': 'parent'
                  },
                }),
        'model.test.form.read': (p) => [
              {
                'id': 1,
                'partner': 5,
                'partner.': {'rec_name': 'P5'},
                'lines': [11, 12],
                '_timestamp': '1'
              }
            ],
        'model.test.party.fields_view_get': (p) => formView(
                '<form><label name="name"/><field name="name"/>'
                '<button name="check" string="Check"/></form>',
                {
                  'name': {'type': 'char', 'string': 'Name'}
                }),
        'model.test.party.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'P$id', 'rec_name': 'P$id', '_timestamp': '1'}
            ],
        'model.test.party.check': (_) => null,
        'model.test.line.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'view_id': 40,
                'arch': '<tree><field name="name"/></tree>',
                'fields': {
                  'name': {'type': 'char', 'string': 'Name'}
                },
              }
            : formView('<form><label name="name"/><field name="name"/></form>', {
                'name': {'type': 'char', 'string': 'Name'}
              }),
        'model.test.line.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'L$id', '_timestamp': '1'}
            ],
        'model.test.line.default_get': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.form.resources': (_) => <String, dynamic>{},
      });

  Finder inDialog(Finder f) => find.descendant(of: find.byType(Dialog), matching: f);

  bool enabled(WidgetTester tester, Finder button) {
    final w = tester.widget(button);
    return w is ButtonStyleButton
        ? w.onPressed != null
        : (w as IconButton).onPressed != null;
  }

  bool footer(WidgetTester tester, String label) => enabled(
      tester,
      inDialog(find.ancestor(
              of: find.text(label),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)))
          .first);

  bool tool(WidgetTester tester, String key) =>
      enabled(tester, inDialog(find.byKey(ValueKey(key))));

  Future<void> openPartner(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('m2o-open-partner')));
    await tester.pumpAndSettle();
  }

  Future<void> openLine(WidgetTester tester, String name) async {
    // desktop: a double click opens the row
    await tester.tap(find.text(name));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  group('size', () {
    testWidgets('wide window: 90 % of the width, height of the content',
        (tester) async {
      await pumpForm(tester, server(), model: 'test.form', recordId: 1,
          metadata: true);
      await openPartner(tester);
      final frame = tester.getSize(find.byKey(const ValueKey('form-dialog-frame')));
      expect(frame.width, 1260, reason: '90 % of 1400 (was at most 960)');
      expect(frame.height, lessThan(900 * 0.5), reason: 'small form: low');
      expect(frame.height, lessThanOrEqualTo(900));
    }, variant: desktop);

    testWidgets('narrow window (< 600 px): full screen', (tester) async {
      await pumpForm(tester, server(), model: 'test.form', recordId: 1,
          metadata: true, size: const Size(500, 800));
      await openPartner(tester);
      expect(find.byKey(const ValueKey('form-dialog-frame')), findsNothing);
      expect(tester.getSize(find.byType(Dialog)), const Size(500, 800));
    }, variant: desktop);
  });

  group('many2one dialog (existing record)', () {
    testWidgets('with write right: Discard/Save and the form buttons work',
        (tester) async {
      final rpc = server();
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1,
          metadata: true);
      await openPartner(tester);
      expect(footer(tester, 'Discard changes'), isTrue);
      expect(footer(tester, 'Save'), isTrue);
      // no mini toolbar (Python: only for x2many)
      expect(find.byKey(const ValueKey('form-dialog-new')), findsNothing);
      // the <button> of the form was always disabled (no onButton)
      final check = inDialog(find.byType(RecordButton));
      expect(
          tester
              .widgetList<ButtonStyleButton>(find.descendant(
                  of: check, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)))
              .single
              .onPressed,
          isNotNull);
      await tester.tap(inDialog(find.text('Check')));
      await tester.pumpAndSettle();
      expect(rpc.named('model.test.party.check').single.params[0], [5]);
    }, variant: desktop);

    testWidgets('without write but with create right: Save stays (Python '
        'Group.readonly = no write and no create)', (tester) async {
      await pumpForm(
          tester,
          server({
            'test.party': {'read': 1, 'write': 0, 'create': 1, 'delete': 0}
          }),
          model: 'test.form',
          recordId: 1,
          metadata: true);
      await openPartner(tester);
      expect(footer(tester, 'Discard changes'), isTrue);
      expect(footer(tester, 'Save'), isTrue);
    }, variant: desktop);

    testWidgets('without write and create right: only Close, read only',
        (tester) async {
      await pumpForm(
          tester,
          server({
            'test.party': {'read': 1, 'write': 0, 'create': 0, 'delete': 0}
          }),
          model: 'test.form',
          recordId: 1,
          metadata: true);
      await openPartner(tester);
      expect(footer(tester, 'Close'), isTrue);
      expect(inDialog(find.text('Discard changes')), findsNothing);
      expect(inDialog(find.text('Save')), findsNothing);
      expect(tester.widget<TextField>(inDialog(find.byType(TextField))).readOnly,
          isTrue);
    }, variant: desktop);
  });

  group('x2many dialog', () {
    testWidgets('existing child: Next, New, Delete; Discard/Apply',
        (tester) async {
      await pumpForm(tester, server(), model: 'test.form', recordId: 1,
          metadata: true);
      await openLine(tester, 'L11');
      expect(tool(tester, 'form-dialog-previous'), isFalse);
      expect(tool(tester, 'form-dialog-next'), isTrue);
      expect(tool(tester, 'form-dialog-new'), isTrue);
      expect(tool(tester, 'form-dialog-delete'), isTrue);
      expect(tool(tester, 'form-dialog-undelete'), isFalse);
      expect(footer(tester, 'Discard changes'), isTrue);
      expect(footer(tester, 'Apply changes'), isTrue);
    }, variant: desktop);

    testWidgets('new child: Delete, Add and New, Add', (tester) async {
      await pumpForm(tester, server(), model: 'test.form', recordId: 1,
          metadata: true);
      await tester.tap(find.byKey(const ValueKey('x2m-new')));
      await tester.pumpAndSettle();
      expect(inDialog(find.text('Delete')), findsWidgets);
      expect(footer(tester, 'Add and New'), isTrue);
      expect(footer(tester, 'Add'), isTrue);
      expect(tool(tester, 'form-dialog-new'), isTrue);
      expect(tool(tester, 'form-dialog-previous'), isTrue, reason: '3/3');
    }, variant: desktop);

    testWidgets('no create / delete right on the child model: New, Delete off',
        (tester) async {
      await pumpForm(
          tester,
          server({
            'test.line': {'read': 1, 'write': 1, 'create': 0, 'delete': 0}
          }),
          model: 'test.form',
          recordId: 1,
          metadata: true);
      await openLine(tester, 'L11');
      expect(tool(tester, 'form-dialog-new'), isFalse);
      expect(tool(tester, 'form-dialog-delete'), isFalse);
      expect(footer(tester, 'Apply changes'), isTrue);
    }, variant: desktop);

    testWidgets('parent read only: only Close, toolbar without New/Delete',
        (tester) async {
      await pumpForm(
          tester,
          server({
            'test.form': {'read': 1, 'write': 0, 'create': 0, 'delete': 0}
          }),
          model: 'test.form',
          recordId: 1,
          metadata: true);
      await openLine(tester, 'L11');
      expect(footer(tester, 'Close'), isTrue);
      expect(inDialog(find.text('Discard changes')), findsNothing);
      expect(tool(tester, 'form-dialog-new'), isFalse);
      expect(tool(tester, 'form-dialog-delete'), isFalse);
      expect(tool(tester, 'form-dialog-next'), isTrue, reason: 'browsing stays');
    }, variant: desktop);
  });
}

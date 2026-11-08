import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'form_harness.dart';

/// Header of the x2many widget (spec 9.2.7 „Kopfzeile im Detail“, Python
/// form_gtk/one2many.py and many2many.py): all buttons shown, disabled
/// when not allowed.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// Form `test.form` with the x2many [field] (description [desc], node
  /// attributes in [attrs]) holding [ids] of `test.line`.
  FakeFormRpc server(Map<String, dynamic> desc, List<int> ids,
          {String attrs = '',
          Map<String, Object? Function(List<dynamic>)> extra = const {}}) =>
      FakeFormRpc({
        'model.test.form.fields_view_get': (_) =>
            formView('<form><field name="lines" $attrs/></form>', {
              'lines': {
                'string': 'Lines',
                'relation': 'test.line',
                ...desc,
              },
            }),
        'model.test.form.read': (p) => [
              {'id': 1, '_timestamp': '1', 'lines': ids}
            ],
        'model.test.form.write': (_) => null,
        'model.test.line.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'arch': '<tree><field name="name"/></tree>',
                'fields': {
                  'name': {'type': 'char', 'string': 'Name'},
                },
              }
            : formView('<form><field name="name"/></form>', {
                'name': {'type': 'char', 'string': 'Name'},
              }),
        'model.test.line.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'L$id', '_timestamp': '1'}
            ],
        'model.test.line.view_toolbar_get': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.form.resources': (_) => <String, dynamic>{},
        ...extra,
      });

  IconButton? button(WidgetTester tester, String name) {
    final finder = find.descendant(
        of: find.byKey(ValueKey('x2m-$name')), matching: find.byType(IconButton));
    return finder.evaluate().isEmpty ? null : tester.widget<IconButton>(finder);
  }

  bool active(WidgetTester tester, String name) =>
      button(tester, name)!.onPressed != null;

  String position(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('x2m-position'))).data!;

  /// Selects the row of [text] (the single click waits for the row's
  /// double tap).
  Future<void> select(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
  }

  testWidgets('(a) readonly field: all buttons shown; New/Delete disabled, '
      'Edit and navigation active; Edit opens the record', (tester) async {
    final rpc = server({'type': 'one2many'}, [11, 12], attrs: 'readonly="1"');
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    expect(find.text('Lines'), findsOneWidget, reason: 'title in the header');
    for (final name in ['switch', 'previous', 'next', 'new', 'open', 'delete', 'undelete']) {
      expect(button(tester, name), isNotNull, reason: '$name shown');
    }
    expect(position(tester), '_/2');
    expect(active(tester, 'new'), isFalse);
    expect(active(tester, 'open'), isFalse, reason: 'no selection');
    expect(active(tester, 'next'), isTrue);

    await select(tester, 'L11');
    expect(position(tester), '1/2');
    expect(active(tester, 'new'), isFalse);
    expect(active(tester, 'delete'), isFalse);
    expect(active(tester, 'undelete'), isFalse);
    expect(active(tester, 'open'), isTrue, reason: 'view only');
    expect(active(tester, 'switch'), isTrue);
    expect(active(tester, 'previous'), isFalse, reason: 'first');
    expect(active(tester, 'next'), isTrue);

    // navigation in the table: the selection follows
    await tester.tap(find.byKey(const ValueKey('x2m-next')));
    await tester.pumpAndSettle();
    expect(position(tester), '2/2');
    expect(active(tester, 'next'), isFalse, reason: 'last');

    await tester.tap(find.byKey(const ValueKey('x2m-open')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget, reason: 'form dialog');
  }, variant: desktop);

  testWidgets('(b) size limit: New, Add and the search entry disabled',
      (tester) async {
    final rpc = server({
      'type': 'one2many',
      'size': 2,
      'add_remove': [
        ['active', '=', true]
      ],
    }, [11, 12]);
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    expect(active(tester, 'new'), isFalse);
    expect(active(tester, 'add'), isFalse);
    expect(
        tester.widget<TextField>(find.byKey(const ValueKey('x2m-add-entry'))).enabled,
        isFalse);
    await select(tester, 'L11');
    expect(active(tester, 'delete'), isTrue, reason: 'not limited');
    expect(active(tester, 'remove'), isTrue);
  }, variant: desktop);

  testWidgets('(b) below the size limit: New active', (tester) async {
    final rpc = server({'type': 'one2many', 'size': 3}, [11, 12]);
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    expect(active(tester, 'new'), isTrue);
  }, variant: desktop);

  testWidgets('(c) one2many without add_remove: no search entry, no Add/Remove',
      (tester) async {
    final rpc = server({'type': 'one2many'}, [11]);
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    expect(find.byKey(const ValueKey('x2m-add-entry')), findsNothing);
    expect(find.byKey(const ValueKey('x2m-add')), findsNothing);
    expect(find.byKey(const ValueKey('x2m-remove')), findsNothing);
    expect(button(tester, 'new'), isNotNull);
    expect(tester.widget<IconButton>(find.descendant(
            of: find.byKey(const ValueKey('x2m-new')),
            matching: find.byType(IconButton))).tooltip,
        'Create a new record');
  }, variant: desktop);

  testWidgets('(d) many2many: search entry with „Create …“, Add/Remove/'
      'Restore, no New/Edit button', (tester) async {
    final rpc = server({'type': 'many2many'}, [11], extra: {
      'model.test.line.autocomplete': (p) => [
            {'id': 21, 'name': 'Red'},
            {
              'id': null,
              'name': 'Create "Re"...',
              'defaults': {'name': 'Re'}
            },
          ],
      'model.test.line.default_get': (_) => <String, dynamic>{},
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    expect(find.byKey(const ValueKey('x2m-add-entry')), findsOneWidget);
    for (final name in ['add', 'remove', 'undelete']) {
      expect(button(tester, name), isNotNull, reason: name);
    }
    expect(find.byKey(const ValueKey('x2m-new')), findsNothing);
    expect(find.byKey(const ValueKey('x2m-open')), findsNothing);
    expect(button(tester, 'undelete')!.tooltip, 'Restore selected record');
    expect(active(tester, 'remove'), isFalse, reason: 'no selection');
    await select(tester, 'L11');
    expect(active(tester, 'remove'), isTrue);

    await tester.enterText(find.byKey(const ValueKey('x2m-add-entry')), 'Re');
    await tester.pumpAndSettle();
    expect(find.text('Red'), findsOneWidget);
    expect(find.text('Create "Re"...'), findsOneWidget, reason: 'create right');
    await tester.tap(find.text('Create "Re"...'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget, reason: 'new record');
    // the defaults of the entry as default_ context (Python `_sig_new`)
    expect(rpc.named('model.test.line.default_get').single.context['default_name'],
        'Re');
  }, variant: desktop);

  testWidgets('Switch to the inline form loads the fields of the form view '
      '(lazy function fields, Python `screen.add_view`)', (tester) async {
    final rpc = server({'type': 'one2many', 'mode': 'tree,form'}, [11, 12],
        extra: {
      'model.test.line.fields_view_get': (p) => p[1] == 'tree'
          ? {
              'type': 'tree',
              'view_id': 5,
              'arch': '<tree><field name="name"/></tree>',
              'fields': {
                'name': {'type': 'char', 'string': 'Name'},
              },
            }
          : {
              'type': 'form',
              'view_id': 6,
              'arch': '<form><field name="name"/><field name="total"/></form>',
              'fields': {
                'name': {'type': 'char', 'string': 'Name'},
                'total': {
                  'type': 'char',
                  'string': 'Total',
                  'loading': 'lazy',
                },
              },
            },
      'model.test.line.read': (p) => [
            for (final id in p[0] as List)
              {
                'id': id,
                '_timestamp': '1',
                for (final f in p[1] as List)
                  if (f == 'name') 'name': 'L$id' else if (f == 'total') 'total': 'T$id',
              }
          ],
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await select(tester, 'L11');
    await tester.tap(find.byKey(const ValueKey('x2m-switch')));
    await tester.pumpAndSettle();
    expect(
        rpc
            .named('model.test.line.read')
            .any((c) => (c.params[1] as List).contains('total')),
        isTrue,
        reason: 'form field read');
    expect(find.text('T11'), findsOneWidget);
  }, variant: desktop);

  testWidgets('narrow screen: the rare buttons are in the „More“ menu',
      (tester) async {
    final rpc = server({
      'type': 'one2many',
      'add_remove': [
        ['active', '=', true]
      ],
    }, [11]);
    await pumpForm(tester, rpc,
        model: 'test.form', recordId: 1, size: const Size(420, 900));
    expect(find.byKey(const ValueKey('x2m-more')), findsOneWidget);
    expect(find.byKey(const ValueKey('x2m-switch')), findsNothing);
    expect(button(tester, 'new'), isNotNull, reason: 'frequent: stays');
    await tester.tap(find.byKey(const ValueKey('x2m-more')));
    await tester.pumpAndSettle();
    for (final name in ['switch', 'add', 'remove', 'undelete']) {
      expect(find.byKey(ValueKey('x2m-more-$name')), findsOneWidget, reason: name);
    }
  }, variant: desktop);
}

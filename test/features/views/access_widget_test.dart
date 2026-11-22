import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/views/record_menu.dart';

import 'form_harness.dart';

/// Access rights from the server (MODELACCESS) in the UI (spec 4, 10.3).
void main() {
  const arch = '<form><label name="name"/><field name="name"/>'
      '<label name="partner"/><field name="partner"/></form>';

  FakeFormRpc server(Map<String, Map<String, int>> access,
          {List<String> history = const []}) =>
      FakeFormRpc({
        'model.ir.model.list_models': (_) => ['test.form', 'test.party'],
        'model.ir.model.access.get_access': (p) => {
              for (final m in p[0] as List)
                m: access[m] ??
                    {'read': 1, 'write': 1, 'create': 1, 'delete': 1}
            },
        'model.ir.model.list_history': (_) => history,
        'model.test.form.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'view_id': 2,
                'arch': '<tree><field name="name"/></tree>',
                'fields': {
                  'name': {'type': 'char', 'string': 'Name'}
                },
              }
            : formView(arch, {
                'name': {'type': 'char', 'string': 'Name'},
                'partner': {
                  'type': 'many2one',
                  'string': 'Partner',
                  'relation': 'test.party',
                },
              }),
        'model.test.form.search': (_) => [1, 2],
        'model.test.form.read': (p) => [
              for (final id in p[0] as List)
                {
                  'id': id,
                  'name': 'N$id',
                  'partner': 5,
                  'partner.': {'rec_name': 'Acme'},
                  'rec_name': 'N$id',
                  '_timestamp': '1',
                  '_write': true,
                  '_delete': true,
                }
            ],
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  IconButton buttonOf(WidgetTester tester, IconData icon) =>
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon).first);

  /// Copy, delete and revisions are in the record menu only (SAO toolbar).
  Future<MenuItemButton?> menuEntry(
      WidgetTester tester, RecordAction action) async {
    if (find.byKey(const ValueKey('record-menu-save')).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('record-title')));
      await tester.pumpAndSettle();
    }
    final entry = find.byKey(ValueKey('record-menu-${action.name}'));
    return entry.evaluate().isEmpty
        ? null
        : tester.widget<MenuItemButton>(entry);
  }

  testWidgets('without create/delete: New, Duplicate, Delete disabled; '
      'Many2One without read: no Open', (tester) async {
    final rpc = server({
      'test.form': {'read': 1, 'write': 1, 'create': 0, 'delete': 0},
      'test.party': {'read': 0, 'write': 0, 'create': 0, 'delete': 0},
    });
    await pumpForm(tester, rpc,
        model: 'test.form', recordId: 1, settle: false, metadata: true);
    expect(buttonOf(tester, Icons.add).onPressed, isNull);
    expect(find.byKey(const ValueKey('m2o-open-partner')), findsNothing);
    expect((await menuEntry(tester, RecordAction.copy))?.onPressed, isNull);
    expect((await menuEntry(tester, RecordAction.delete))?.onPressed, isNull);
    expect(await menuEntry(tester, RecordAction.revision), isNull,
        reason: 'no MODELHISTORY model');
    // write right: the form stays editable
    expect(rpc.named('model.ir.model.access.get_access'), isNotEmpty);
  });

  testWidgets('full rights: buttons enabled, Open shown; history model has '
      'Revisions', (tester) async {
    final rpc = server(const {}, history: ['test.form']);
    // The start sequence loads the history models.
    await pumpForm(tester, rpc,
        model: 'test.form', recordId: 1, settle: false, metadata: true);
    expect(buttonOf(tester, Icons.add).onPressed, isNotNull);
    expect(find.byKey(const ValueKey('m2o-open-partner')), findsOneWidget);
    expect((await menuEntry(tester, RecordAction.delete))?.onPressed, isNotNull);
    expect(await menuEntry(tester, RecordAction.revision), isNotNull,
        reason: 'history model: revisions in the record menu');
  });

  testWidgets('list: a click selects, a double click opens (desktop)',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
    final rpc = server(const {});
    await pumpScreen(tester, rpc, const ScreenAttributes('test.form'),
        settle: false, metadata: true);
    await tester.tap(find.text('N2'));
    await tester.pump(kDoubleTapTimeout);
    await pumpFrames(tester, 5);
    expect(find.byKey(const ValueKey('list-column-menu')), findsOneWidget, reason: 'still the list');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('toolbar-position')),
            matching: find.text('2/2')),
        findsOneWidget,
        reason: 'N2 selected');

    await tester.tap(find.text('N2'));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.text('N2'));
    await pumpFrames(tester);
    expect(find.byKey(const ValueKey('list-column-menu')), findsNothing, reason: 'form opened');
  });

  testWidgets('touch: tapping opens, a long press selects', (tester) async {
    final rpc = server(const {});
    await pumpScreen(tester, rpc, const ScreenAttributes('test.form'),
        settle: false, metadata: true);
    await tester.longPress(find.text('N2'));
    await pumpFrames(tester, 5);
    expect(find.byKey(const ValueKey('list-column-menu')), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('toolbar-position')),
            matching: find.text('2/2')),
        findsOneWidget,
        reason: 'N2 selected');
    await tester.tap(find.text('N1'));
    await pumpFrames(tester);
    expect(find.byKey(const ValueKey('list-column-menu')), findsNothing, reason: 'form opened');
  });
}

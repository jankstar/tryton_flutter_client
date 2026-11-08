import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/views/record_menu.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

import 'form_harness.dart';

/// Record menu at the title and the shortcuts of a form tab (spec 10.3,
/// Anhang B).
void main() {
  FakeFormRpc server({Map<String, int>? access}) => FakeFormRpc({
        'model.ir.model.list_models': (_) => ['test.form'],
        'model.ir.model.access.get_access': (p) => {
              for (final m in p[0] as List)
                m: access ?? {'read': 1, 'write': 1, 'create': 1, 'delete': 1}
            },
        'model.ir.model.list_history': (_) => ['test.form'],
        'model.test.form.fields_view_get': (_) => formView(
            '<form><field name="name"/></form>',
            {'name': {'type': 'char', 'string': 'Name'}}),
        'model.test.form.read': (p) => [
              for (final id in p[0] as List)
                {
                  'id': id,
                  'name': 'N$id',
                  'rec_name': 'N$id',
                  '_timestamp': '1',
                  '_write': true,
                  '_delete': true,
                }
            ],
        'model.test.form.write': (_) => null,
        'model.test.form.resources': (_) =>
            {'attachment_count': 0, 'note_count': 0, 'note_unread': 0},
        'model.test.form.view_toolbar_get': (_) => {
              'print': [
                {'id': 3, 'name': 'Label', 'type': 'ir.action.report'}
              ],
            },
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  MenuItemButton entry(WidgetTester tester, RecordAction a) =>
      tester.widget<MenuItemButton>(find.byKey(ValueKey('record-menu-${a.name}')));

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('record-title')));
    await tester.pumpAndSettle();
  }

  testWidgets('menu at the title: all entries of menu_def with icon, '
      'shortcut and the activation of the buttons', (tester) async {
    final rpc = server(access: {'read': 1, 'write': 1, 'create': 0, 'delete': 1});
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1, metadata: true);
    await openMenu(tester);
    // all entries in the order of menu_def (revision: MODELHISTORY)
    final keys = [
      for (final e in tester.widgetList<MenuItemButton>(find.byType(MenuItemButton)))
        (e.key as ValueKey<String>).value
    ];
    expect(keys, [for (final a in RecordAction.values) 'record-menu-${a.name}']);
    expect(find.byType(Divider), findsNWidgets(recordMenuGroups.length - 1),
        reason: 'separators between the groups');

    final enabled = {
      for (final a in RecordAction.values) a: entry(tester, a).onPressed != null
    };
    expect(enabled, {
      RecordAction.switchView: false, // only the form view
      RecordAction.previous: false, // single record
      RecordAction.next: false,
      RecordAction.search: false,
      RecordAction.newRecord: false, // no create right
      RecordAction.save: false, // not modified
      RecordAction.reload: true,
      RecordAction.copy: false, // no create right
      RecordAction.delete: true,
      RecordAction.logs: true,
      RecordAction.revision: true,
      RecordAction.attach: true,
      RecordAction.note: true,
      RecordAction.action: false, // nothing in view_toolbar_get
      RecordAction.relate: false,
      RecordAction.print: true, // a report
      RecordAction.email: false,
      RecordAction.export: true,
      RecordAction.import: false, // no create right
      RecordAction.close: true,
    });
    // shortcut (GTK; Ctrl outside macOS) and label
    String? keysOf(RecordAction a) => switch (entry(tester, a).shortcut) {
          final SingleActivator s => shortcutText(s),
          _ => null,
        };
    expect(keysOf(RecordAction.save), 'Ctrl+S');
    expect(keysOf(RecordAction.copy), 'Ctrl+Shift+D');
    expect(keysOf(RecordAction.next), 'Ctrl+↓');
    expect(keysOf(RecordAction.logs), isNull);
    expect(find.text('Reload/Undo'), findsOneWidget);

    // a dropdown entry opens the toolbar button's menu, here: run the
    // single report directly → no menu; Revisions asks the server
    await tester.tap(find.byKey(const ValueKey('record-menu-revision')));
    await tester.pumpAndSettle();
    expect(rpc.named('model.test.form.history_revisions'), hasLength(1));
  });

  testWidgets('Ctrl+S saves the typed text; Save becomes active in the menu',
      (tester) async {
    final rpc = server();
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1, metadata: true);
    await tester.enterText(find.byType(TextField).first, 'Changed');
    await tester.pump();
    await openMenu(tester);
    expect(entry(tester, RecordAction.save).onPressed, isNotNull);
    await tester.tapAt(Offset.zero); // close the menu
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField).first);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(rpc.named('model.test.form.write').single.params, [
      [1],
      {'name': 'Changed'},
    ]);
    expect(find.text('Changed'), findsOneWidget);
  });

  testWidgets('macOS: Cmd+S saves, Cmd+D asks before deleting',
      (tester) async {
    final rpc = server();
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1, metadata: true);
    await tester.enterText(find.byType(TextField).first, 'Mac');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(rpc.named('model.test.form.write').single.params[1], {'name': 'Mac'});

    await tester.showKeyboard(find.byType(TextField).first);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget, reason: 'delete prompt');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('help dialog lists all shortcuts', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
            onPressed: () => showShortcutsHelp(context), child: const Text('help')),
      ),
    ));
    await tester.tap(find.text('help'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shortcuts-help')), findsOneWidget);
    for (final a in RecordAction.values) {
      final s = recordShortcut(a);
      if (s != null) expect(find.text(shortcutText(s)), findsWidgets, reason: a.name);
    }
    expect(find.text('Ctrl+S'), findsOneWidget);
    expect(find.text('Ctrl+Shift+D'), findsOneWidget);
    expect(find.text('Ctrl+↑'), findsOneWidget);
    expect(find.text('F3'), findsWidgets);
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/icons/tryton_icon.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';

import 'form_harness.dart';

/// Buttons of a list in the toolbar menus (Python `Screen.get_buttons` +
/// `ViewTree.get_buttons`): e.g. „Run Once“ of `ir.cron`.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// `ir.cron`-like list: `<button name="run_once" multiple="1"/>`,
  /// readonly while `running`.
  FakeFormRpc server({bool running = false}) => FakeFormRpc({
        'model.test.cron.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'view_id': 3,
                'arch': '<tree><field name="name"/><field name="running"/>'
                    '<button name="run_once" multiple="1" string="Run Once" '
                    'type="class" states="{&quot;readonly&quot;: '
                    '{&quot;__class__&quot;: &quot;Eval&quot;, '
                    '&quot;v&quot;: &quot;running&quot;, &quot;d&quot;: false}}"/>'
                    '</tree>',
                'fields': {
                  'name': {'type': 'char', 'string': 'Name'},
                  'running': {'type': 'boolean', 'string': 'Running'},
                },
              }
            : formView('<form><field name="name"/></form>', {
                'name': {'type': 'char', 'string': 'Name'},
              }),
        'model.test.cron.search': (_) => [1, 2],
        'model.test.cron.search_count': (_) => 2,
        'model.test.cron.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'Cron $id', 'running': running, '_timestamp': '1'}
            ],
        'model.test.cron.run_once': (_) => null,
        'model.test.cron.view_toolbar_get': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.cron.resources': (_) => <String, dynamic>{},
      });

  const attributes = ScreenAttributes('test.cron', mode: ['tree', 'form']);

  Future<void> select(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
  }

  testWidgets('a class button of the list is in „Launch actions“ and runs on '
      'the selected records', (tester) async {
    final rpc = server();
    await pumpScreen(tester, rpc, attributes);
    await select(tester, 'Cron 2');
    await tester.tap(find.byTooltip('Launch actions'));
    await tester.pumpAndSettle();
    // (also in the footer of the list: `multiple="1"`)
    final entry = find.descendant(
        of: find.byType(PopupMenuItem<Object>), matching: find.text('Run Once'));
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(rpc.named('model.test.cron.run_once').single.params[0], [2]);
  }, variant: desktop);

  testWidgets('a button readonly for the selection is not offered',
      (tester) async {
    final rpc = server(running: true);
    await pumpScreen(tester, rpc, attributes);
    await select(tester, 'Cron 1');
    expect(find.byTooltip('Launch actions'), findsOneWidget);
    final button = tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip('Launch actions'),
        matching: find.byType(IconButton)));
    expect(button.onPressed, isNull, reason: 'nothing to launch');
    // the propeller of the Python client (`tryton-launch`), not a rocket
    final icon = tester.widget<TrytonIcon>(find.descendant(
        of: find.byTooltip('Launch actions'), matching: find.byType(TrytonIcon)));
    expect(icon.iconName, 'tryton-launch');
  }, variant: desktop);
}

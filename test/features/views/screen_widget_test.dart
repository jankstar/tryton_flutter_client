import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';

import 'form_harness.dart';

/// List and form as two views of one screen (spec 8, E1/E4).
void main() {
  const fields = {
    'name': {'type': 'char', 'string': 'Name'},
  };

  FakeFormRpc server() => FakeFormRpc({
        'model.test.party.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'view_id': 10,
                'arch': '<tree><field name="name"/></tree>',
                'fields': fields,
              }
            : {
                'type': 'form',
                'view_id': 11,
                'arch': '<form><label name="name"/><field name="name"/>'
                    '<button name="do_it" string="Do it"/></form>',
                'fields': fields,
              },
        'model.test.party.search': (_) => [1, 2, 3],
        'model.test.party.read': (p) => [
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
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.party.resources': (_) => <String, dynamic>{},
      });

  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(finder);
    await pumpFrames(tester);
  }

  /// The value shown in the form's Name field.
  String formName(WidgetTester tester) =>
      tester.widget<TextField>(textFieldOf('Name')).controller!.text;

  testWidgets('list → form → previous/next → list share group and record',
      (tester) async {
    final rpc = server();
    await pumpScreen(tester, rpc, const ScreenAttributes('test.party'),
        settle: false);

    // List: one search, the rows loaded with their neighbours in one read.
    expect(find.text('N1'), findsOneWidget);
    expect(find.text('N3'), findsOneWidget);
    expect(find.text('_/3'), findsOneWidget);
    expect(rpc.named('model.test.party.search'), hasLength(1));
    expect(rpc.named('model.test.party.read').first.params[0], [1, 2, 3]);

    // Double click opens the form of the same record.
    await doubleTap(tester, find.text('N2'));
    expect(find.byType(DataTable), findsNothing);
    expect(formName(tester), 'N2');
    expect(find.textContaining('2/3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_forward_ios));
    await pumpFrames(tester);
    expect(formName(tester), 'N3');
    await tester.tap(find.byIcon(Icons.arrow_back_ios));
    await pumpFrames(tester);
    await tester.tap(find.byIcon(Icons.arrow_back_ios));
    await pumpFrames(tester);
    expect(formName(tester), 'N1');
    expect(find.textContaining('1/3'), findsOneWidget);

    // Back to the list: no new search, the current record is selected.
    await tester.tap(find.byTooltip('Switch view'));
    await pumpFrames(tester);
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(rpc.named('model.test.party.search'), hasLength(1));
    final row = tester
        .widget<DataTable>(find.byType(DataTable))
        .rows
        .firstWhere((r) => r.selected);
    expect(row, isNotNull);
  });

  testWidgets('new from the list opens the form; switching back asks first',
      (tester) async {
    final rpc = server()
      ..handlers['model.test.party.default_get'] =
          (_) => <String, dynamic>{'name': 'Default'};
    await pumpScreen(tester, rpc, const ScreenAttributes('test.party'),
        settle: false);
    await tester.tap(find.byIcon(Icons.add).first);
    await pumpFrames(tester);
    expect(formName(tester), 'Default');

    // Switching back asks first (new record = modified, spec 10.4); "No"
    // removes the new record.
    await tester.tap(find.byTooltip('Switch view'));
    await pumpFrames(tester);
    expect(find.textContaining('This record has been modified'), findsOneWidget);
    await tester.tap(find.text('No'));
    await pumpFrames(tester);
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Default'), findsNothing);
    expect(find.text('_/3'), findsOneWidget);
  });

  testWidgets('form: duplicate, delete and a button with a client action',
      (tester) async {
    final rpc = server();
    rpc.handlers
      ..['model.test.party.copy'] = ((_) => [100])
      ..['model.test.party.delete'] = ((_) => null)
      ..['model.test.party.do_it'] = ((_) => 'switch tree');
    await pumpScreen(tester, rpc, const ScreenAttributes('test.party'),
        settle: false);
    await doubleTap(tester, find.text('N2'));
    expect(formName(tester), 'N2');

    // Duplicate: the copy is loaded on top of the group and shown.
    await tester.tap(find.byIcon(Icons.copy_outlined));
    await pumpFrames(tester);
    expect(rpc.named('model.test.party.copy').single.params, [
      [2],
      <String, dynamic>{}
    ]);
    expect(formName(tester), 'N100');
    expect(find.textContaining('1/4'), findsOneWidget);

    // Delete: removed from the group, the form shows the next record.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await pumpFrames(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await pumpFrames(tester);
    expect(rpc.named('model.test.party.delete').single.params, [
      [100]
    ]);
    expect(formName(tester), 'N1');

    // A button answering "switch tree" switches to the list (spec 8.7).
    await tester.tap(find.text('Do it'));
    await pumpFrames(tester);
    expect(rpc.named('model.test.party.do_it').single.params, [
      [1]
    ]);
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('N100'), findsNothing);
    expect(find.text('1/3'), findsOneWidget);
  });
}

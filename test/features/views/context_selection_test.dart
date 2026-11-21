import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/shared/widgets/selection_input.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';

import 'form_harness.dart';

/// Issue #2: the context form above a list (real_estate „Belegung“) has a
/// selection `state` with a method (`get_state`, `sort=False`, first
/// option `(None, '')`). Its options are loaded like in the form, and the
/// chosen key keeps its type (null stays null, not "null").
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  FakeFormRpc server() => FakeFormRpc({
        'model.test.occ.context.fields_view_get': (_) => formView(
                '<form><label name="state"/><field name="state"/>'
                '<label name="level"/><field name="level"/></form>',
                {
                  'state': {
                    'type': 'selection',
                    'string': 'State',
                    'selection': 'get_state',
                    'sort': false,
                  },
                  'level': {
                    'type': 'selection',
                    'string': 'Level',
                    'selection': [
                      [1, 'One'],
                      [2, 'Two'],
                    ],
                  },
                }),
        'model.test.occ.context.default_get': (_) => <String, dynamic>{},
        'model.test.occ.context.get_state': (_) => [
              [null, ''],
              ['rented', 'Rented'],
              ['vacant', 'Vacant'],
            ],
        'model.test.occ.fields_view_get': (_) => {
              'type': 'tree',
              'view_id': 3,
              'arch': '<tree><field name="name"/></tree>',
              'fields': {
                'name': {'type': 'char', 'string': 'Name'},
              },
            },
        'model.test.occ.search': (_) => [1],
        'model.test.occ.search_count': (_) => 1,
        'model.test.occ.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'Occ $id', '_timestamp': '1'},
            ],
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  Future<void> choose(WidgetTester tester, int index, String label) async {
    // the arrow of the selection entry shows the whole list (spec T2)
    await tester.tap(find.descendant(
        of: find.byType(SelectionInput).at(index),
        matching: find.byIcon(Icons.arrow_drop_down)));
    await pumpFrames(tester, 5);
    // (the empty label has no size: the tap hits its row)
    await tester.tap(
        find
            .descendant(
                of: find.byKey(const ValueKey('selection-options')),
                matching: find.text(label))
            .first,
        warnIfMissed: false);
    await pumpFrames(tester, 10);
  }

  testWidgets('method selection of the context form is loaded and chosen',
      (tester) async {
    final rpc = server();
    await pumpScreen(
      tester,
      rpc,
      const ScreenAttributes('test.occ',
          mode: ['tree'], contextModel: 'test.occ.context'),
      settle: false,
    );
    await pumpFrames(tester);
    expect(rpc.named('model.test.occ.context.get_state'), hasLength(1));

    await choose(tester, 0, 'Vacant');
    expect(rpc.named('model.test.occ.search').last.context['state'], 'vacant');

    // the empty option gives null, not the text "null"
    await choose(tester, 0, '');
    final ctx = rpc.named('model.test.occ.search').last.context;
    expect(ctx.containsKey('state') ? ctx['state'] : null, isNull);

    // integer keys stay integers
    await choose(tester, 1, 'Two');
    expect(rpc.named('model.test.occ.search').last.context['level'], 2);
  }, variant: desktop);
}

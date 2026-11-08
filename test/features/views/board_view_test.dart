import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/views/board_view.dart';

import 'form_harness.dart';

/// Board tab (spec 9.7, E33): `view_get` arch, one screen per action,
/// master/detail by the `_actions` domain.
void main() {
  final desktop = TargetPlatformVariant.only(TargetPlatform.macOS);

  /// `Eval('_actions', {}).get('10', {}).get('active_id', -1)` (PYSON).
  const activeParty = {
    '__class__': 'Get',
    'v': {
      '__class__': 'Get',
      'v': {'__class__': 'Eval', 'v': '_actions', 'd': {}},
      'k': '10',
      'd': {},
    },
    'k': 'active_id',
    'd': -1,
  };

  Map<String, dynamic> act(String name, String model, int viewId,
          {Object domain = const []}) =>
      {
        'id': viewId,
        'name': name,
        'type': 'ir.action.act_window',
        'res_model': model,
        'views': [
          [viewId, 'tree'],
          [null, 'form'],
        ],
        'pyson_domain': jsonEncode(domain),
        'pyson_context': '{}',
        'pyson_order': '[]',
        'pyson_search_value': '[]',
        'domains': <dynamic>[],
        'context_model': null,
        'context_domain': null,
      };

  Map<String, dynamic> tree(String field) => {
        'type': 'tree',
        'arch': '<tree><field name="$field"/></tree>',
        'fields': {
          field: {'type': 'char', 'string': field},
        },
      };

  /// The party (or -1) of the `party` clause in [domain].
  int partyOf(dynamic domain) {
    final match = RegExp(r'"party","=",(-?\d+)').firstMatch(jsonEncode(domain));
    return int.parse(match?.group(1) ?? '0');
  }

  FakeFormRpc server() => FakeFormRpc({
        'model.ir.ui.view.view_get': (_) => {
              'type': 'board',
              'view_id': 7,
              'arch': '<board col="2"><action name="10"/>'
                  '<action name="20" string="Their addresses"/></board>',
            },
        'model.ir.action.act_window.get': (p) => p[0] == '10'
            ? act('Parties', 'test.party', 11)
            : act('Addresses', 'test.address', 21, domain: [
                ['party', '=', activeParty],
              ]),
        'model.test.party.fields_view_get': (p) =>
            p[1] == 'tree' ? tree('name') : formView('<form/>', {}),
        'model.test.address.fields_view_get': (p) =>
            p[1] == 'tree' ? tree('street') : formView('<form/>', {}),
        'model.test.party.search': (_) => [1, 2],
        'model.test.party.search_count': (_) => 2,
        'model.test.party.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'Party $id', '_timestamp': '1'}
            ],
        'model.test.address.search': (p) {
          final party = partyOf(p[0]);
          return party > 0 ? [100 + party] : <int>[];
        },
        'model.test.address.search_count': (p) => partyOf(p[0]) > 0 ? 1 : 0,
        'model.test.address.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'street': 'Street $id', '_timestamp': '1'}
            ],
        'model.test.party.view_toolbar_get': (_) => <String, dynamic>{},
        'model.test.address.view_toolbar_get': (_) => <String, dynamic>{},
      });

  const board = ScreenAttributes('null',
      mode: ['board'], viewIds: [7], context: {'board': true});

  testWidgets('view_get, one screen per action with its title; a selection '
      'in A updates the domain of B (master/detail)', (tester) async {
    final rpc = server();
    await pumpApp(tester, rpc, const BoardView(attributes: board, title: 'Dashboard'),
        settle: false);
    await pumpFrames(tester);

    final viewGet = rpc.named('model.ir.ui.view.view_get').single;
    expect(viewGet.params, [7]);
    expect(viewGet.context['board'], isTrue, reason: 'context of the tab');
    expect([for (final c in rpc.named('model.ir.action.act_window.get')) c.params[0]],
        unorderedEquals(['10', '20']));
    expect(find.text('Parties'), findsOneWidget, reason: 'action name');
    expect(find.text('Their addresses'), findsOneWidget, reason: 'string');
    expect(find.text('Party 1'), findsOneWidget);
    // no party selected: `active_id` is null (Python `Action.active`)
    expect(jsonEncode(rpc.named('model.test.address.search').last.params[0]),
        contains('"party","=",null'));
    expect(find.textContaining('Street'), findsNothing);

    await tester.tap(find.text('Party 2'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await pumpFrames(tester);
    expect(partyOf(rpc.named('model.test.address.search').last.params[0]), 2);
    expect(find.text('Street 102'), findsOneWidget);

    // the same selection again: the domain is unchanged, no new search
    final searches = rpc.named('model.test.address.search').length;
    await tester.tap(find.text('Party 2'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await pumpFrames(tester);
    expect(rpc.named('model.test.address.search'), hasLength(searches));
  }, variant: desktop);

  testWidgets('Reload searches all actions again; activation opens the '
      'record in a form dialog', (tester) async {
    final rpc = server();
    await pumpApp(tester, rpc, const BoardView(attributes: board, title: 'Dashboard'),
        settle: false);
    await pumpFrames(tester);
    final before = rpc.named('model.test.party.search').length;
    await tester.tap(find.byKey(const ValueKey('board-reload')));
    await pumpFrames(tester);
    expect(rpc.named('model.test.party.search').length, before + 1);

    await tester.tap(find.text('Party 1'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Party 1'));
    await pumpFrames(tester);
    expect(find.byType(Dialog), findsOneWidget, reason: 'form dialog');
  }, variant: desktop);
}

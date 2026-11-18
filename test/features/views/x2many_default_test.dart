import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'form_harness.dart';

/// Issue #6: x2many defaults of `default_get` (party `addresses` → `[{}]`)
/// become child records like Python `O2MField.set_default`.
void main() {
  Map<String, dynamic> addressView(int id, String type) => type == 'form'
      ? {
          'type': 'form',
          'view_id': id,
          'arch': '<form><label name="street"/><field name="street"/>'
              '<label name="city"/><field name="city"/>'
              '<label name="active"/><field name="active"/></form>',
          'fields': {
            // like party.address: readonly unless active
            'street': {
              'type': 'char',
              'string': 'Street',
              'states': '{"readonly": {"__class__": "Not", "v": '
                  '{"__class__": "Eval", "v": "active", "d": true}}}',
            },
            'active': {'type': 'boolean', 'string': 'Active'},
            'city': {'type': 'char', 'string': 'City'},
            'party': {
              'type': 'many2one',
              'string': 'Party',
              'relation': 'test.party'
            },
          },
        }
      : {
          'type': 'tree',
          'view_id': id,
          'arch': '<tree><field name="street"/></tree>',
          'fields': {
            'street': {'type': 'char', 'string': 'Street'},
          },
        };

  FakeFormRpc server(Map<String, dynamic> defaults) => FakeFormRpc({
        'model.test.party.fields_view_get': (_) => formView(
                '<form><label name="name"/><field name="name"/>'
                '<field name="addresses" mode="form,tree" colspan="4" '
                'view_ids="168,166"/></form>',
                {
                  'name': {'type': 'char', 'string': 'Name'},
                  'addresses': {
                    'type': 'one2many',
                    'string': 'Addresses',
                    'relation': 'test.address',
                    'relation_field': 'party',
                  },
                }),
        'model.test.party.default_get': (_) => defaults,
        'model.test.party.create': (_) => [5],
        'model.test.party.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'Doe', 'addresses': <int>[], '_timestamp': '1'}
            ],
        'model.test.address.fields_view_get': (p) =>
            addressView(p[0] as int? ?? 0, '${p[1]}'),
        'model.test.address.default_get': (p) => {
              for (final MapEntry(:key, :value) in {
                'city': 'From default_get',
                'active': true,
                'street': '',
              }.entries)
                if ((p[0] as List).contains(key)) key: value
            },
        'model.test.address.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'street': 'Street $id', 'city': 'B', '_timestamp': '1'}
            ],
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.party.resources': (_) => <String, dynamic>{},
      });

  bool readOnly(WidgetTester tester, String label) =>
      tester.widget<TextField>(textFieldOf(label)).readOnly;

  Future<void> save(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'new party: [{}] gives an empty, editable address; create like Python',
      (tester) async {
    final rpc = server({
      'addresses': [<String, dynamic>{}]
    });
    await pumpForm(tester, rpc, model: 'test.party', recordId: -1);
    // one address in the inline form, without clicking „+“
    expect(find.text('1/1'), findsOneWidget);
    // its view fields got their defaults (Python Group.add_fields): active
    expect(rpc.named('model.test.address.default_get'), hasLength(1));
    expect(rpc.named('model.test.address.default_get').single.params[0],
        containsAll(['street', 'city', 'active']));
    expect(readOnly(tester, 'Street'), isFalse, reason: 'active is True');
    expect(
        tester.widget<TextField>(textFieldOf('City')).controller!.text,
        'From default_get');

    await tester.enterText(textFieldOf('Name'), 'Doe');
    await tester.enterText(textFieldOf('Street'), 'Main 1');
    await save(tester);
    // Python Record.get of a new child: every field of the group
    // (Char as ''), the parent field removed
    expect(rpc.named('model.test.party.create').single.params[0], [
      {
        'name': 'Doe',
        'addresses': [
          [
            'create',
            [
              {'street': 'Main 1', 'city': 'From default_get', 'active': true}
            ]
          ]
        ],
      }
    ]);
  });

  testWidgets('new party: [{}] and only the name saved creates the address',
      (tester) async {
    final rpc = server({
      'addresses': [<String, dynamic>{}]
    });
    await pumpForm(tester, rpc, model: 'test.party', recordId: -1);
    await tester.enterText(textFieldOf('Name'), 'Doe');
    await save(tester);
    expect(rpc.named('model.test.party.create').single.params[0], [
      {
        'name': 'Doe',
        'addresses': [
          [
            'create',
            [
              {'street': '', 'city': 'From default_get', 'active': true}
            ]
          ]
        ],
      }
    ]);
  });

  testWidgets('default as id list: the records are loaded and added',
      (tester) async {
    final rpc = server({
      'addresses': [7]
    });
    await pumpForm(tester, rpc, model: 'test.party', recordId: -1);
    expect(find.text('1/1'), findsOneWidget);
    expect(tester.widget<TextField>(textFieldOf('Street')).controller!.text,
        'Street 7');
    expect(rpc.named('model.test.address.default_get'), isEmpty);
    await tester.enterText(textFieldOf('Name'), 'Doe');
    await save(tester);
    expect(rpc.named('model.test.party.create').single.params[0], [
      {
        'name': 'Doe',
        'addresses': [
          [
            'add',
            [7]
          ]
        ],
      }
    ]);
  });
}

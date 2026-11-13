import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';

import 'form_harness.dart';

/// Selection columns whose selection is a server method show labels also
/// without the server's `<f>:string` (new or changed records; Python
/// `list_gtk.Selection.get_textual_value` with `update_selection`), e.g.
/// the type of a party identifier (`get_types`) – not the key.
void main() {
  FakeFormRpc server(List<Map<String, dynamic>> rows) => FakeFormRpc({
        'model.test.ident.fields_view_get': (_) => {
              'type': 'tree',
              'view_id': 7,
              'arch': '<tree><field name="type"/><field name="kind"/>'
                  '<field name="tags"/></tree>',
              'fields': {
                'type': {
                  'type': 'selection',
                  'string': 'Type',
                  'selection': 'get_types',
                },
                'kind': {
                  'type': 'selection',
                  'string': 'Kind',
                  'selection': 'get_kinds',
                  'selection_change_with': ['country'],
                },
                'country': {'type': 'char', 'string': 'Country'},
                'tags': {
                  'type': 'multiselection',
                  'string': 'Tags',
                  'selection': 'get_tags',
                },
              },
            },
        'model.test.ident.get_types': (_) => [
              ['de_stnr', 'Deutsche Steuernummer'],
              ['eu_vat', 'USt-IdNr.'],
            ],
        'model.test.ident.get_kinds': (p) => [
              ['a', (p[0] as Map)['country'] == 'DE' ? 'A in DE' : 'A elsewhere'],
            ],
        'model.test.ident.get_tags': (_) => [
              ['x', 'Tag X'],
              ['y', 'Tag Y'],
            ],
        'model.test.ident.search': (_) => [for (final r in rows) r['id']],
        'model.test.ident.search_count': (_) => rows.length,
        'model.test.ident.read': (p) => [
              for (final id in p[0] as List)
                {...rows.firstWhere((r) => r['id'] == id), '_timestamp': '1'}
            ],
        'model.test.ident.view_toolbar_get': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  testWidgets('method selections: labels instead of keys, also with '
      'selection_change_with and for multiselection', (tester) async {
    final rpc = server([
      // no `type:string`: like a record created or changed in the client
      {'id': 1, 'type': 'de_stnr', 'kind': 'a', 'country': 'DE', 'tags': ['x', 'y']},
      {'id': 2, 'type': 'eu_vat', 'kind': 'a', 'country': 'FR', 'tags': ['y']},
    ]);
    await pumpScreen(
        tester, rpc, const ScreenAttributes('test.ident', mode: ['tree']),
        settle: false);
    await pumpFrames(tester, 20);
    expect(find.text('Deutsche Steuernummer'), findsOneWidget);
    expect(find.text('USt-IdNr.'), findsOneWidget);
    expect(find.text('de_stnr'), findsNothing);
    // per record values (selection_change_with)
    expect(find.text('A in DE'), findsOneWidget);
    expect(find.text('A elsewhere'), findsOneWidget);
    expect(find.text('Tag X, Tag Y'), findsOneWidget);
    expect(find.text('Tag Y'), findsOneWidget);
    expect(rpc.named('model.test.ident.get_types'), hasLength(1),
        reason: 'once per screen, shared with the search');
  });

  testWidgets('inline x2many form ("Switch"): a method selection shows its '
      'label, not the key', (tester) async {
    final rpc = FakeFormRpc({
      'model.test.form.fields_view_get': (_) => formView(
          '<form><field name="idents" mode="form,tree" colspan="4"/></form>', {
        'idents': {
          'type': 'one2many',
          'string': 'Identifiers',
          'relation': 'test.ident',
        },
      }),
      'model.test.form.read': (_) => [
            {'id': 1, '_timestamp': '1', 'idents': [11]}
          ],
      'model.test.ident.fields_view_get': (p) => p[1] == 'form'
          ? formView('<form><label name="type"/><field name="type"/></form>', {
              'type': {
                'type': 'selection',
                'string': 'Type',
                'selection': 'get_types',
              },
            })
          : {
              'type': 'tree',
              'arch': '<tree><field name="type"/></tree>',
              'fields': {
                'type': {
                  'type': 'selection',
                  'string': 'Type',
                  'selection': 'get_types',
                },
              },
            },
      'model.test.ident.get_types': (_) => [
            ['de_stnr', 'Deutsche Steuernummer'],
          ],
      'model.test.ident.read': (p) => [
            for (final id in p[0] as List)
              {'id': id, '_timestamp': '1', 'type': 'de_stnr'}
          ],
      'model.test.ident.view_toolbar_get': (_) => <String, dynamic>{},
      'model.test.form.resources': (_) => <String, dynamic>{},
      'model.ir.model.search_read': (_) => <dynamic>[],
      'model.ir.model.get_notification': (_) => <String, dynamic>{},
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await pumpFrames(tester, 10);
    expect(find.text('Deutsche Steuernummer'), findsOneWidget);
    expect(find.text('de_stnr'), findsNothing);
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/icons/tryton_icon.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';
import 'package:tryton_flutter_client/features/views/record_form.dart';

import 'form_harness.dart';

/// Form widgets on the record (E10, E11, E12, E13, D9, H4, H5).
void main() {
  /// A form `test.form` (record 1) with [arch], [fields] and [values].
  FakeFormRpc server(String arch, Map<String, dynamic> fields,
          Map<String, dynamic> values,
          [Map<String, Object? Function(List<dynamic>)> extra = const {}]) =>
      FakeFormRpc({
        'model.test.form.fields_view_get': (_) => formView(arch, fields),
        'model.test.form.read': (p) => [
              {'id': 1, '_timestamp': '1.0', ...values}
            ],
        'model.test.form.write': (_) => null,
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.form.resources': (_) => <String, dynamic>{},
        ...extra,
      });

  const german = {
    'locale': {
      'date': '%d.%m.%Y',
      'decimal_point': ',',
      'thousands_sep': '.',
      'grouping': [3, 3, 0],
    }
  };

  String textOf(WidgetTester tester, String label) =>
      tester.widget<TextField>(textFieldOf(label)).controller!.text;

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
  }

  group('numbers (D9/H4)', () {
    testWidgets('German locale: 1.234,56 shown and parsed, factor, '
        'get_digits and get_symbol', (tester) async {
      final rpc = server(
        '<form><field name="amount"/><field name="rate" factor="100"/>'
            '<field name="price" symbol="currency"/>'
            '<field name="currency"/><field name="qty"/></form>',
        {
          // digits PYSON-encoded like trytond (`encoder.encode(digits)`)
          'amount': {'type': 'numeric', 'string': 'Amount', 'digits': '[16, 2]'},
          'rate': {'type': 'float', 'string': 'Rate', 'digits': '[16, 4]'},
          'price': {'type': 'numeric', 'string': 'Price', 'digits': '"currency"'},
          'currency': {
            'type': 'many2one',
            'string': 'Currency',
            'relation': 'test.currency'
          },
          'qty': {'type': 'integer', 'string': 'Qty'},
        },
        {
          'amount': const TrytonDecimal('1234.56'),
          'rate': 0.125,
          'price': const TrytonDecimal('1234567.5'),
          'currency': 7,
          'currency.': {'rec_name': 'Euro'},
          'qty': 1234567,
        },
        {
          'model.test.currency.get_digits': (p) => [16, 3],
          'model.test.currency.get_symbol': (p) => ['€', 1],
        },
      );
      await pumpForm(tester, rpc,
          model: 'test.form', recordId: 1, preferences: german);
      expect(textOf(tester, 'Amount'), '1.234,56');
      expect(textOf(tester, 'Rate'), '12,50',
          reason: 'value × factor, digits 4 − 2');
      expect(textOf(tester, 'Price'), '1.234.567,500',
          reason: 'digits of get_digits(7)');
      expect(rpc.named('model.test.currency.get_digits').first.params, [7]);
      expect(rpc.named('model.test.currency.get_symbol').first.params, [7, 1]);
      expect(find.text(' €'), findsOneWidget, reason: 'position 1: suffix');
      expect(textOf(tester, 'Qty'), '1.234.567');

      await tester.enterText(textFieldOf('Amount'), '2.345,5');
      await tester.enterText(textFieldOf('Rate'), '7,5');
      await tester.enterText(textFieldOf('Qty'), '12');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(textOf(tester, 'Amount'), '2.345,50');
      await save(tester);
      final values = rpc.named('model.test.form.write').single.params[1] as Map;
      expect(values['amount'], const TrytonDecimal('2345.50'));
      expect(values['rate'], 0.075, reason: 'input ÷ factor');
      expect(values['qty'], 12);
    });

    testWidgets('invalid input keeps the value', (tester) async {
      final rpc = server('<form><field name="amount"/></form>', {
        'amount': {'type': 'float', 'string': 'Amount', 'digits': [16, 2]},
      }, {
        'amount': 5.0
      });
      await pumpForm(tester, rpc,
          model: 'test.form', recordId: 1, preferences: german);
      await tester.enterText(textFieldOf('Amount'), '1.2.x');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(textOf(tester, 'Amount'), '5,00');
    });
  });

  group('timedelta, multiselection, dict (E13)', () {
    testWidgets('timedelta with the converter of the context',
        (tester) async {
      final rpc = server('<form><field name="duration"/></form>', {
        'duration': {
          'type': 'timedelta',
          'string': 'Duration',
          'converter': 'work_time',
        },
      }, {
        'duration': const Duration(hours: 10)
      });
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1, context: {
        // company_work_time: 1 day = 8 hours
        'work_time': {'s': 1, 'm': 60, 'h': 3600, 'd': 28800, 'w': 144000},
      });
      expect(textOf(tester, 'Duration'), '1d 02:00');
      await tester.enterText(textFieldOf('Duration'), '2d 1:30');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(textOf(tester, 'Duration'), '2d 01:30');
      await save(tester);
      expect(rpc.named('model.test.form.write').single.params[1],
          {'duration': const Duration(hours: 17, minutes: 30)});
    });

    testWidgets('multiselection chips write the sorted list',
        (tester) async {
      final rpc = server('<form><field name="tags"/></form>', {
        'tags': {
          'type': 'multiselection',
          'string': 'Tags',
          'selection': [
            ['a', 'Alpha'],
            ['b', 'Beta'],
            ['c', 'Gamma']
          ],
        },
      }, {
        'tags': ['c']
      });
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      expect(tester.widget<FilterChip>(find.byKey(const ValueKey('multi-tags-c'))).selected,
          isTrue);
      await tester.tap(find.text('Alpha'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(rpc.named('model.test.form.write').single.params[1], {
        'tags': ['a', 'c']
      });
    });

    testWidgets('dict: keys of search_get_keys, typed rows, remove',
        (tester) async {
      final rpc = server('<form><field name="attrs"/></form>', {
        'attrs': {
          'type': 'dict',
          'string': 'Attributes',
          'schema_model': 'test.attribute',
          'domain': '[]',
        },
      }, {
        'attrs': {'size': 3, 'ok': true, 'kind': 'b'}
      }, {
        'model.test.attribute.search_get_keys': (p) => [
              {'name': 'size', 'string': 'Size', 'type': 'integer', 'sequence': 1},
              {'name': 'ok', 'string': 'OK', 'type': 'boolean', 'sequence': 3},
              {
                'name': 'kind',
                'string': 'Kind',
                'type': 'selection',
                'sequence': 2,
                'selection': [
                  ['a', 'A'],
                  ['b', 'B']
                ]
              },
            ],
      });
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      final keysCall = rpc.named('model.test.attribute.search_get_keys').single;
      expect((keysCall.params[0] as List).first, [
        'name',
        'in',
        ['kind', 'ok', 'size'] // the dict's keys are sorted
      ]);
      expect(find.text('Size:'), findsOneWidget);
      expect(find.text('Kind:'), findsOneWidget);
      expect(find.text('B'), findsOneWidget, reason: 'selection label');
      // sorted by sequence: Size, Kind, OK
      final dy = [
        for (final t in ['Size:', 'Kind:', 'OK:']) tester.getTopLeft(find.text(t)).dy
      ];
      expect(dy, orderedEquals([...dy]..sort()));
      final size = find.descendant(
          of: find.byKey(const ValueKey('dict-attrs-size')),
          matching: find.byType(TextField));
      expect(tester.widget<TextField>(size).controller!.text, '3');

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dict-remove-kind')));
      await tester.pumpAndSettle();
      await tester.enterText(size, '4');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await save(tester);
      expect(rpc.named('model.test.form.write').single.params[1], {
        'attrs': {'ok': false, 'size': 4}
      });
    });
  });

  group('date (H5)', () {
    testWidgets('locale date format, operators and "="', (tester) async {
      final rpc = server('<form><field name="day"/></form>', {
        'day': {'type': 'date', 'string': 'Day'},
      }, {
        'day': const TrytonDate(2026, 1, 31)
      });
      await pumpForm(tester, rpc,
          model: 'test.form', recordId: 1, preferences: german);
      expect(textOf(tester, 'Day'), '31.01.2026');
      await tester.tap(textFieldOf('Day'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(textOf(tester, 'Day'), '28.02.2026', reason: 'm: +1 month, clipped');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.pump();
      expect(textOf(tester, 'Day'), '01.03.2026');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY, character: 'Y');
      await tester.pump();
      expect(textOf(tester, 'Day'), '01.03.2025', reason: 'Y: −1 year');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await save(tester);
      expect(rpc.named('model.test.form.write').single.params[1],
          {'day': const TrytonDate(2025, 3, 1)});
    });
  });

  group('link (E10)', () {
    testWidgets('counters per tab domain with count, 99+, click runs the '
        'action', (tester) async {
      final rpc = server(
          '<form><field name="name"/><link id="5" icon="tryton-sale"/>'
              '<link id="6" empty="hide"/></form>',
          {
            'name': {'type': 'char', 'string': 'Name'}
          },
          {
            'name': 'P'
          },
          {
            'model.ir.action.get_action_value': (p) => p[0] == 5
                ? {
                    'id': 5,
                    'type': 'ir.action.act_window',
                    'name': 'Sales',
                    'res_model': 'test.sale',
                    'pyson_domain':
                        '[["party", "=", {"__class__": "Eval", "v": "active_id", "d": null}]]',
                    'domains': [
                      ['Draft', '[["state", "=", "draft"]]', true],
                      ['All', '[]', false],
                      ['Done', '[["state", "=", "done"]]', true],
                    ],
                  }
                : {
                    'id': 6,
                    'type': 'ir.action.act_window',
                    'name': 'Invoices',
                    'res_model': 'test.invoice',
                    'pyson_domain': '[]',
                    'domains': const [],
                  },
            'model.test.sale.search_count': (p) {
              final domain = p[0] as List;
              return '${domain.last}'.contains('draft') ? 150 : 2;
            },
            'model.test.invoice.search_count': (p) => 0,
            'model.test.sale.fields_view_get': (_) => {
                  'type': 'tree',
                  'arch': '<tree/>',
                  'fields': <String, dynamic>{}
                },
          });
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      expect(find.text('Sales\nDraft (99+)\nDone (2)'), findsOneWidget);
      final count = rpc.named('model.test.sale.search_count').first;
      expect(count.params.sublist(1), [0, 100]);
      expect(count.params[0], [
        'AND',
        [
          ['party', '=', 1]
        ],
        [
          ['state', '=', 'draft']
        ]
      ]);
      expect(find.textContaining('Invoices'), findsNothing,
          reason: 'empty="hide" with 0');

      await tester.tap(find.text('Sales\nDraft (99+)\nDone (2)'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
          tester.element(find.byType(RecordForm)));
      final tab = container.read(tabsProvider).tabs.single;
      expect(tab.attributes.model, 'test.sale');
      expect(tab.attributes.domain, [
        ['party', '=', 1]
      ]);
    });
  });

  group('layout (E12)', () {
    const fields = {
      'name': {'type': 'char', 'string': 'Name'},
      'code': {'type': 'char', 'string': 'Code'},
      'hidden': {
        'type': 'char',
        'string': 'Hidden',
        'states': '{"invisible": true}'
      },
    };
    const arch = '<form col="4"><label name="name"/><field name="name"/>'
        '<label name="code"/><field name="code"/>'
        '<field name="hidden" colspan="4"/></form>';

    testWidgets('wide: one row; narrow: one column, label above',
        (tester) async {
      final rpc = server(arch, fields, {'name': 'N', 'code': 'C', 'hidden': ''});
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      final name = tester.getRect(textFieldOf('Name'));
      final code = tester.getRect(textFieldOf('Code'));
      expect(name.top, code.top, reason: 'same row');
      expect(code.left, greaterThan(name.right));
      expect(find.text('Hidden'), findsNothing, reason: 'invisible row collapses');

      await pumpForm(tester, rpc,
          model: 'test.form', recordId: 1, size: const Size(400, 900));
      final name2 = tester.getRect(textFieldOf('Name'));
      final code2 = tester.getRect(textFieldOf('Code'));
      expect(code2.top, greaterThan(name2.bottom), reason: 'one column');
      expect(code2.left, name2.left);
      expect(code2.width, name2.width);
    });

    testWidgets('a column without visible cell collapses', (tester) async {
      final rpc = server(
          '<form col="2"><field name="hidden"/><field name="name"/></form>',
          fields,
          {'name': 'N', 'hidden': ''});
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      final form = tester.getRect(find.byType(RecordForm));
      // column 0 has only the invisible field: column 1 takes the width
      expect(tester.getRect(textFieldOf('Name')).width,
          greaterThan(form.width * 0.9));
    });

    testWidgets('col="0": a horizontal box', (tester) async {
      final rpc = server(
          '<form col="0"><field name="name"/><field name="code"/></form>',
          fields,
          {'name': 'N', 'code': 'C'});
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      final n = tester.getRect(textFieldOf('Name'));
      final c = tester.getRect(textFieldOf('Code'));
      expect(n.top, c.top);
      expect(c.left, greaterThan(n.right));
      expect(n.width, closeTo(c.width, 1), reason: 'both expand');
    });
  });

  group('states on containers, label value, image (E10)', () {
    testWidgets('group/separator/label states, expander, label string=""',
        (tester) async {
      final rpc = server(
          '<form><group id="g" string="Hidden group" '
              'states="{&quot;invisible&quot;: {&quot;__class__&quot;: &quot;Equal&quot;, '
              '&quot;s1&quot;: {&quot;__class__&quot;: &quot;Eval&quot;, &quot;v&quot;: &quot;name&quot;, &quot;d&quot;: &quot;&quot;}, '
              '&quot;s2&quot;: &quot;N&quot;}}"><field name="code"/></group>'
              '<separator string="Sep" states="{&quot;invisible&quot;: true}"/>'
              '<label string="Free" states="{&quot;invisible&quot;: true}"/>'
              '<label name="name" string=""/>'
              '<group id="e" string="More" expandable="0"><field name="other"/></group>'
              '<image name="color" type="color" size="20"/></form>',
          {
            'name': {'type': 'char', 'string': 'Name'},
            'code': {'type': 'char', 'string': 'Code'},
            'other': {'type': 'char', 'string': 'Other'},
            'color': {'type': 'char', 'string': 'Color'},
          },
          {'name': 'N', 'code': 'C', 'other': 'O', 'color': '#ff0000'});
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      expect(find.text('Hidden group'), findsNothing);
      expect(find.text('Code'), findsNothing);
      expect(find.text('Sep'), findsNothing);
      expect(find.text('Free'), findsNothing);
      expect(find.text('N'), findsOneWidget, reason: 'label shows the value');
      // expander closed (expandable="0"), opens on tap
      expect(find.text('More'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Other'), findsOneWidget);
      final square = tester.widgetList<Container>(find.byType(Container)).where(
          (c) => c.color == const Color(0xffff0000));
      expect(square, hasLength(1), reason: 'image type="color" of the field');
    });
  });

  group('translation dialog (9.2.5)', () {
    testWidgets('per language value, fuzzy hint, edited value written',
        (tester) async {
      final rpc = server('<form><field name="name"/></form>', {
        'name': {'type': 'char', 'string': 'Name', 'translate': true},
      }, {
        'name': 'Chair'
      }, {
        'model.ir.lang.search': (p) => [1, 2],
        'model.ir.lang.read': (p) => [
              {'id': 1, 'code': 'en', 'name': 'English'},
              {'id': 2, 'code': 'de', 'name': 'German'},
            ],
      });
      // read per language: without and with fuzzy_translation
      rpc.handlers['model.test.form.read'] = (p) {
        final call = rpc.calls.last;
        final language = call.context['language'];
        final fuzzy = call.context['fuzzy_translation'] == true;
        final name = switch (language) {
          'de' => fuzzy ? 'Stuhl?' : 'Chair',
          _ => 'Chair',
        };
        return [
          {'id': 1, '_timestamp': '1.0', 'name': name}
        ];
      };
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      await tester.tap(find.byKey(const ValueKey('translate-name')));
      await tester.pumpAndSettle();
      expect(rpc.named('model.ir.lang.search').single.params[0], [
        ['translatable', '=', true]
      ]);
      expect(find.text('German:'), findsOneWidget);
      expect(find.text('Fuzzy'), findsOneWidget, reason: 'only de differs');
      await tester.tap(find.byKey(const ValueKey('translate-edit-de')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('translate-de')), 'Stuhl');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final write = rpc.named('model.test.form.write').single;
      expect(write.params, [
        [1],
        {'name': 'Stuhl'}
      ]);
      expect(write.context['language'], 'de');
      expect(write.context['fuzzy_translation'], isFalse);
    });
  });

  group('x2many mode (9.2.7)', () {
    testWidgets('mode="form,tree" with view_ids: inline form first, '
        'Previous/Next, Switch to the table', (tester) async {
      final rpc = server(
          '<form><field name="addresses" mode="form,tree" '
              'view_ids="168,166"/></form>',
          {
            'addresses': {
              'type': 'one2many',
              'string': 'Addresses',
              'relation': 'test.address',
              'relation_field': 'party',
            },
          },
          {
            'addresses': [11, 12]
          },
          {
            'model.test.address.fields_view_get': (p) => p[0] == 168
                ? {
                    'type': 'form',
                    'view_id': 168,
                    'arch': '<form><field name="street"/>'
                        '<field name="party"/></form>',
                    'fields': {
                      'street': {'type': 'char', 'string': 'Street'},
                      'party': {
                        'type': 'many2one',
                        'string': 'Party',
                        'relation': 'test.form'
                      },
                    },
                  }
                : {
                    'type': 'tree',
                    'view_id': 166,
                    'arch': '<tree><field name="street"/></tree>',
                    'fields': {
                      'street': {'type': 'char', 'string': 'Street'},
                    },
                  },
            'model.test.address.read': (p) => [
                  for (final id in p[0] as List)
                    {
                      'id': id,
                      'street': 'Street $id',
                      'party': 1,
                      'party.': {'rec_name': 'P'},
                      '_timestamp': '1'
                    }
                ],
          });
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      final views = rpc.named('model.test.address.fields_view_get');
      expect([for (final v in views) v.params], containsAll([
        [168, 'form'],
        [166, 'tree']
      ]));
      expect(textOf(tester, 'Street'), 'Street 11');
      expect(find.text('Party'), findsNothing, reason: 'relation_field');
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('x2m-next')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'Street'), 'Street 12');
      await tester.enterText(textFieldOf('Street'), 'New street');
      await tester.tap(find.byKey(const ValueKey('x2m-switch')));
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('New street'), findsOneWidget,
          reason: 'typed text written before switching');
      await save(tester);
      expect(rpc.named('model.test.form.write').single.params[1], {
        'addresses': [
          ['add', [12]], // modified records are added and written (5.7)
          [
            'write',
            [12],
            {'street': 'New street'}
          ]
        ]
      });
    });
  });

  testWidgets('cursor: initial focus on the field (9.2.2), help as tooltip',
      (tester) async {
    final rpc = server(
        '<form cursor="code"><field name="name"/><field name="code" '
            'help="The code"/></form>',
        {
          'name': {'type': 'char', 'string': 'Name'},
          'code': {'type': 'char', 'string': 'Code'},
        },
        {'name': 'N', 'code': 'C'});
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final code = tester.widget<TextField>(textFieldOf('Code'));
    expect(code.focusNode!.hasFocus, isTrue);
    expect(find.byTooltip('The code'), findsOneWidget);
  });

  group('many2one widget="selection" (9.2.4)', () {
    const langField = {
      'type': 'many2one',
      'string': 'Language',
      'relation': 'test.lang',
      'domain': '[["kind", "=", {"__class__": "Eval", "v": "kind", "d": ""}]]',
      'context': '{"lang_ctx": 1}',
    };
    final fields = {
      'lang': langField,
      'kind': {
        'type': 'selection',
        'string': 'Kind',
        'selection': [
          ['a', 'A'],
          ['b', 'B']
        ]
      },
    };
    const arch = '<form><field name="kind"/>'
        '<field name="lang" widget="selection" help_field="code"/></form>';

    List<Map<String, dynamic>> langs(String kind) => kind == 'a'
        ? [
            {'id': 2, 'rec_name': 'German', 'code': 'de'},
            {'id': 1, 'rec_name': 'English', 'code': 'en'},
          ]
        : [
            {'id': 3, 'rec_name': 'French', 'code': 'fr'},
          ];

    testWidgets('search_read with field domain/context, default order, '
        'help, empty entry; choice writes the id', (tester) async {
      final rpc = server(arch, fields, {
        'kind': 'a',
        'lang': 1,
        'lang.': {'rec_name': 'English'}
      }, {
        'model.test.lang.search_read': (p) =>
            langs('${((p[0] as List).single as List)[2]}'),
      });
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      final call = rpc.named('model.test.lang.search_read').single;
      expect(call.params, [
        [
          ['kind', '=', 'a']
        ],
        0,
        null,
        null,
        ['rec_name', 'code']
      ]);
      expect(call.context['lang_ctx'], 1, reason: 'field context');
      expect(find.byType(DropdownButtonFormField<int?>), findsOneWidget);
      expect(find.text('English'), findsOneWidget, reason: 'current value');
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      // server order (German before English), empty entry last
      final items = tester
          .widgetList<DropdownMenuItem<int?>>(find.byType(DropdownMenuItem<int?>))
          .map((i) => i.value)
          .toList();
      expect(items.sublist(items.length - 3), [2, 1, null]);
      expect(find.byTooltip('de'), findsWidgets, reason: 'help_field');
      await tester.tap(find.text('German').last);
      await tester.pumpAndSettle();
      await save(tester);
      expect(rpc.named('model.test.form.write').single.params[1], {'lang': 2});
    });

    testWidgets('inactive value shown, domain change reloads, late older '
        'answer dropped', (tester) async {
      final rpc = server(arch, fields, {
        'kind': 'a',
        'lang': 9,
        'lang.': {'rec_name': 'Latin (inactive)'}
      });
      var first = true;
      rpc.handlers['model.test.lang.search_read'] = (p) async {
        final kind = '${((p[0] as List).single as List)[2]}';
        if (first) {
          first = false;
          // the answer of the first domain comes late
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        return langs(kind);
      };
      await pumpForm(tester, rpc,
          model: 'test.form', recordId: 1, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Latin (inactive)'), findsOneWidget);
      // change the domain before the first answer arrived
      final kind = find.byType(DropdownButtonFormField<String>);
      await tester.tap(kind);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      await tester.tap(find.text('B').last);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(rpc.named('model.test.lang.search_read'), hasLength(2));
      await tester.tap(find.text('Latin (inactive)'));
      await tester.pumpAndSettle();
      expect(find.text('French'), findsWidgets);
      expect(find.text('German'), findsNothing,
          reason: 'the late answer of domain a is dropped');
    });

    testWidgets('error: only the empty entry, no dialog',
        (tester) async {
      final rpc = server(arch, fields, {
        'kind': 'a',
        'lang': null,
      }, {
        'model.test.lang.search_read': (_) => throw StateError('denied'),
      });
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();
      expect(
          tester
              .widgetList<DropdownMenuItem<int?>>(
                  find.byType(DropdownMenuItem<int?>))
              .map((i) => i.value)
              .toSet(),
          {null});
    });

    testWidgets('readonly: the rec_name as text, nothing loaded',
        (tester) async {
      final ro = server(
          '<form><field name="lang" widget="selection" readonly="1"/></form>',
          fields, {
        'lang': 1,
        'lang.': {'rec_name': 'English'}
      });
      await pumpForm(tester, ro, model: 'test.form', recordId: 1);
      expect(find.byType(DropdownButtonFormField<int?>), findsNothing);
      expect(find.text('English'), findsOneWidget);
      expect(ro.named('model.test.lang.search_read'), isEmpty);
    });
  });

  testWidgets('x2many keys: Delete marks, Insert undeletes, F3 new (desktop)',
      (tester) async {
    final rpc = server(
        '<form><field name="lines"/></form>',
        {
          'lines': {
            'type': 'one2many',
            'string': 'Lines',
            'relation': 'test.line',
            'relation_field': 'parent',
          },
        },
        {
          'lines': [11, 12]
        },
        {
          'model.test.line.fields_view_get': (p) => p[1] == 'tree'
              ? {
                  'type': 'tree',
                  'arch': '<tree><field name="name"/></tree>',
                  'fields': {
                    'name': {'type': 'char', 'string': 'Name'}
                  },
                }
              : {
                  'type': 'form',
                  'arch': '<form><field name="name"/></form>',
                  'fields': {
                    'name': {'type': 'char', 'string': 'Name'}
                  },
                },
          'model.test.line.read': (p) => [
                for (final id in p[0] as List)
                  {'id': id, 'name': 'L$id', '_timestamp': '1'}
              ],
          'model.test.line.default_get': (_) => <String, dynamic>{},
        });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(find.text('L11'));
    // the single tap fires after the double tap timeout
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(find.text('1 ×'), findsOneWidget, reason: 'marked for deletion');
    await tester.sendKeyEvent(LogicalKeyboardKey.insert);
    await tester.pumpAndSettle();
    expect(find.text('1 ×'), findsNothing, reason: 'undeleted');
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    await save(tester);
    expect(rpc.named('model.test.form.write').single.params[1], {
      'lines': [
        [
          'delete',
          [11]
        ]
      ]
    });
    await tester.tap(find.text('L12'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    expect(rpc.named('model.test.line.default_get'), hasLength(1),
        reason: 'F3: new record (form popup)');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('readonly x2many (posted invoice): Switch gives the inline '
      'form with the fields by their own states, no New/Delete',
      (tester) async {
    final rpc = server(
        '<form><field name="state"/><field name="lines"/></form>',
        {
          'state': {'type': 'char', 'string': 'State'},
          'lines': {
            'type': 'one2many',
            'string': 'Lines',
            'relation': 'test.line',
            'relation_field': 'invoice',
            // like account.invoice: readonly when not draft
            'states': '{"readonly": {"__class__": "Not", "v": {"__class__": '
                '"Equal", "s1": {"__class__": "Eval", "v": "state", "d": ""}, '
                '"s2": "draft"}}}',
          },
        },
        {
          'state': 'posted',
          'lines': [11, 12]
        },
        {
          'model.test.line.fields_view_get': (p) => p[1] == 'tree'
              ? {
                  'type': 'tree',
                  'arch': '<tree><field name="name"/></tree>',
                  'fields': {
                    'name': {'type': 'char', 'string': 'Name'}
                  },
                }
              : {
                  'type': 'form',
                  'arch': '<form><field name="sequence"/>'
                      '<field name="name"/></form>',
                  'fields': {
                    'sequence': {'type': 'integer', 'string': 'Sequence'},
                    // like the invoice line fields: readonly when posted
                    'name': {
                      'type': 'char',
                      'string': 'Name',
                      'states': '{"readonly": true}'
                    },
                  },
                },
          'model.test.line.read': (p) => [
                for (final id in p[0] as List)
                  {'id': id, 'name': 'L$id', 'sequence': id, '_timestamp': '1'}
              ],
        });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    expect(find.byKey(const ValueKey('x2m-new')), findsNothing,
        reason: 'readonly x2many: no New');
    await tester.tap(find.text('L11'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    final switchButton = find.ancestor(
        of: find.byWidgetPredicate(
            (w) => w is TrytonIcon && w.iconName == 'tryton-switch'),
        matching: find.byType(IconButton));
    await tester.tap(switchButton.last);
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget, reason: 'inline form');
    final sequence = tester.widget<TextField>(textFieldOf('Sequence'));
    expect(sequence.readOnly, isFalse, reason: 'no states: editable');
    expect(sequence.controller!.text, '11');
    expect(tester.widget<TextField>(textFieldOf('Name')).readOnly, isTrue,
        reason: 'own states readonly');
    expect(find.byKey(const ValueKey('x2m-delete')), findsNothing);
    await tester.enterText(textFieldOf('Sequence'), '5');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(textFieldOf('Sequence')).controller!.text,
        '5');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('x2many with sum="1": sum row „selected / all“', (tester) async {
    final rpc = server(
        '<form><field name="lines"/></form>',
        {
          'lines': {
            'type': 'one2many',
            'string': 'Lines',
            'relation': 'test.line',
            'relation_field': 'move',
          },
        },
        {
          'lines': [11, 12, 13]
        },
        {
          'model.test.line.fields_view_get': (p) => {
                'type': 'tree',
                'arch': '<tree><field name="name"/>'
                    '<field name="debit" sum="1"/></tree>',
                'fields': {
                  'name': {'type': 'char', 'string': 'Name'},
                  'debit': {
                    'type': 'numeric',
                    'string': 'Debit',
                    'digits': '[16, 2]'
                  },
                },
              },
          'model.test.line.read': (p) => [
                for (final id in p[0] as List)
                  {
                    'id': id,
                    'name': 'L$id',
                    'debit': TrytonDecimal('${id - 10}.5'),
                    '_timestamp': '1'
                  }
              ],
        });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final sum = find.byKey(const ValueKey('x2m-sum-debit#0'));
    expect(tester.widget<Text>(sum).data, '7.50\n7.50', reason: '1.5+2.5+3.5');
    await tester.tap(find.text('L12'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(sum).data, '2.50\n7.50', reason: 'selected / all');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}

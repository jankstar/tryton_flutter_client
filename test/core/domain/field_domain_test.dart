import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/domain/domain_inversion.dart';
import 'package:tryton_flutter_client/core/domain/field_domain.dart';
import 'package:tryton_flutter_client/core/pyson/pyson_environment.dart';

/// Form behaviour of domain_readonly (spec 02-datenmodell.md 5.5) with the
/// domain inversion, like `Field.validate` in the Python client.
void main() {
  Map<String, dynamic> env(Map<String, dynamic> values,
          [Map<String, String>? types]) =>
      recordEnvironment(
          values: formEvalValues(values, fieldTypes: types),
          activeModel: 'sale.sale',
          activeId: -1);

  DomainReadonlyResult check(
    String field,
    List<dynamic> screen,
    Map<String, dynamic> values, {
    String type = 'many2one',
    dynamic fieldDomain,
    bool required = false,
    bool fieldReadonly = false,
    bool Function(String)? isReadonlyField,
  }) =>
      evaluateDomainReadonly(
        fieldName: field,
        fieldType: type,
        fieldDomainRaw: fieldDomain,
        screenDomain: screen,
        environment: env(values),
        required: required,
        fieldReadonly: fieldReadonly,
        isReadonlyField: isReadonlyField,
      );

  group('as before', () {
    test('screen domain [f = v] sets the value and locks the field', () {
      final r = check(
          'company',
          [
            ['company', '=', 1]
          ],
          {'company': null});
      expect(r.forced, isTrue);
      expect(r.forcedValue, 1);
      expect(r.readonly, isTrue);
    });

    test('in [v] counts as a single value', () {
      final r = check(
          'company',
          [
            ['company', 'in', [1]]
          ],
          {'company': null});
      expect((r.forced, r.forcedValue, r.readonly), (true, 1, true));
    });

    test('other leaves of the action domain do not matter', () {
      final r = check(
          'company',
          [
            ['type', '=', 'out'],
            ['company', '=', 1]
          ],
          {'company': null, 'type': 'out'});
      expect((r.forced, r.forcedValue, r.readonly), (true, 1, true));
    });

    test('no unique value: nothing forced', () {
      expect(
          check(
              'company',
              [
                ['company', 'in', [1, 2]]
              ],
              {'company': null}).forced,
          isFalse);
      expect(
          check(
              'company',
              [
                ['company', '!=', 1]
              ],
              {'company': null}).forced,
          isFalse);
      expect(check('company', const [], {'company': null}).forced, isFalse);
    });

    test('a Many2One value [id, name] equals the forced id', () {
      final e = env({
        'company': [1, 'ACME']
      }, {
        'company': 'many2one'
      });
      final r = evaluateDomainReadonly(
        fieldName: 'company',
        fieldType: 'many2one',
        fieldDomainRaw: null,
        screenDomain: [
          ['company', '=', 1]
        ],
        environment: e,
      );
      expect(r.forced, isTrue);
      // The form compares in get_eval format → no update loop.
      expect(domainEquals(e['company'], r.forcedValue), isTrue);
    });
  });

  group('better (domain inversion, Python Field.validate)', () {
    test('OR in the screen domain: value set but the field stays editable',
        () {
      final r = check(
          'company',
          [
            'OR',
            ['company', '=', 1],
            ['party', '=', 5]
          ],
          {'company': null, 'party': 6});
      expect((r.forced, r.forcedValue, r.readonly), (true, 1, false));
      // party matches → the OR is already true, no constraint on company.
      expect(
          check(
              'company',
              [
                'OR',
                ['company', '=', 1],
                ['party', '=', 5]
              ],
              {'company': null, 'party': 5}).forced,
          isFalse);
    });

    test('nested AND domains are inverted', () {
      final r = check(
          'company',
          [
            [
              ['company', '=', 1],
              ['state', '=', 'draft']
            ]
          ],
          {'company': null, 'state': 'draft'});
      expect((r.forced, r.forcedValue, r.readonly), (true, 1, true));
    });

    test('leaves on readonly fields are ignored (clean4inversion)', () {
      final screen = [
        ['state', '!=', 'draft'],
        ['company', '=', 1]
      ];
      // Without cleaning the domain cannot be satisfied → nothing forced.
      expect(
          check('company', screen, {'company': null, 'state': 'draft'})
              .forced,
          isFalse);
      final r = check('company', screen, {'company': null, 'state': 'draft'},
          isReadonlyField: (f) => f == 'state');
      expect((r.forced, r.forcedValue), (true, 1));
    });

    test('field domain of a non-relational field: only for required or '
        'filled fields', () {
      final domain = jsonEncode([
        ['code', '=', 'A']
      ]);
      expect(
          check('code', const [], {'code': ''},
                  type: 'char', fieldDomain: domain)
              .forced,
          isFalse);
      final r = check('code', const [], {'code': ''},
          type: 'char', fieldDomain: domain, required: true);
      expect((r.forced, r.forcedValue, r.readonly), (true, 'A', true));
      expect(
          check('code', const [], {'code': 'B'},
                  type: 'char', fieldDomain: domain)
              .forcedValue,
          'A');
    });

    test('the domain of a Many2One restricts the search, not the value', () {
      expect(
          check('company', const [], {'company': null},
                  fieldDomain: jsonEncode([
                    ['company', '=', 1]
                  ]),
                  required: true)
              .forced,
          isFalse);
    });

    test('statically readonly fields are not touched', () {
      expect(
          check(
                  'company',
                  [
                    ['company', '=', 1]
                  ],
                  {'company': null},
                  fieldReadonly: true)
              .forced,
          isFalse);
    });

    test('multi-value fields: in [v] is not a single value', () {
      expect(
          check(
                  'tags',
                  [
                    ['tags', 'in', [1]]
                  ],
                  {'tags': []},
                  type: 'many2many',
                  required: true)
              .forced,
          isFalse);
    });

    test('[f = null] forces an empty value', () {
      final r = check(
          'company',
          [
            ['company', '=', null]
          ],
          {
            'company': [3, 'X']
          });
      expect((r.forced, r.forcedValue, r.readonly), (true, null, true));
    });

    test('Reference: f.id = v with model gives [model, v]', () {
      final r = check(
          'origin',
          [
            ['origin.id', '=', 4, 'sale.sale']
          ],
          {'origin': null},
          type: 'reference');
      expect(r.forced, isTrue);
      expect(r.forcedValue, ['sale.sale', 4]);
    });
  });
}

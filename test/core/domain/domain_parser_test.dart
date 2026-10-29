import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/domain/date_text.dart';
import 'package:tryton_flutter_client/core/domain/domain_parser.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

/// Port of the Python client's `tryton/tests/test_common_domain_parser.py`
/// (8.0). Python tuples are lists here, `iter([...])` is [TestGroup].
/// `untimezoned_date(dt)` is `DateTime(...).toUtc()`, `strftime('%x')` the
/// C locale `%m/%d/%y`.
void main() {
  DateTime untimezoned(int y, int m, int d, [int h = 0, int mi = 0, int s = 0]) =>
      DateTime(y, m, d, h, mi, s).toUtc();
  String x(DateTime d) => strftime(d, '%x');

  test('group_operator', () {
    expect(groupOperator(['a', '>', '=']), ['a', '>=']);
    expect(groupOperator(['>', '=', 'b']), ['>=', 'b']);
    expect(groupOperator(['a', '=', 'b']), ['a', '=', 'b']);
    expect(groupOperator(['a', '>', '=', 'b']), ['a', '>=', 'b']);
    expect(groupOperator(['a', '>', '=', '=']), ['a', '>=', '=']);
  });

  test('likify', () {
    for (final (value, result) in [
      ('', '%'),
      ('foo', '%foo%'),
      ('foo%', 'foo%'),
      ('foo_bar', 'foo_bar'),
      (r'foo\%', r'%foo\%%'),
      (r'foo\_bar', r'%foo\_bar%'),
    ]) {
      expect(likify(value), result, reason: value);
    }
  });

  test('quote', () {
    expect(quote('test'), 'test');
    expect(quote('foo bar'), '"foo bar"');
    expect(quote('"foo"'), r'\"foo\"');
    expect(quote(r'foo\bar'), r'foo\\bar');
  });

  test('split_target_value', () {
    const field = {
      'type': 'reference',
      'selection': [
        ['spam', 'Spam'],
        ['ham', 'Ham'],
        ['e', 'Eggs'],
      ],
    };
    for (final (value, target, rest) in [
      ('Spam', null, 'Spam'),
      ('foo', null, 'foo'),
      ('Spam,', 'spam', ''),
      ('Ham,bar', 'ham', 'bar'),
      ('Eggs,foo', 'e', 'foo'),
    ]) {
      final (t, v) = splitTargetValue(field, value);
      expect((t, v), (target, rest), reason: value);
    }
  });

  test('convert boolean', () {
    const field = {'type': 'boolean'};
    for (final (value, result) in [
      ('Y', true),
      ('yes', true),
      ('t', true),
      ('1', true),
      ('N', false),
      ('False', false),
      ('no', false),
      ('0', false),
      (null, null),
    ]) {
      expect(convertValue(field, value), result, reason: '$value');
    }
  });

  test('convert float', () {
    const field = {'type': 'float'};
    for (final (value, result) in [
      ('1', 1.0),
      ('1.5', 1.5),
      ('', null),
      ('test', null),
      (null, null),
    ]) {
      expect(convertValue(field, value), result, reason: '$value');
    }
    expect(convertValue({'type': 'float', 'factor': '100'}, '42'), 0.42);
  });

  test('convert integer', () {
    const field = {'type': 'integer'};
    for (final (value, result) in [
      ('1', 1),
      ('1.5', 1),
      ('', null),
      ('test', null),
      (null, null),
    ]) {
      expect(convertValue(field, value), result, reason: '$value');
    }
    expect(convertValue({'type': 'integer', 'factor': '2'}, '6'), 3);
  });

  test('convert numeric', () {
    const field = {'type': 'numeric'};
    for (final (value, result) in [
      ('1', const TrytonDecimal('1')),
      ('1.5', const TrytonDecimal('1.5')),
      ('', null),
      ('test', null),
      (null, null),
    ]) {
      expect(convertValue(field, value), result, reason: '$value');
    }
    expect(convertValue({'type': 'numeric', 'factor': '5'}, '1'),
        const TrytonDecimal('0.2'));
  });

  test('convert selection', () {
    const field = {
      'type': 'selection',
      'selection': [
        ['male', 'Male'],
        ['female', 'Female'],
      ],
    };
    final withEmpty = {
      ...field,
      'selection': [
        ...field['selection'] as List,
        ['', '']
      ],
    };
    for (final (value, result) in [
      ('Male', 'male'),
      ('male', 'male'),
      ('test', 'test'),
      (null, null),
      ('', ''),
    ]) {
      expect(convertValue(field, value), result, reason: '$value');
      expect(convertValue(withEmpty, value), result, reason: '$value');
    }
  });

  test('convert datetime', () {
    const field = {'type': 'datetime', 'format': '"%H:%M:%S"'};
    for (final (value, result) in [
      ('12/04/2002', untimezoned(2002, 12, 4)),
      ('12/04/2002 12:30:00', untimezoned(2002, 12, 4, 12, 30)),
      ('02/03/04', untimezoned(2004, 2, 3)),
      ('02/03/04 05:06:07', untimezoned(2004, 2, 3, 5, 6, 7)),
      ('test', null),
      (null, null),
    ]) {
      expect(convertValue(field, value), result, reason: '$value');
    }
  });

  test('convert date', () {
    const field = {'type': 'date'};
    for (final (value, result) in [
      ('12/04/2002', const TrytonDate(2002, 12, 4)),
      ('test', null),
      (null, null),
    ]) {
      expect(convertValue(field, value), result, reason: '$value');
    }
  });

  test('convert time', () {
    const field = {'type': 'time', 'format': '"%H:%M:%S"'};
    for (final (value, result) in [
      ('12:30:00', const TrytonTime(12, 30, 0, 0)),
      ('test', null),
      (null, null),
    ]) {
      expect(convertValue(field, value), result, reason: '$value');
    }
  });

  test('convert timedelta', () {
    const field = {'type': 'timedelta'};
    for (final (value, result) in [
      ('1d 2:00', const Duration(days: 1, hours: 2)),
      ('foo', Duration.zero),
      (null, null),
    ]) {
      expect(convertValue(field, value), result, reason: '$value');
    }
  });

  test('format boolean', () {
    const field = {'type': 'boolean'};
    for (final (value, result) in [(true, 'True'), (false, 'False'), (null, '')]) {
      expect(formatValue(field, value), result, reason: '$value');
    }
  });

  test('format integer', () {
    const field = {'type': 'integer'};
    for (final (value, result) in [
      (1, '1'),
      (1.5, '1'),
      (0, '0'),
      (0.0, '0'),
      (false, ''),
      (null, ''),
    ]) {
      expect(formatValue(field, value), result, reason: '$value');
    }
    expect(formatValue({'type': 'integer', 'factor': '2'}, 3), '6');
  });

  test('format float', () {
    const field = {'type': 'float'};
    for (final (value, result) in [
      (1, '1'),
      (1.5, '1.5'),
      (1.50, '1.5'),
      (150.79, '150.79'),
      (0, '0'),
      (0.0, '0'),
      (false, ''),
      (null, ''),
      (1e-12, '0.000000000001'),
      (1.0579e-10, '0.00000000010579'),
    ]) {
      expect(formatValue(field, value), result, reason: '$value');
    }
    expect(formatValue({'type': 'float', 'factor': '100'}, 0.42), '42');
  });

  test('format numeric', () {
    const field = {'type': 'numeric'};
    for (final (value, result) in [
      (const TrytonDecimal('1'), '1'),
      (const TrytonDecimal('1.5'), '1.5'),
      (const TrytonDecimal('1.50'), '1.5'),
      (const TrytonDecimal('150.79'), '150.79'),
      (const TrytonDecimal('0'), '0'),
      (const TrytonDecimal('0.0'), '0'),
      (false, ''),
      (null, ''),
    ]) {
      expect(formatValue(field, value), result, reason: '$value');
    }
    expect(formatValue({'type': 'numeric', 'factor': '5'},
        const TrytonDecimal('0.2')), '1');
  });

  test('format selection', () {
    const field = {
      'type': 'selection',
      'selection': [
        ['male', 'Male'],
        ['female', 'Female'],
      ],
    };
    final withEmpty = {
      ...field,
      'selection': [
        ...field['selection'] as List,
        ['', '']
      ],
    };
    for (final (value, result) in [
      ('male', 'Male'),
      ('test', 'test'),
      (false, ''),
      (null, ''),
      ('', ''),
    ]) {
      expect(formatValue(field, value), result, reason: '$value');
      expect(formatValue(withEmpty, value), result, reason: '$value');
    }
  });

  test('format datetime', () {
    const field = {'type': 'datetime', 'format': '"%H:%M:%S"'};
    for (final (value, result) in <(Object?, String)>[
      (const TrytonDate(2002, 12, 4), x(DateTime(2002, 12, 4))),
      (untimezoned(2002, 12, 4), x(DateTime(2002, 12, 4))),
      (
        untimezoned(2002, 12, 4, 12, 30),
        strftime(DateTime(2002, 12, 4, 12, 30), '"%x %H:%M:%S"')
      ),
      (false, ''),
      (null, ''),
    ]) {
      expect(formatValue(field, value), result, reason: '$value');
    }
  });

  test('format date', () {
    const field = {'type': 'date'};
    for (final (value, result) in <(Object?, String)>[
      (const TrytonDate(2002, 12, 4), x(DateTime(2002, 12, 4))),
      (false, ''),
      (null, ''),
    ]) {
      expect(formatValue(field, value), result, reason: '$value');
    }
  });

  test('format time', () {
    const field = {'type': 'time', 'format': '"%H:%M:%S"'};
    for (final (value, result) in <(Object?, String)>[
      (const TrytonTime(12, 30, 0, 0), '"12:30:00"'),
      (false, ''),
      (null, ''),
    ]) {
      expect(formatValue(field, value), result, reason: '$value');
    }
  });

  test('format timedelta', () {
    const field = {'type': 'timedelta'};
    for (final (value, result) in <(Object?, String)>[
      (const Duration(days: 1, hours: 2), '"1d 02:00"'),
      (Duration.zero, ''),
      (null, ''),
      ('', ''),
    ]) {
      expect(formatValue(field, value), result, reason: '$value');
    }
  });

  test('complete boolean', () {
    const field = {'type': 'boolean'};
    expect(completeValue(field, null), [true, false]);
    expect(completeValue(field, true), [false]);
    expect(completeValue(field, false), [true]);
  });

  test('complete selection', () {
    const field = {
      'type': 'selection',
      'selection': [
        ['male', 'Male'],
        ['female', 'Female'],
      ],
    };
    for (final (value, result) in <(Object?, List)>[
      ('m', ['male']),
      ('test', []),
      ('', ['male', 'female']),
      (null, ['male', 'female']),
      (['male', 'f'], [['male', 'female']]),
      (['male', null], [['male', 'male'], ['male', 'female']]),
    ]) {
      expect(completeValue(field, value), result, reason: '$value');
    }
    final withEmpty = {
      ...field,
      'selection': [
        ...field['selection'] as List,
        ['', '']
      ],
    };
    for (final (value, result) in <(Object?, List)>[
      ('m', ['male']),
      ('test', []),
      ('', ['male', 'female', '']),
      (null, ['male', 'female', '']),
      (['male', 'f'], [['male', 'female']]),
    ]) {
      expect(completeValue(withEmpty, value), result, reason: '$value');
    }
  });

  test('complete reference', () {
    const field = {
      'type': 'reference',
      'selection': [
        ['spam', 'Spam'],
        ['ham', 'Ham'],
        ['', ''],
      ],
    };
    for (final (value, result) in <(Object?, List)>[
      ('s', ['%spam%']),
      ('test', []),
      ('', ['%spam%', '%ham%', '%']),
      (null, ['%spam%', '%ham%', '%']),
      (['spam', 'h'], [['spam', 'ham']]),
    ]) {
      expect(completeValue(field, value), result, reason: '$value');
    }
  });

  test('parenthesize', () {
    for (final (value, result) in <(List<String>, List)>[
      (['a'], ['a']),
      (['a', 'b'], ['a', 'b']),
      (['(', 'a', ')'], [['a']]),
      (
        ['a', 'b', '(', 'c', '(', 'd', 'e', ')', 'f', ')', 'g'],
        ['a', 'b', ['c', ['d', 'e'], 'f'], 'g']
      ),
      (['a', 'b', '(', 'c'], ['a', 'b', ['c']]),
      (
        ['a', 'b', '(', 'c', '(', 'd', 'e', ')', 'f'],
        ['a', 'b', ['c', ['d', 'e'], 'f']]
      ),
      (['a', 'b', ')'], ['a', 'b']),
      (['a', 'b', ')', 'c', ')', 'd)'], ['a', 'b']),
    ]) {
      expect(debugParenthesize(value), result, reason: '$value');
    }
  });

  test('operatorize', () {
    const a = ['a', 'a', 'a'];
    const b = ['b', 'b', 'b'];
    const c = ['c', 'c', 'c'];
    const null_ = ['d', null, 'x'];
    const doubleNull = ['e', null, null];
    TestGroup g(List<Object?> items) => TestGroup(items);
    for (final (value, result) in <(List<Object?>, List)>[
      (['a'], ['a']),
      (['a', '|', 'b'], [['OR', 'a', 'b']]),
      (['a', '|', 'b', '|', 'c'], [['OR', ['OR', 'a', 'b'], 'c']]),
      (['a', 'b', '|', 'c'], ['a', ['OR', 'b', 'c']]),
      (['a', '|', 'b', 'c'], [['OR', 'a', 'b'], 'c']),
      (['a', g(['b', 'c'])], ['a', ['b', 'c']]),
      (['a', g(['b', 'c']), 'd'], ['a', ['b', 'c'], 'd']),
      (['a', '|', g(['b', 'c'])], [['OR', 'a', ['b', 'c']]]),
      (['a', '|', g(['b', 'c']), 'd'], [['OR', 'a', ['b', 'c']], 'd']),
      (['a', g(['b', 'c']), '|', 'd'], ['a', ['OR', ['b', 'c'], 'd']]),
      (['a', '|', g(['b', '|', 'c'])], [['OR', 'a', [['OR', 'b', 'c']]]]),
      (['|'], []),
      (['|', 'a'], ['a']),
      (['a', g(['|', 'b'])], ['a', ['b']]),
      (['a', '|', '|', 'b'], [['OR', 'a', 'b']]),
      (['|', '|', 'a'], ['a']),
      (['|', '|', 'a', 'b'], ['a', 'b']),
      (['|', '|', 'a', '|', 'b'], [['OR', 'a', 'b']]),
      (['a', g(['b', '|', 'c'])], ['a', [['OR', 'b', 'c']]]),
      ([a, g([b, ['|'], c])], [a, [['OR', b, c]]]),
      (['a', g(['b', '|'])], ['a', [['OR', 'b']]]),
      ([null_], [null_]),
      ([null_, '|', doubleNull], [['OR', null_, doubleNull]]),
    ]) {
      expect(debugOperatorize(value), result, reason: '$value');
    }
  });

  test('stringable', () {
    final dom = DomainParser({
      'name': {'string': 'Name', 'type': 'char'},
      'multiselection': {
        'string': 'MultiSelection',
        'type': 'multiselection',
        'selection': [
          ['foo', 'Foo'],
          ['bar', 'Bar'],
          ['baz', 'Baz'],
        ],
      },
      'relation': {
        'string': 'Relation',
        'type': 'many2one',
        'relation_fields': {
          'name': {'string': 'Name', 'type': 'char'},
        },
      },
      'relations': {'string': 'Relations', 'type': 'many2many'},
    });
    const valid = ['name', '=', 'Doe'];
    const invalid = ['surname', '=', 'John'];
    expect(dom.stringable([]), isTrue);
    expect(dom.stringable([[]]), isTrue);
    expect(dom.stringable([valid]), isTrue);
    expect(dom.stringable([invalid]), isFalse);
    expect(dom.stringable(['AND', valid]), isTrue);
    expect(dom.stringable(['AND', valid, invalid]), isFalse);
    expect(dom.stringable([[valid]]), isTrue);
    expect(dom.stringable([[valid], [invalid]]), isFalse);
    expect(dom.stringable([['multiselection', '=', null]]), isTrue);
    expect(dom.stringable([['multiselection', '=', '']]), isTrue);
    expect(dom.stringable([['multiselection', '=', 'foo']]), isFalse);
    expect(dom.stringable([['multiselection', '=', ['foo']]]), isTrue);
    expect(dom.stringable([['relation', '=', null]]), isTrue);
    expect(dom.stringable([['relation', '=', 'Foo']]), isTrue);
    expect(dom.stringable([['relation.rec_name', '=', 'Foo']]), isTrue);
    expect(dom.stringable([['relation', '=', 1]]), isFalse);
    expect(dom.stringable([['relations', '=', 'Foo']]), isTrue);
    expect(dom.stringable([['relations', '=', null]]), isTrue);
    expect(dom.stringable([['relations', 'in', ['Foo']]]), isTrue);
    expect(dom.stringable([['relations', 'in', [42]]]), isFalse);
    expect(dom.stringable([['relation.name', '=', 'Foo']]), isTrue);
  });

  test('string', () {
    final dom = DomainParser({
      'name': {'string': 'Name', 'type': 'char'},
      'surname': {'string': '(Sur)Name', 'type': 'char'},
      'date': {'string': 'Date', 'type': 'date'},
      'selection': {
        'string': 'Selection',
        'type': 'selection',
        'selection': [
          ['male', 'Male'],
          ['female', 'Female'],
          ['', ''],
        ],
      },
      'multiselection': {
        'string': 'MultiSelection',
        'type': 'multiselection',
        'selection': [
          ['foo', 'Foo'],
          ['bar', 'Bar'],
          ['baz', 'Baz'],
        ],
      },
      'reference': {
        'string': 'Reference',
        'type': 'reference',
        'selection': [
          ['spam', 'Spam'],
          ['ham', 'Ham'],
        ],
      },
      'many2one': {
        'string': 'Many2One',
        'name': 'many2one',
        'type': 'many2one',
        'relation_fields': {
          'name': {'string': 'Name', 'type': 'char'},
          'rec_name': {'string': 'Record Name', 'type': 'char'},
        },
      },
    });
    expect(dom.string([['name', '=', 'Doe']]), 'Name: =Doe');
    expect(dom.string([['name', '=', null]]), 'Name: =');
    expect(dom.string([['name', '=', '']]), 'Name: =""');
    expect(dom.string([['name', 'ilike', '%']]), 'Name: ');
    expect(dom.string([['name', 'ilike', '%Doe%']]), 'Name: Doe');
    expect(dom.string([['name', 'ilike', '%<%']]), 'Name: "" "<"');
    expect(dom.string([['name', 'ilike', 'Doe']]), 'Name: =Doe');
    expect(dom.string([['name', 'ilike', 'Doe%']]), 'Name: Doe%');
    expect(dom.string([['name', 'ilike', r'Doe\%']]), 'Name: =Doe%');
    expect(dom.string([['name', 'not ilike', '%Doe%']]), 'Name: !Doe');
    expect(dom.string([['name', 'in', ['John', 'Jane']]]), 'Name: John;Jane');
    expect(dom.string([['name', 'in', ['John', '']]]), 'Name: John;""');
    expect(dom.string([['name', 'in', ['John']]]), 'Name: =John');
    expect(dom.string([['name', 'not in', ['John', 'Jane']]]),
        'Name: !John;Jane');
    expect(dom.string([['name', 'not in', ['John']]]), 'Name: !=John');
    expect(
        dom.string([
          ['name', 'ilike', '%Doe%'],
          ['name', 'ilike', '%Jane%']
        ]),
        'Name: Doe Name: Jane');
    expect(
        dom.string([
          'AND',
          ['name', 'ilike', '%Doe%'],
          ['name', 'ilike', '%Jane%']
        ]),
        'Name: Doe Name: Jane');
    expect(
        dom.string([
          'OR',
          ['name', 'ilike', '%Doe%'],
          ['name', 'ilike', '%Jane%']
        ]),
        'Name: Doe | Name: Jane');
    expect(
        dom.string([
          ['name', 'ilike', '%Doe%'],
          [
            'OR',
            ['name', 'ilike', '%John%'],
            ['name', 'ilike', '%Jane%']
          ]
        ]),
        'Name: Doe (Name: John | Name: Jane)');
    expect(dom.string([]), '');
    expect(dom.string([['surname', 'ilike', '%Doe%']]), '"(Sur)Name": Doe');
    expect(dom.string([['date', '>=', const TrytonDate(2012, 10, 24)]]),
        'Date: >=${x(DateTime(2012, 10, 24))}');
    expect(dom.string([['selection', '=', '']]), 'Selection: ');
    expect(dom.string([['selection', '=', null]]), 'Selection: ');
    expect(dom.string([['selection', '!=', '']]), 'Selection: !""');
    expect(dom.string([['selection', '=', 'male']]), 'Selection: Male');
    expect(dom.string([['selection', '!=', 'male']]), 'Selection: !Male');
    expect(dom.string([['multiselection', '=', null]]), 'MultiSelection: =');
    expect(dom.string([['multiselection', '=', '']]), 'MultiSelection: =');
    expect(dom.string([['multiselection', '!=', '']]), 'MultiSelection: !=');
    expect(dom.string([['multiselection', '=', ['foo']]]),
        'MultiSelection: =Foo');
    expect(dom.string([['multiselection', '!=', ['foo']]]),
        'MultiSelection: !=Foo');
    expect(dom.string([['multiselection', '=', ['foo', 'bar']]]),
        'MultiSelection: =Foo;Bar');
    expect(dom.string([['multiselection', '!=', ['foo', 'bar']]]),
        'MultiSelection: !=Foo;Bar');
    expect(dom.string([['multiselection', 'in', ['foo']]]),
        'MultiSelection: Foo');
    expect(dom.string([['multiselection', 'not in', ['foo']]]),
        'MultiSelection: !Foo');
    expect(dom.string([['multiselection', 'in', ['foo', 'bar']]]),
        'MultiSelection: Foo;Bar');
    expect(dom.string([['multiselection', 'not in', ['foo', 'bar']]]),
        'MultiSelection: !Foo;Bar');
    expect(dom.string([['reference', 'ilike', '%foo%']]), 'Reference: foo');
    expect(dom.string([['reference.rec_name', 'ilike', '%bar%', 'spam']]),
        'Reference: Spam,bar');
    expect(dom.string([['reference.rec_name', '=', null, 'spam']]),
        'Reference: =Spam,');
    expect(dom.string([['reference', 'in', ['foo', 'bar']]]),
        'Reference: foo;bar');
    expect(dom.string([['many2one', 'ilike', '%John%']]), 'Many2One: John');
    expect(dom.string([['many2one.rec_name', 'in', ['John', 'Jane']]]),
        'Many2One: John;Jane');
    expect(dom.string([['many2one.rec_name', '=', 'John']]),
        'Many2One: =John');
    expect(dom.string([['many2one.rec_name', '=', '']]),
        '"Many2One.Record Name": =""');
    expect(dom.string([['many2one.rec_name', '=', null]]),
        '"Many2One.Record Name": =');
    expect(dom.string([['many2one.name', 'ilike', '%Foo%']]),
        'Many2One.Name: Foo');
  });

  test('group', () {
    final dom = DomainParser({
      'name': {'string': 'Name'},
      'firstname': {'string': 'First Name'},
      'surname': {'string': '(Sur)Name'},
      'relation': {
        'string': 'Relation',
        'relation': 'relation',
        'relation_fields': {
          'name': {'string': 'Name'},
        },
      },
    });
    List<Object?> g(String text) => debugGroup(dom, text);
    expect(g('Name: Doe'), [['Name', null, 'Doe']]);
    expect(g('"(Sur)Name": Doe'), [['(Sur)Name', null, 'Doe']]);
    expect(g('Name: Doe Name: John'), [
      ['Name', null, 'Doe'],
      ['Name', null, 'John']
    ]);
    expect(g('Name: Name: John'), [
      ['Name', null, null],
      ['Name', null, 'John']
    ]);
    expect(g('First Name: John'), [['First Name', null, 'John']]);
    expect(g('Name: Doe First Name: John'), [
      ['Name', null, 'Doe'],
      ['First Name', null, 'John']
    ]);
    expect(g('First Name: John Name: Doe'), [
      ['First Name', null, 'John'],
      ['Name', null, 'Doe']
    ]);
    expect(g('First Name: John First Name: Jane'), [
      ['First Name', null, 'John'],
      ['First Name', null, 'Jane']
    ]);
    expect(g('Name: John Doe'), [
      ['Name', null, 'John'],
      ['Doe']
    ]);
    expect(g('Name: "John Doe"'), [['Name', null, 'John Doe']]);
    expect(g('Doe Name: John'), [
      ['Doe'],
      ['Name', null, 'John']
    ]);
    expect(g('Name: =Doe'), [['Name', '=', 'Doe']]);
    expect(g('Name: =Doe Name: >John'), [
      ['Name', '=', 'Doe'],
      ['Name', '>', 'John']
    ]);
    expect(g('First Name: =John First Name: =Jane'), [
      ['First Name', '=', 'John'],
      ['First Name', '=', 'Jane']
    ]);
    expect(g('Name: John;Jane'), [
      ['Name', null, ['John', 'Jane']]
    ]);
    expect(g('Name: John;'), [
      ['Name', null, ['John']]
    ]);
    expect(g('Name: John;Jane Name: Doe'), [
      ['Name', null, ['John', 'Jane']],
      ['Name', null, 'Doe']
    ]);
    expect(g('Name: John; Name: Doe'), [
      ['Name', null, ['John']],
      ['Name', null, 'Doe']
    ]);
    expect(g('Name:'), [['Name', null, null]]);
    expect(g('Name: ='), [['Name', '=', null]]);
    expect(g('Name: =""'), [['Name', '=', '']]);
    expect(g('Name: = ""'), [['Name', '=', '']]);
    expect(g('Name: = Name: Doe'), [
      ['Name', '=', null],
      ['Name', null, 'Doe']
    ]);
    expect(g(r'Name: \"foo\"'), [['Name', null, '"foo"']]);
    expect(g('Name: "" <'), [['Name', '', '<']]);
    expect(g('Relation.Name: Test'), [['Relation.Name', null, 'Test']]);
  });

  test('parse_clause', () {
    final dom = DomainParser({
      'name': {'string': 'Name', 'name': 'name', 'type': 'char'},
      'integer': {'string': 'Integer', 'name': 'integer', 'type': 'integer'},
      'timestamp': {
        'name': 'timestamp',
        'string': 'Timestamp',
        'type': 'timestamp',
        'format': '"%H:%M:%S"',
      },
      'selection': {
        'string': 'Selection',
        'name': 'selection',
        'type': 'selection',
        'selection': [
          ['male', 'Male'],
          ['female', 'Female'],
        ],
      },
      'multiselection': {
        'string': 'MultiSelection',
        'name': 'multiselection',
        'type': 'multiselection',
        'selection': [
          ['foo', 'Foo'],
          ['bar', 'Bar'],
          ['baz', 'Baz'],
        ],
      },
      'reference': {
        'string': 'Reference',
        'name': 'reference',
        'type': 'reference',
        'selection': [
          ['spam', 'Spam'],
          ['ham', 'Ham'],
        ],
      },
      'many2one': {'string': 'Many2One', 'name': 'many2one', 'type': 'many2one'},
      'relation': {
        'string': 'Relation',
        'name': 'relation',
        'type': 'many2one',
        'relation_fields': {
          'name': {'string': 'Name', 'name': 'name', 'type': 'char'},
          'm2o': {
            'string': 'M2O',
            'name': 'm2o',
            'type': 'many2one',
            'relation_fields': {
              'foo': {'string': 'Foo', 'name': 'foo', 'type': 'integer'},
            },
          },
        },
      },
    });
    List<Object?> p(List<Object?> tokens) => debugParseClause(dom, tokens);
    expect(p([['John']]), [['rec_name', 'ilike', '%John%']]);
    expect(p([['Name', null, null]]), [['name', 'ilike', '%']]);
    expect(p([['Name', '', null]]), [['name', 'ilike', '%']]);
    expect(p([['Name', '=', null]]), [['name', '=', null]]);
    expect(p([['Name', '=', '']]), [['name', '=', '']]);
    expect(p([['Name', null, 'Doe']]), [['name', 'ilike', '%Doe%']]);
    expect(p([['Name', '!', 'Doe']]), [['name', 'not ilike', '%Doe%']]);
    expect(p([['Name', null, ['John', 'Jane']]]), [
      ['name', 'in', ['John', 'Jane']]
    ]);
    expect(p([['Name', '!', ['John', 'Jane']]]), [
      ['name', 'not in', ['John', 'Jane']]
    ]);
    expect(p([['Selection', null, null]]), [['selection', '=', null]]);
    expect(p([['Selection', null, '']]), [['selection', '=', '']]);
    expect(p([['Selection', null, ['Male', 'Female']]]), [
      ['selection', 'in', ['male', 'female']]
    ]);
    expect(p([['MultiSelection', null, null]]), [['multiselection', '=', null]]);
    expect(p([['MultiSelection', null, '']]), [
      ['multiselection', 'in', ['']]
    ]);
    expect(p([['MultiSelection', '=', '']]), [
      ['multiselection', '=', ['']]
    ]);
    expect(p([['MultiSelection', '!', '']]), [
      ['multiselection', 'not in', ['']]
    ]);
    expect(p([['MultiSelection', '!=', '']]), [
      ['multiselection', '!=', ['']]
    ]);
    expect(p([['MultiSelection', null, ['Foo', 'Bar']]]), [
      ['multiselection', 'in', ['foo', 'bar']]
    ]);
    expect(p([['MultiSelection', '=', ['Foo', 'Bar']]]), [
      ['multiselection', '=', ['foo', 'bar']]
    ]);
    expect(p([['MultiSelection', '!', ['Foo', 'Bar']]]), [
      ['multiselection', 'not in', ['foo', 'bar']]
    ]);
    expect(p([['MultiSelection', '!=', ['Foo', 'Bar']]]), [
      ['multiselection', '!=', ['foo', 'bar']]
    ]);
    expect(p([['Integer', null, null]]), [['integer', '=', null]]);
    expect(p([['Integer', null, '3..5']]), [
      [
        ['integer', '>=', 3],
        ['integer', '<=', 5]
      ]
    ]);
    expect(p([['Reference', null, 'foo']]), [['reference', 'ilike', '%foo%']]);
    expect(p([['Reference', null, 'Spam']]), [['reference', 'ilike', '%spam%']]);
    expect(p([['Reference', null, 'Spam,bar']]), [
      ['reference.rec_name', 'ilike', '%bar%', 'spam']
    ]);
    expect(p([['Reference', null, 'Spam,']]), [
      ['reference.rec_name', 'ilike', '%', 'spam']
    ]);
    expect(p([['Reference', null, ['foo', 'bar']]]), [
      ['reference', 'in', ['foo', 'bar']]
    ]);
    expect(
        p([
          'OR',
          ['Name', null, 'John'],
          ['Name', null, 'Jane']
        ]),
        [
          'OR',
          ['name', 'ilike', '%John%'],
          ['name', 'ilike', '%Jane%']
        ]);
    expect(p([['Many2One', null, 'John']]), [
      ['many2one.rec_name', 'ilike', '%John%']
    ]);
    expect(p([['Many2One', null, ['John', 'Jane']]]), [
      ['many2one.rec_name', 'in', ['John', 'Jane']]
    ]);
    expect(p([['Many2One', '=', null]]), [['many2one', '=', null]]);
    expect(p([['Many2One', '=', '']]), [['many2one', '=', null]]);
    expect(
        p([
          const TestGroup([
            ['John']
          ])
        ]),
        [
          [
            ['rec_name', 'ilike', '%John%']
          ]
        ]);
    expect(p([['Relation', null, 'Test']]), [
      ['relation.rec_name', 'ilike', '%Test%']
    ]);
    expect(p([['Relation.Name', null, 'Test']]), [
      ['relation.name', 'ilike', '%Test%']
    ]);
    expect(p([['Relation.M2O', null, 'Foo']]), [
      ['relation.m2o.rec_name', 'ilike', '%Foo%']
    ]);
    expect(p([['Relation.M2O.Foo', null, '42']]), [
      ['relation.m2o.foo', '=', 42]
    ]);
    expect(p([['OR']]), [['rec_name', 'ilike', '%OR%']]);
    expect(p([['AND']]), [['rec_name', 'ilike', '%AND%']]);

    expect(p([['Timestamp', null, null]]), [['timestamp', '=', null]]);
    expect(p([['Timestamp', '=', x(DateTime(2002, 12, 4))]]), [
      [
        ['timestamp', '>=', untimezoned(2002, 12, 4)],
        ['timestamp', '<', untimezoned(2002, 12, 5)]
      ]
    ]);
    expect(
        p([
          [
            'Timestamp',
            '=',
            strftime(DateTime(2002, 12, 4, 12, 30), '%x %X')
          ]
        ]),
        [
          ['timestamp', '=', untimezoned(2002, 12, 4, 12, 30)]
        ]);
    expect(
        p([
          [
            'Timestamp',
            null,
            [x(DateTime(2002, 12, 4)), x(DateTime(2002, 12, 5))]
          ]
        ]),
        [
          [
            'timestamp',
            'in',
            [untimezoned(2002, 12, 4), untimezoned(2002, 12, 5)]
          ]
        ]);
  });

  test('completion char', () {
    final dom = DomainParser({
      'name': {'string': 'Name', 'name': 'name', 'type': 'char'},
    });
    expect(dom.completion('Nam'), ['Name: ']);
    expect(dom.completion('Name:'), ['Name: ']);
    expect(dom.completion('Name: foo'), <String>[]);
    expect(dom.completion('Name: !='), <String>[]);
    expect(dom.completion('Name: !=foo'), <String>[]);
    expect(dom.completion(''), ['Name: ']);
    expect(dom.completion(' '), ['', 'Name: ']);
    expect(dom.completion('Name: foo |'), ['Name: foo']);
    expect(dom.completion('Name: foo (Name: foo | N'),
        ['Name: foo (Name: foo | Name: ']);
  });

  test('completion many2one', () {
    final dom = DomainParser({
      'relation': {
        'name': 'relation',
        'string': 'Relation',
        'type': 'many2one',
        'relation_fields': {
          'name': {'name': 'name', 'string': 'Name', 'type': 'char'},
        },
      },
    });
    expect(dom.completion('Relatio'), ['Relation: ', 'Relation.Name: ']);
  });

  test('completion boolean', () {
    final dom = DomainParser({
      'name': {'string': 'Active', 'name': 'active', 'type': 'boolean'},
    });
    expect(dom.completion('Act'), ['Active: ']);
    expect(dom.completion('Active:'),
        ['Active: ', 'Active: True', 'Active: False']);
    expect(dom.completion('Active: t'), ['Active: True', 'Active: False']);
    expect(dom.completion('Active: f'), ['Active: False', 'Active: True']);
  });

  // Not in the Python tests: parse end to end and the locale.
  test('parse: text → domain → text', () {
    final dom = DomainParser({
      'name': {'string': 'Name', 'type': 'char'},
      'amount': {'string': 'Amount', 'type': 'float'},
      'date': {'string': 'Date', 'type': 'date'},
    }, {
      'date_format': '%d.%m.%Y',
      'decimal_point': ',',
      'thousands_sep': '.',
    });
    expect(dom.parse('Name: Doe Amount: >1.000,5'), [
      ['name', 'ilike', '%Doe%'],
      ['amount', '>', 1000.5]
    ]);
    expect(dom.parse('Name: Doe | Name: Jane'), [
      'OR',
      ['name', 'ilike', '%Doe%'],
      ['name', 'ilike', '%Jane%']
    ]);
    // simplify removes the outer nesting (like Python).
    expect(dom.parse('Date: 01.02.2026..28.02.2026'), [
      ['date', '>=', const TrytonDate(2026, 2, 1)],
      ['date', '<=', const TrytonDate(2026, 2, 28)]
    ]);
    expect(dom.parse('free text'), [
      ['rec_name', 'ilike', '%free%'],
      ['rec_name', 'ilike', '%text%']
    ]);
    expect(dom.string([['amount', '>', 1234.5]]), 'Amount: >1.234,5');
    expect(dom.string([['date', '=', const TrytonDate(2026, 2, 1)]]),
        'Date: 01.02.2026');
    expect(dom.parse('Name: "unclosed'), [['name', 'ilike', '%unclosed%']]);
  });
}

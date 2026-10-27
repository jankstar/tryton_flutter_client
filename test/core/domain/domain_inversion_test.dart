import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/domain/domain_inversion.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

/// DomainInversion cases from SAO's tests/sao.js, translated 1:1.
/// `new Number(x)` (a boxed JS number) is represented by a [TrytonDecimal].
void main() {
  test('simple_inversion', () {
    var domain = <dynamic>[
      ['x', '=', 3]
    ];
    expect(domainInversion(domain, 'x'), [
      ['x', '=', 3]
    ]);

    domain = [];
    expect(domainInversion(domain, 'x'), true);
    expect(domainInversion(domain, 'y'), true);
    expect(domainInversion(domain, 'x', {'x': 5}), true);
    expect(domainInversion(domain, 'z', {'x': 7}), true);

    domain = [
      ['x.id', '>', 5]
    ];
    expect(domainInversion(domain, 'x'), [
      ['x.id', '>', 5]
    ]);
  });

  test('unconstrained_inversion', () {
    final domain = [
      ['x', '=', 3],
      ['y', 'in', ['a', 'b']]
    ];
    expect(domainInversion(domain, 'x'), [
      ['x', '=', 3]
    ]);
    expect(domainInversion(domain, 'x', {'y': 'a'}), [
      ['x', '=', 3]
    ]);
    expect(domainInversion(domain, 'x', {'y': 'c'}), false);
  });

  test('constrained_equal_inversion', () {
    final domain = [
      ['x', '=', 3],
      ['y', '=', 'a']
    ];
    expect(domainInversion(domain, 'x'), [
      ['x', '=', 3]
    ]);
    expect(domainInversion(domain, 'x', {'y': 'a'}), [
      ['x', '=', 3]
    ]);
    expect(domainInversion(domain, 'x', {'y': 'c'}), [
      ['x', '=', 3]
    ]);
  });

  test('constrained_in_inversion (SAO 8.2; Python 8.0 gives false)', () {
    final domain = [
      ['x', '=', 3],
      ['y', 'in', ['a']]
    ];
    expect(domainInversion(domain, 'x'), [
      ['x', '=', 3]
    ]);
    expect(domainInversion(domain, 'x', {'y': 'a'}), [
      ['x', '=', 3]
    ]);
    expect(domainInversion(domain, 'x', {'y': 'c'}), [
      ['x', '=', 3]
    ]);
  });

  test('and_inversion', () {
    var domain = [
      ['x', '=', 3],
      ['y', '>', 5]
    ];
    expect(domainInversion(domain, 'x'), [
      ['x', '=', 3]
    ]);
    expect(domainInversion(domain, 'x', {'y': 4}), false);
    expect(domainInversion(domain, 'x', {'y': 6}), [
      ['x', '=', 3]
    ]);

    domain = [
      ['x', '=', 3],
      ['y', '=', 5]
    ];
    expect(domainInversion(domain, 'z'), true);
    expect(domainInversion(domain, 'z', {'x': 2, 'y': 7}), true);
    expect(domainInversion(domain, 'x', {'y': null}), [
      ['x', '=', 3]
    ]);

    domain = [
      ['x.id', '>', 5],
      ['y', '<', 3]
    ];
    expect(domainInversion(domain, 'y'), [
      ['y', '<', 3]
    ]);
    expect(domainInversion(domain, 'y', {'x': 3}), [
      ['y', '<', 3]
    ]);
    expect(domainInversion(domain, 'x'), [
      ['x.id', '>', 5]
    ]);
  });

  test('or_inversion', () {
    var domain = <dynamic>[
      'OR',
      ['x', '=', 3],
      ['y', '>', 5],
      ['z', '=', 'abc']
    ];
    expect(domainInversion(domain, 'x'), true);
    expect(domainInversion(domain, 'x', {'y': 4}), true);
    expect(domainInversion(domain, 'x', {'y': 4, 'z': 'ab'}), [
      ['x', '=', 3]
    ]);
    expect(domainInversion(domain, 'x', {'y': 7}), true);
    expect(domainInversion(domain, 'x', {'y': 7, 'z': 'b'}), true);
    expect(domainInversion(domain, 'x', {'z': 'abc'}), true);
    expect(domainInversion(domain, 'x', {'y': 4, 'z': 'abc'}), true);

    domain = [
      'OR',
      ['x', '=', 3],
      ['y', '=', 5]
    ];
    expect(domainInversion(domain, 'x', {'y': null}), [
      ['x', '=', 3]
    ]);

    domain = [
      'OR',
      ['x', '=', 3],
      ['y', '>', 5]
    ];
    expect(domainInversion(domain, 'z'), true);

    domain = [
      'OR',
      ['x.id', '>', 5],
      ['y', '<', 3]
    ];
    expect(domainInversion(domain, 'y'), true);
    expect(domainInversion(domain, 'y', {'z': 4}), true);
    expect(domainInversion(domain, 'y', {'x': 3}), true);

    domain = [
      'OR',
      ['length', '>', 5],
      ['language.code', '=', 'de_DE']
    ];
    expect(domainInversion(domain, 'length', {'length': 0, 'name': 'n'}),
        true);
  });

  test('orand_inversion', () {
    final domain = [
      'OR',
      [
        ['x', '=', 3],
        ['y', '>', 5],
        ['z', '=', 'abc']
      ],
      [
        ['x', '=', 4]
      ],
      [
        ['y', '>', 6]
      ]
    ];
    expect(domainInversion(domain, 'x'), true);
    expect(domainInversion(domain, 'x', {'y': 4}), true);
    expect(domainInversion(domain, 'x', {'z': 'abc', 'y': 7}), true);
    expect(domainInversion(domain, 'x', {'y': 7}), true);
    expect(domainInversion(domain, 'x', {'z': 'ab'}), true);
  });

  test('andor_inversion', () {
    final domain = [
      [
        'OR',
        ['x', '=', 4],
        ['y', '>', 6]
      ],
      ['z', '=', 3]
    ];
    final z3 = [
      ['z', '=', 3]
    ];
    expect(domainInversion(domain, 'z'), z3);
    expect(domainInversion(domain, 'z', {'z': 3}), z3);
    expect(domainInversion(domain, 'z', {'x': 5, 'y': 5}), z3);
    expect(domainInversion(domain, 'z', {'x': 5, 'y': 7}), z3);
  });

  test('andand_invertion', () {
    var domain = <dynamic>[
      [
        ['x', '=', 4],
        ['y', '>', 6]
      ],
      ['z', '=', 3]
    ];
    final z3 = [
      ['z', '=', 3]
    ];
    expect(domainInversion(domain, 'z'), z3);
    expect(domainInversion(domain, 'z', {'x': 5}), z3);
    expect(domainInversion(domain, 'z', {'y': 5}), z3);
    expect(domainInversion(domain, 'z', {'x': 4, 'y': 7}), z3);

    domain = [
      [
        ['x', '=', 4],
        ['y', '>', 6],
        ['z', '=', 2]
      ],
      ['w', '=', 2]
    ];
    expect(domainInversion(domain, 'z', {'x': 4}), [
      ['z', '=', 2]
    ]);
  });

  test('oror_invertion', () {
    final domain = [
      'OR',
      [
        'OR',
        ['x', '=', 3],
        ['y', '>', 5]
      ],
      [
        'OR',
        ['x', '=', 2],
        ['z', '=', 'abc']
      ],
      [
        'OR',
        ['y', '=', 8],
        ['z', '=', 'y']
      ]
    ];
    expect(domainInversion(domain, 'x'), true);
    expect(domainInversion(domain, 'x', {'y': 4}), true);
    expect(domainInversion(domain, 'x', {'z': 'ab'}), true);
    expect(domainInversion(domain, 'x', {'y': 7}), true);
    expect(domainInversion(domain, 'x', {'z': 'abc'}), true);
    expect(domainInversion(domain, 'x', {'z': 'y'}), true);
    expect(domainInversion(domain, 'x', {'y': 8}), true);
    expect(domainInversion(domain, 'x', {'y': 8, 'z': 'b'}), true);
    expect(domainInversion(domain, 'x', {'y': 4, 'z': 'y'}), true);
    expect(domainInversion(domain, 'x', {'y': 7, 'z': 'abc'}), true);
    expect(domainInversion(domain, 'x', {'y': 4, 'z': 'b'}), [
      'OR',
      ['x', '=', 3],
      ['x', '=', 2]
    ]);
  });

  test('parse', () {
    List<String> vars(dynamic d) =>
        ((parse(d) as DomainAnd).variables.toList()..sort());
    expect(
        vars([
          ['x', '=', 5]
        ]),
        ['x']);
    expect(
        vars([
          'OR',
          ['x', '=', 4],
          ['y', '>', 6]
        ]),
        ['x', 'y']);
    expect(
        vars([
          [
            'OR',
            ['x', '=', 4],
            ['y', '>', 6]
          ],
          ['z', '=', 3]
        ]),
        ['x', 'y', 'z']);
    expect(
        vars([
          [
            ['x', '=', 4],
            ['y', '>', 6]
          ],
          ['z', '=', 3]
        ]),
        ['x', 'y', 'z']);
  });

  test('simplify', () {
    final x3 = ['x', '=', 3];
    final cases = <List<dynamic>>[
      [
        [x3],
        [x3]
      ],
      [
        [
          [x3]
        ],
        [x3]
      ],
      [
        [
          [
            x3,
            ['y', '=', 4]
          ]
        ],
        [
          x3,
          ['y', '=', 4]
        ]
      ],
      [
        ['OR', x3],
        [x3]
      ],
      [
        [
          'OR',
          [x3],
          [
            ['y', '=', 5]
          ]
        ],
        [
          'OR',
          x3,
          ['y', '=', 5]
        ]
      ],
      [
        [
          'OR',
          x3,
          [
            'AND',
            ['y', '=', 5]
          ]
        ],
        [
          'OR',
          x3,
          ['y', '=', 5]
        ]
      ],
      [
        [
          'OR',
          ['x', '=', 1],
          [
            'OR',
            ['x', '=', 2],
            ['x', '=', 3]
          ]
        ],
        [
          'OR',
          ['x', '=', 1],
          ['x', '=', 2],
          ['x', '=', 3]
        ]
      ],
      [
        [
          x3,
          ['OR']
        ],
        [x3]
      ],
      [
        ['OR', x3, []],
        []
      ],
      [
        [
          'OR',
          x3,
          ['OR']
        ],
        []
      ],
      [
        [x3, []],
        [x3]
      ],
      [
        [
          x3,
          ['AND']
        ],
        [x3]
      ],
      [
        ['AND'],
        []
      ],
      [
        ['OR'],
        []
      ],
    ];
    for (final [domain, result] in cases) {
      expect(simplify(domain), result, reason: 'simplify($domain)');
    }
  });

  test('simplify deduplicate', () {
    final clause = ['x', '=', 3];
    final another = ['y', '=', 4];
    final third = ['z', '=', 5];
    final cases = <List<dynamic>>[
      [[], []],
      [
        ['OR', []],
        []
      ],
      [
        ['AND', []],
        []
      ],
      [
        [clause],
        [clause]
      ],
      [
        ['OR', clause],
        [clause]
      ],
      [
        [clause, clause],
        [clause]
      ],
      [
        ['OR', clause, clause],
        [clause]
      ],
      [
        [
          clause,
          [clause, clause]
        ],
        [clause]
      ],
      [
        [clause, another],
        [clause, another]
      ],
      [
        ['OR', clause, another],
        ['OR', clause, another]
      ],
      [
        [clause, clause, another],
        [clause, another]
      ],
      [
        [
          clause,
          [clause, clause],
          another
        ],
        [clause, another]
      ],
      [
        [clause, clause, another, another],
        [clause, another]
      ],
      [
        [clause, another, clause, another],
        [clause, another]
      ],
      [
        [
          'AND',
          ['OR', clause, another],
          third
        ],
        [
          'AND',
          ['OR', clause, another],
          third
        ]
      ],
    ];
    for (final [domain, result] in cases) {
      expect(simplify(domain), result, reason: 'simplify($domain)');
    }
  });

  test('merge', () {
    final cases = <List<dynamic>>[
      [
        [
          ['x', '=', 6],
          ['y', '=', 7]
        ],
        [
          'AND',
          ['x', '=', 6],
          ['y', '=', 7]
        ]
      ],
      [
        [
          'AND',
          ['x', '=', 6],
          ['y', '=', 7]
        ],
        [
          'AND',
          ['x', '=', 6],
          ['y', '=', 7]
        ]
      ],
      [
        [
          ['z', '=', 8],
          [
            'AND',
            ['x', '=', 6],
            ['y', '=', 7]
          ]
        ],
        [
          'AND',
          ['z', '=', 8],
          ['x', '=', 6],
          ['y', '=', 7]
        ]
      ],
      [
        [
          'OR',
          ['x', '=', 1],
          ['y', '=', 2],
          ['z', '=', 3]
        ],
        [
          'OR',
          ['x', '=', 1],
          ['y', '=', 2],
          ['z', '=', 3]
        ]
      ],
      [
        [
          'OR',
          ['x', '=', 1],
          [
            'OR',
            ['y', '=', 2],
            ['z', '=', 3]
          ]
        ],
        [
          'OR',
          ['x', '=', 1],
          ['y', '=', 2],
          ['z', '=', 3]
        ]
      ],
      [
        [
          'OR',
          ['x', '=', 1],
          [
            'AND',
            ['y', '=', 2],
            ['z', '=', 3]
          ]
        ],
        [
          'OR',
          ['x', '=', 1],
          [
            'AND',
            ['y', '=', 2],
            ['z', '=', 3]
          ]
        ]
      ],
      [
        [
          ['z', '=', 8],
          [
            'OR',
            ['x', '=', 6],
            ['y', '=', 7]
          ]
        ],
        [
          'AND',
          ['z', '=', 8],
          [
            'OR',
            ['x', '=', 6],
            ['y', '=', 7]
          ]
        ]
      ],
      [
        [
          'AND',
          [
            'OR',
            ['a', '=', 1],
            ['b', '=', 2]
          ],
          [
            'OR',
            ['c', '=', 3],
            [
              'AND',
              ['d', '=', 4],
              ['d2', '=', 6]
            ]
          ],
          [
            'AND',
            ['d', '=', 5],
            ['e', '=', 6]
          ],
          ['f', '=', 7]
        ],
        [
          'AND',
          [
            'OR',
            ['a', '=', 1],
            ['b', '=', 2]
          ],
          [
            'OR',
            ['c', '=', 3],
            [
              'AND',
              ['d', '=', 4],
              ['d2', '=', 6]
            ]
          ],
          ['d', '=', 5],
          ['e', '=', 6],
          ['f', '=', 7]
        ]
      ],
    ];
    for (final [domain, result] in cases) {
      expect(merge(domain), result, reason: 'merge($domain)');
    }
  });

  test('concat', () {
    final domain1 = [
      ['a', '=', 1]
    ];
    final domain2 = [
      ['b', '=', 2]
    ];
    expect(concat([domain1, domain2]), [
      'AND',
      ['a', '=', 1],
      ['b', '=', 2]
    ]);
    expect(concat([[], domain1]), domain1);
    expect(concat([domain2, []]), domain2);
    expect(concat([[], []]), []);
    expect(concat([domain1, domain2], domOperator: 'OR'), [
      'OR',
      ['a', '=', 1],
      ['b', '=', 2]
    ]);
  });

  test('unique_value', () {
    (bool, String?, dynamic) uv(dynamic d, [bool single = true]) =>
        uniqueValue(d, singleValue: single);
    const none = (false, null, null);
    expect(
        uv([
          ['a', '=', 1]
        ]),
        (true, 'a', 1));
    expect(
        uv([
          ['a', '!=', 1]
        ]).$1,
        isFalse);
    expect(
        uv([
          ['a', '=', 1],
          ['a', '=', 2]
        ]).$1,
        isFalse);
    expect(
        uv([
          ['a.b', '=', 1]
        ]).$1,
        isFalse);
    var r = uv([
      ['a.id', '=', 1, 'model']
    ]);
    expect((r.$1, r.$2), (true, 'a.id'));
    expect(r.$3, ['model', 1]);
    var domain = [
      ['a.b.id', '=', 1, 'model']
    ];
    expect(uv(domain), none);
    expect(uv(domain, false), none);
    domain = [
      ['a', 'in', [1]]
    ];
    expect(uv(domain), (true, 'a', 1));
    expect(uv(domain, false), none);
    expect(
        uv([
          ['a', 'in', [1, 2]]
        ]),
        none);
    expect(
        uv([
          ['a', 'in', []]
        ]),
        none);
    expect(
        uv([
          ['a.b', 'in', [1]]
        ]),
        none);
    domain = [
      ['a.id', 'in', [1], 'model']
    ];
    r = uv(domain);
    expect((r.$1, r.$2), (true, 'a.id'));
    expect(r.$3, ['model', 1]);
    expect(uv(domain, false), none);
  });

  test('evaldomain', () {
    final now = DateTime.now();
    final today = TrytonDate(now.year, now.month, now.day);
    const n42 = TrytonDecimal('42');
    const n0 = TrytonDecimal('0');
    final cases = <List<dynamic>>[
      [
        [
          ['x', '=', 42]
        ],
        {'x': 42},
        true
      ],
      [
        [
          ['x', '=', 42]
        ],
        {'x': n42},
        true
      ],
      [
        [
          ['x', '=', 42]
        ],
        {'x': 0},
        false
      ],
      [
        [
          ['x', '=', 42]
        ],
        {'x': n0},
        false
      ],
      [
        [
          ['x', '=', 42]
        ],
        {'x': null},
        false
      ],
      [
        [
          ['x', '=', n42]
        ],
        {'x': 42},
        true
      ],
      [
        [
          ['x', '=', n42]
        ],
        {'x': n42},
        true
      ],
      [
        [
          ['x', '=', n42]
        ],
        {'x': 0},
        false
      ],
      [
        [
          ['x', '=', n42]
        ],
        {'x': n0},
        false
      ],
      [
        [
          ['x', '=', n42]
        ],
        {'x': null},
        false
      ],
      [
        [
          ['x', '=', 0]
        ],
        {'x': 0},
        true
      ],
      [
        [
          ['x', '=', 0]
        ],
        {'x': n0},
        true
      ],
      [
        [
          ['x', '=', 0]
        ],
        {'x': null},
        false
      ],
      [
        [
          ['x', '=', n0]
        ],
        {'x': 0},
        true
      ],
      [
        [
          ['x', '=', n0]
        ],
        {'x': n0},
        true
      ],
      [
        [
          ['x', '=', n0]
        ],
        {'x': null},
        false
      ],
      [
        [
          ['x', '=', null]
        ],
        {'x': 0},
        false
      ],
      [
        [
          ['x', '=', null]
        ],
        {'x': n0},
        false
      ],
      [
        [
          ['x', '=', null]
        ],
        {'x': null},
        true
      ],
      [
        [
          ['x', '!=', 42]
        ],
        {'x': 42},
        false
      ],
      [
        [
          ['x', '!=', 42]
        ],
        {'x': n42},
        false
      ],
      [
        [
          ['x', '!=', 42]
        ],
        {'x': 0},
        true
      ],
      [
        [
          ['x', '!=', 42]
        ],
        {'x': n0},
        true
      ],
      [
        [
          ['x', '!=', 42]
        ],
        {'x': null},
        true
      ],
      [
        [
          ['x', '!=', n42]
        ],
        {'x': 42},
        false
      ],
      [
        [
          ['x', '!=', n42]
        ],
        {'x': n42},
        false
      ],
      [
        [
          ['x', '!=', n42]
        ],
        {'x': 0},
        true
      ],
      [
        [
          ['x', '!=', n42]
        ],
        {'x': n0},
        true
      ],
      [
        [
          ['x', '!=', n42]
        ],
        {'x': null},
        true
      ],
      [
        [
          ['x', '!=', 0]
        ],
        {'x': 0},
        false
      ],
      [
        [
          ['x', '!=', 0]
        ],
        {'x': n0},
        false
      ],
      [
        [
          ['x', '!=', 0]
        ],
        {'x': null},
        true
      ],
      [
        [
          ['x', '!=', n0]
        ],
        {'x': 0},
        false
      ],
      [
        [
          ['x', '!=', n0]
        ],
        {'x': n0},
        false
      ],
      [
        [
          ['x', '!=', n0]
        ],
        {'x': null},
        true
      ],
      [
        [
          ['x', '!=', null]
        ],
        {'x': 0},
        true
      ],
      [
        [
          ['x', '!=', null]
        ],
        {'x': n0},
        true
      ],
      [
        [
          ['x', '!=', null]
        ],
        {'x': null},
        false
      ],
      [
        [
          ['x', '>', 5]
        ],
        {'x': 6},
        true
      ],
      [
        [
          ['x', '>', 5]
        ],
        {'x': 4},
        false
      ],
      [
        [
          ['x', '>', null]
        ],
        {'x': today},
        false
      ],
      [
        [
          ['x', '>', null]
        ],
        {'x': now},
        false
      ],
      [
        [
          ['x', '<', today]
        ],
        {'x': null},
        false
      ],
      [
        [
          ['x', '<', now]
        ],
        {'x': null},
        false
      ],
      [
        [
          ['x', 'in', [3, 5]]
        ],
        {'x': 3},
        true
      ],
      [
        [
          ['x', 'in', [3, 5]]
        ],
        {'x': 4},
        false
      ],
      [
        [
          ['x', 'in', [3, 5]]
        ],
        {
          'x': [3]
        },
        true
      ],
      [
        [
          ['x', 'in', [3, 5]]
        ],
        {
          'x': [3, 4]
        },
        true
      ],
      [
        [
          ['x', 'in', [3, 5]]
        ],
        {
          'x': [1, 2]
        },
        false
      ],
      [
        [
          ['x', 'in', [3, 5]]
        ],
        {'x': null},
        false
      ],
      [
        [
          ['x', 'in', [1, null]]
        ],
        {'x': null},
        true
      ],
      [
        [
          ['x', 'in', [1, null]]
        ],
        {'x': 2},
        false
      ],
      [
        [
          ['x', 'not in', [3, 5]]
        ],
        {'x': 3},
        false
      ],
      [
        [
          ['x', 'not in', [3, 5]]
        ],
        {'x': 4},
        true
      ],
      [
        [
          ['x', 'not in', [3, 5]]
        ],
        {
          'x': [3]
        },
        false
      ],
      [
        [
          ['x', 'not in', [3, 5]]
        ],
        {
          'x': [3, 4]
        },
        false
      ],
      [
        [
          ['x', 'not in', [3, 5]]
        ],
        {
          'x': [1, 2]
        },
        true
      ],
      [
        [
          ['x', 'not in', [3, 5]]
        ],
        {'x': null},
        false
      ],
      [
        [
          ['x', 'not in', [1, null]]
        ],
        {'x': null},
        false
      ],
      [
        [
          ['x', 'not in', [1, null]]
        ],
        {'x': 2},
        true
      ],
      [
        [
          ['x', 'like', 'abc']
        ],
        {'x': 'abc'},
        true
      ],
      [
        [
          ['x', 'like', 'abc']
        ],
        {'x': ''},
        false
      ],
      [
        [
          ['x', 'like', 'abc']
        ],
        {'x': 'xyz'},
        false
      ],
      [
        [
          ['x', 'like', 'abc']
        ],
        {'x': 'abcd'},
        false
      ],
      [
        [
          ['x', 'not like', 'abc']
        ],
        {'x': 'xyz'},
        true
      ],
      [
        [
          ['x', 'not like', 'abc']
        ],
        {'x': 'ABC'},
        true
      ],
      [
        [
          ['x', 'not like', 'abc']
        ],
        {'x': 'abc'},
        false
      ],
      [
        [
          ['x', 'not ilike', 'abc']
        ],
        {'x': 'xyz'},
        true
      ],
      [
        [
          ['x', 'not ilike', 'abc']
        ],
        {'x': 'ABC'},
        false
      ],
      [
        [
          ['x', 'not ilike', 'abc']
        ],
        {'x': 'abc'},
        false
      ],
      [
        [
          ['x', 'like', 'a%']
        ],
        {'x': 'a'},
        true
      ],
      [
        [
          ['x', 'like', 'a%']
        ],
        {'x': 'abcde'},
        true
      ],
      [
        [
          ['x', 'like', 'a%']
        ],
        {'x': ''},
        false
      ],
      [
        [
          ['x', 'like', 'a%']
        ],
        {'x': 'ABCDE'},
        false
      ],
      [
        [
          ['x', 'like', 'a%']
        ],
        {'x': 'xyz'},
        false
      ],
      [
        [
          ['x', 'ilike', 'a%']
        ],
        {'x': 'a'},
        true
      ],
      [
        [
          ['x', 'ilike', 'a%']
        ],
        {'x': 'A'},
        true
      ],
      [
        [
          ['x', 'ilike', 'a%']
        ],
        {'x': ''},
        false
      ],
      [
        [
          ['x', 'ilike', 'a%']
        ],
        {'x': 'xyz'},
        false
      ],
      [
        [
          ['x', 'like', 'a_']
        ],
        {'x': 'ab'},
        true
      ],
      [
        [
          ['x', 'like', 'a_']
        ],
        {'x': 'a'},
        false
      ],
      [
        [
          ['x', 'like', 'a_']
        ],
        {'x': 'abc'},
        false
      ],
      [
        [
          ['x', 'like', r'a\%b']
        ],
        {'x': 'a%b'},
        true
      ],
      [
        [
          ['x', 'like', r'a\%b']
        ],
        {'x': 'ab'},
        false
      ],
      [
        [
          ['x', 'like', r'a\%b']
        ],
        {'x': 'a123b'},
        false
      ],
      [
        [
          ['x', 'like', r'\%b']
        ],
        {'x': '%b'},
        true
      ],
      [
        [
          ['x', 'like', r'\%b']
        ],
        {'x': 'b'},
        false
      ],
      [
        [
          ['x', 'like', r'\%b']
        ],
        {'x': '123b'},
        false
      ],
      [
        [
          ['x', 'like', r'a\_c']
        ],
        {'x': 'a_c'},
        true
      ],
      [
        [
          ['x', 'like', r'a\_c']
        ],
        {'x': 'abc'},
        false
      ],
      [
        [
          ['x', 'like', r'a\_c']
        ],
        {'x': 'ac'},
        false
      ],
      [
        [
          ['x', 'like', r'a\\_c']
        ],
        {'x': r'a\bc'},
        true
      ],
      [
        [
          ['x', 'like', r'a\\_c']
        ],
        {'x': 'abc'},
        false
      ],
      [
        [
          'OR',
          ['x', '>', 10],
          ['x', '<', 0]
        ],
        {'x': 11},
        true
      ],
      [
        [
          'OR',
          ['x', '>', 10],
          ['x', '<', 0]
        ],
        {'x': -4},
        true
      ],
      [
        [
          'OR',
          ['x', '>', 10],
          ['x', '<', 0]
        ],
        {'x': 5},
        false
      ],
      [
        [
          'OR',
          ['x', '>', 0],
          ['x', '=', null]
        ],
        {'x': 1},
        true
      ],
      [
        [
          'OR',
          ['x', '>', 0],
          ['x', '=', null]
        ],
        {'x': null},
        true
      ],
      [
        [
          'OR',
          ['x', '>', 0],
          ['x', '=', null]
        ],
        {'x': -1},
        false
      ],
      [
        [
          'OR',
          ['x', '>', 0],
          ['x', '=', null]
        ],
        {'x': 0},
        false
      ],
      for (final (x, r) in [
        (1, false),
        (3, true),
        (2, true),
        (4, false),
        (5, false),
        (6, false)
      ])
        [
          [
            ['x', '>', 0],
            [
              'OR',
              ['x', '=', 3],
              ['x', '=', 2]
            ]
          ],
          {'x': x},
          r
        ],
      for (final (x, r) in [
        (4, true),
        (7, true),
        (3, false),
        (5, false),
        (11, false)
      ])
        [
          [
            'OR',
            ['x', '=', 4],
            [
              ['x', '>', 6],
              ['x', '<', 10]
            ]
          ],
          {'x': x},
          r
        ],
      [
        [
          ['x', '=', 'test,1']
        ],
        {
          'x': ['test', 1]
        },
        true
      ],
      [
        [
          ['x', '=', 'test,1']
        ],
        {'x': 'test,1'},
        true
      ],
      [
        [
          ['x', '=', 'test,1']
        ],
        {
          'x': ['test', 2]
        },
        false
      ],
      [
        [
          ['x', '=', 'test,1']
        ],
        {'x': 'test,2'},
        false
      ],
      [
        [
          [
            'x',
            '=',
            ['test', 1]
          ]
        ],
        {
          'x': ['test', 1]
        },
        true
      ],
      [
        [
          [
            'x',
            '=',
            ['test', 1]
          ]
        ],
        {'x': 'test,1'},
        true
      ],
      [
        [
          [
            'x',
            '=',
            ['test', 1]
          ]
        ],
        {
          'x': ['test', 2]
        },
        false
      ],
      [
        [
          [
            'x',
            '=',
            ['test', 1]
          ]
        ],
        {'x': 'test,2'},
        false
      ],
      [
        [
          ['x', '=', 1]
        ],
        {
          'x': [1, 2]
        },
        true
      ],
      [
        [
          ['x', '=', 1]
        ],
        {
          'x': [2]
        },
        false
      ],
      [
        [
          ['x', '=', null]
        ],
        {'x': []},
        true
      ],
      [
        [
          [
            'x',
            '=',
            ['foo', 1]
          ]
        ],
        {'x': 'foo,1'},
        true
      ],
      [
        [
          [
            'x',
            '=',
            ['foo', 1]
          ]
        ],
        {
          'x': ['foo', 1]
        },
        true
      ],
      [
        [
          ['x', '=', 'foo,1']
        ],
        {
          'x': ['foo', 1]
        },
        true
      ],
    ];
    for (final [domain, context, result] in cases) {
      expect(evalDomain(domain, context as Map), result,
          reason: 'eval_domain($domain, $context)');
    }
  });

  test('localize', () {
    var domain = <dynamic>[
      ['x', '=', 5]
    ];
    expect(localizeDomain(domain), [
      ['x', '=', 5]
    ]);

    domain = [
      ['x', '=', 5],
      ['x.code', '=', 7]
    ];
    expect(localizeDomain(domain, 'x'), [
      ['id', '=', 5],
      ['code', '=', 7]
    ]);

    domain = [
      ['x', 'ilike', 'foo%'],
      ['x.code', '=', 'test']
    ];
    expect(localizeDomain(domain, 'x'), [
      ['rec_name', 'ilike', 'foo%'],
      ['code', '=', 'test']
    ]);

    domain = [
      'OR',
      [
        'AND',
        ['x', '>', 7],
        ['x', '<', 15]
      ],
      ['x.code', '=', 8]
    ];
    expect(localizeDomain(domain, 'x'), [
      'OR',
      [
        'AND',
        ['id', '>', 7],
        ['id', '<', 15]
      ],
      ['code', '=', 8]
    ]);

    domain = [
      ['x', 'child_of', [1]]
    ];
    expect(localizeDomain(domain, 'x'), [
      ['x', 'child_of', [1]]
    ]);

    domain = [
      ['x.y', 'child_of', [1], 'parent']
    ];
    expect(localizeDomain(domain, 'x'), [
      ['y', 'child_of', [1], 'parent']
    ]);

    domain = [
      ['x.y.z', 'child_of', [1], 'parent', 'model']
    ];
    expect(localizeDomain(domain, 'x'), [
      ['y.z', 'child_of', [1], 'parent', 'model']
    ]);

    domain = [
      ['x', 'child_of', [1], 'y']
    ];
    expect(localizeDomain(domain, 'x'), [
      ['y', 'child_of', [1]]
    ]);

    domain = [
      ['x.id', '=', 1, 'y']
    ];
    expect(localizeDomain(domain, 'x', false), [
      ['id', '=', 1, 'y']
    ]);
    expect(localizeDomain(domain, 'x', true), [
      ['id', '=', 1]
    ]);

    domain = [
      ['a.b.c', '=', 1, 'y', 'z']
    ];
    expect(localizeDomain(domain, 'x', false), [
      ['b.c', '=', 1, 'y', 'z']
    ]);
    expect(localizeDomain(domain, 'x', true), [
      ['b.c', '=', 1, 'z']
    ]);
  });

  test('prepare_reference_domain', () {
    expect(
        prepareReferenceDomain([
          ['x', 'like', 'A%']
        ], 'x'),
        [[]]);
    expect(
        prepareReferenceDomain([
          ['x', '=', 'A']
        ], 'x'),
        [[]]);
    expect(
        prepareReferenceDomain([
          ['x.y', 'child_of', [1], 'model', 'parent']
        ], 'x'),
        [
          ['x.y', 'child_of', [1], 'model', 'parent']
        ]);
    expect(
        prepareReferenceDomain([
          ['x.y', 'like', 'A%', 'model']
        ], 'x'),
        [
          ['x.y', 'like', 'A%', 'model']
        ]);
    expect(
        prepareReferenceDomain([
          ['x', '=', 'model,1']
        ], 'x'),
        [
          ['x.id', '=', 1, 'model']
        ]);
    expect(
        prepareReferenceDomain([
          ['x', '!=', 'model,1']
        ], 'x'),
        [
          ['x.id', '!=', 1, 'model']
        ]);
    expect(
        prepareReferenceDomain([
          ['x', '=', 'model,%']
        ], 'x'),
        [
          ['x.id', '!=', null, 'model']
        ]);
    expect(
        prepareReferenceDomain([
          ['x', '!=', 'model,%']
        ], 'x'),
        [
          ['x', 'not like', 'model,%']
        ]);
    expect(
        prepareReferenceDomain([
          [
            'x',
            'in',
            ['model_a,1', 'model_b,%', 'model_c,3', 'model_a,2']
          ]
        ], 'x'),
        [
          [
            'OR',
            ['x.id', 'in', [1, 2], 'model_a'],
            ['x.id', '!=', null, 'model_b'],
            ['x.id', 'in', [3], 'model_c'],
          ]
        ]);
    expect(
        prepareReferenceDomain([
          [
            'x',
            'not in',
            ['model_a,1', 'model_b,%', 'model_c,3', 'model_a,2']
          ]
        ], 'x'),
        [
          [
            'AND',
            ['x.id', 'not in', [1, 2], 'model_a'],
            ['x', 'not like', 'model_b,%'],
            ['x.id', 'not in', [3], 'model_c'],
          ]
        ]);
    expect(
        prepareReferenceDomain([
          [
            'x',
            'in',
            ['model_a,1', 'foo']
          ]
        ], 'x'),
        [[]]);
  });

  test('extract_reference_models', () {
    var domain = <dynamic>[
      ['x', 'like', 'A%']
    ];
    expect(extractReferenceModels(domain, 'x'), <String>[]);
    expect(extractReferenceModels(domain, 'y'), <String>[]);

    domain = [
      ['x', 'like', 'A%', 'model']
    ];
    expect(extractReferenceModels(domain, 'x'), ['model']);
    expect(extractReferenceModels(domain, 'y'), <String>[]);

    domain = [
      'OR',
      ['x', 'like', 'A%', 'model_A'],
      ['x', 'like', 'B%', 'model_B']
    ];
    expect(extractReferenceModels(domain, 'x'), ['model_A', 'model_B']);
    expect(extractReferenceModels(domain, 'y'), <String>[]);
  });

  test('sort', () {
    final cases = <List<dynamic>>[
      [[], []],
      [
        ['AND'],
        ['AND']
      ],
      [
        ['OR'],
        ['OR']
      ],
      [
        [
          ['foo', '=', 1]
        ],
        [
          ['foo', '=', 1]
        ]
      ],
      [
        [
          ['foo', '=', 1000],
          ['foo', '=', 0]
        ],
        [
          ['foo', '=', 0],
          ['foo', '=', 1000]
        ]
      ],
      [
        [
          ['foo', '=', 1],
          ['foo', '=', null]
        ],
        [
          ['foo', '=', null],
          ['foo', '=', 1]
        ]
      ],
      [
        [
          ['foo', '=', 1],
          []
        ],
        [
          [],
          ['foo', '=', 1]
        ]
      ],
      [
        [
          [
            [
              [
                ['foo', '=', 1]
              ]
            ]
          ],
          [
            [
              ['foo', '=', 1]
            ]
          ]
        ],
        [
          [
            [
              ['foo', '=', 1]
            ]
          ],
          [
            [
              [
                ['foo', '=', 1]
              ]
            ]
          ]
        ]
      ],
      [
        [
          [
            ['foo', '=', 1],
            ['bar', '=', 2]
          ],
          [
            ['foo', '=', 1],
            ['bar', '=', 2],
            ['baz', '=', 3]
          ]
        ],
        [
          [
            ['bar', '=', 2],
            ['baz', '=', 3],
            ['foo', '=', 1]
          ],
          [
            ['bar', '=', 2],
            ['foo', '=', 1]
          ]
        ]
      ],
      [
        [
          'OR',
          ['foo', '=', 1],
          ['foo', '=', null],
          [
            'AND',
            ['bar', '=', 2],
            ['baz', '=', 3]
          ]
        ],
        [
          'OR',
          ['foo', '=', null],
          ['foo', '=', 1],
          [
            'AND',
            ['bar', '=', 2],
            ['baz', '=', 3]
          ]
        ]
      ],
      [
        [
          ['foo', '=', 'bar'],
          ['foo', '=', null]
        ],
        [
          ['foo', '=', 'bar'],
          ['foo', '=', null]
        ]
      ],
    ];
    for (final [domain, expected] in cases) {
      expect(sortDomain(domain), expected, reason: 'sort($domain)');
    }
  });

  test('canonicalize', () {
    final cases = <List<dynamic>>[
      [[], []],
      [
        ['AND'],
        []
      ],
      [
        ['OR'],
        []
      ],
      [
        [
          ['foo', '=', 1],
          ['bar', '=', 2]
        ],
        [
          ['bar', '=', 2],
          ['foo', '=', 1]
        ]
      ],
      [
        [
          [
            ['foo', '=', 1]
          ]
        ],
        [
          ['foo', '=', 1]
        ]
      ],
      [
        [
          'AND',
          [
            'OR',
            ['bar', '=', 2],
            ['baz', '=', 3]
          ],
          ['foo', '=', 1]
        ],
        [
          ['foo', '=', 1],
          [
            'OR',
            ['bar', '=', 2],
            ['baz', '=', 3]
          ]
        ]
      ],
      [
        [
          'OR',
          [
            'AND',
            ['bar', '=', 2],
            ['baz', '=', 3]
          ],
          ['foo', '=', 1]
        ],
        [
          'OR',
          ['foo', '=', 1],
          [
            ['bar', '=', 2],
            ['baz', '=', 3]
          ]
        ]
      ],
      [
        [
          'AND',
          [
            'AND',
            ['bar', '=', 2],
            ['baz', '=', 3]
          ],
          ['foo', '=', 1]
        ],
        [
          ['bar', '=', 2],
          ['baz', '=', 3],
          ['foo', '=', 1]
        ]
      ],
      [
        [
          'OR',
          [
            'OR',
            ['bar', '=', 2],
            ['baz', '=', 3]
          ],
          ['foo', '=', 1]
        ],
        [
          'OR',
          ['bar', '=', 2],
          ['baz', '=', 3],
          ['foo', '=', 1]
        ]
      ],
    ];
    for (final [domain, expected] in cases) {
      expect(canonicalize(domain), expected, reason: 'canonicalize($domain)');
    }
  });

  // Additional cases (not in sao.js) for the Dart value types.
  test('evaldomain with dates, decimals and child_of', () {
    final d = const TrytonDate(2024, 5, 1);
    expect(
        evalDomain([
          ['x', '>=', const TrytonDate(2024, 1, 1)]
        ], {'x': d}),
        isTrue);
    expect(
        evalDomain([
          ['x', '<', DateTime.utc(2024, 1, 1)]
        ], {'x': DateTime.utc(2023, 12, 31, 23)}),
        isTrue);
    // A date and a datetime are not comparable (Python TypeError → false).
    expect(
        evalDomain([
          ['x', '<', DateTime.utc(2025)]
        ], {'x': d}),
        isFalse);
    // A comparison with an empty value cannot be decided → false.
    expect(
        evalDomain([
          ['x', '<', d]
        ], {'x': null}),
        isFalse);
    expect(
        evalDomain([
          ['x', '>', 1.5]
        ], {'x': const TrytonDecimal('2.25')}),
        isTrue);
    expect(
        evalDomain([
          ['x', 'child_of', [1], 'parent']
        ], {'x': 7}),
        isTrue);
    // like with a regex special character matches literally (Python
    // re.escape; SAO would treat '.' as any character).
    expect(
        evalDomain([
          ['x', 'like', 'a.c']
        ], {'x': 'abc'}),
        isFalse);
    expect(
        evalDomain([
          ['x', 'ilike', '%ü%']
        ], {'x': 'MÜLLER'}),
        isTrue);
  });

  test('filterLeaf, inverseLeaf, cleanForInversion', () {
    expect(
        filterLeaf([
          ['ref', '=', 1, 'party.party'],
          ['ref.name', 'ilike', 'x', 'sale.sale']
        ], 'ref', 'party.party'),
        [
          ['ref', '=', 1, 'party.party'],
          ['id', '=', null]
        ]);
    expect(
        inverseLeaf([
          ['x', 'child_of', [1], 'parent'],
          ['y', '=', 1]
        ]),
        [
          ['parent', 'child_of', [1], 'parent'],
          ['y', '=', 1]
        ]);
    expect(
        cleanForInversion([
          ['company', '=', 1],
          [
            'OR',
            ['state', '=', 'draft'],
            ['party', '=', 2]
          ]
        ], (f) => f == 'state'),
        [
          ['company', '=', 1],
          [
            'OR',
            [],
            ['party', '=', 2]
          ]
        ]);
  });
}

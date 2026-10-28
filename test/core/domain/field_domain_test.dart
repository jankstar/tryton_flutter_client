import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/domain/field_domain.dart';

import '../pyson/pyson_test_helpers.dart';

/// `evalFieldDomain`: the field `domain` (PYSON string or list) evaluated
/// with record values (used by the many2one search outside the data layer).
/// domain_readonly itself is tested with the data layer (Field.validate).
void main() {
  test('PYSON string and list are evaluated', () {
    final env = {'company': 3};
    expect(
        evalFieldDomain(
            jsonEncode([
              ['company', '=', eval_('company', -1)]
            ]),
            env),
        [
          ['company', '=', 3]
        ]);
    expect(
        evalFieldDomain([
          ['company', '=', eval_('company', -1)]
        ], env),
        [
          ['company', '=', 3]
        ]);
  });

  test('empty, invalid and non-list input → []', () {
    expect(evalFieldDomain(null, const {}), isEmpty);
    expect(evalFieldDomain('', const {}), isEmpty);
    expect(evalFieldDomain('[broken', const {}), isEmpty);
    expect(evalFieldDomain('{}', const {}), isEmpty);
  });
}

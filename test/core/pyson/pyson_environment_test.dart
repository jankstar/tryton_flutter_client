import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/pyson/pyson_environment.dart';
import 'package:tryton_flutter_client/core/pyson/pyson_evaluator.dart';

import 'pyson_test_helpers.dart';

void main() {
  group('formEvalValues (get_eval format)', () {
    test('Many2One [id, rec_name] → id, other values unchanged', () {
      expect(
          formEvalValues({
            'party': [5, 'Jan'],
            'empty': [7, null],
            'lines': [1, 2, 3],
            'pair': [1, 2],
            'state': 'draft',
            'none': null,
          }),
          {
            'party': 5,
            'empty': 7,
            'lines': [1, 2, 3],
            'pair': [1, 2],
            'state': 'draft',
            'none': null,
          });
    });

    test('with field types only many2one is converted', () {
      expect(
          formEvalValues({
            'party': [5, 'Jan'],
            'tags': [3, 'x'],
            'owner': [],
          }, fieldTypes: {
            'party': 'many2one',
            'tags': 'many2many',
            'owner': 'many2one',
          }),
          {
            'party': 5,
            'tags': [3, 'x'],
            'owner': null,
          });
    });
  });

  group('recordEnvironment', () {
    test('values, id, context, active_model, active_id', () {
      final env = recordEnvironment(
        values: {'state': 'draft'},
        context: {'company': 1},
        activeModel: 'sale.sale',
        activeId: 42,
      );
      final ev = PYSONEvaluator(env);
      expect(ev.eval(eval_('state')), 'draft');
      expect(ev.eval(eval_('id')), 42);
      expect(ev.eval(eval_('active_model')), 'sale.sale');
      expect(ev.eval(eval_('active_id')), 42);
      expect(ev.eval(eval_('context.company', -1)), 1);
      expect(ev.eval(get(eval_('context', {}), 'company', -1)), 1);
    });

    test('_parent_<field> nested over two levels', () {
      final grandParent =
          parentEnvironment(values: {'currency': 3}, id: 1);
      final parent = parentEnvironment(
        values: {'state': 'draft', 'party': 9},
        id: 10,
        parentName: 'sale',
        parent: grandParent,
      );
      final env = recordEnvironment(
        values: {'product': 4},
        activeModel: 'sale.line.detail',
        activeId: 100,
        parentName: 'line',
        parent: parent,
      );
      final ev = PYSONEvaluator(env);
      expect(ev.eval(eval_('_parent_line.state')), 'draft');
      expect(ev.eval(eval_('_parent_line.id')), 10);
      expect(ev.eval(eval_('_parent_line._parent_sale.currency')), 3);
      expect(ev.eval(eval_('_parent_line._parent_sale.missing', 'x')), 'x');
      expect(ev.eval(eval_('_parent_other.state', 'none')), 'none');
    });
  });

  group('actionEnvironment', () {
    test('active_*, session context, _user and context', () {
      final env = actionEnvironment(
        sessionContext: {'language': 'de', 'company': 1},
        userId: 7,
        activeModel: 'party.party',
        activeId: 3,
        activeIds: [3, 4],
      );
      final ev = PYSONEvaluator(env);
      expect(ev.eval(eval_('_user')), 7);
      expect(ev.eval(eval_('active_model')), 'party.party');
      expect(ev.eval(eval_('active_id')), 3);
      expect(ev.eval(eval_('active_ids')), [3, 4]);
      expect(ev.eval(eval_('language')), 'de');
      expect(ev.eval(eval_('context.company')), 1);
      expect(ev.eval(get(eval_('context', {}), 'language')), 'de');
    });

    test('pyson_context is evaluated and merged', () {
      final env = actionEnvironment(
        sessionContext: {'company': 1},
        userId: 7,
        pysonContext: jsonEncode({
          'owner': eval_('_user'),
          'company_id': eval_('company', -1),
        }),
      );
      expect(env['owner'], 7);
      expect(env['company_id'], 1);
      expect((env['context'] as Map)['owner'], 7);
    });

    test('invalid or empty pyson_context is ignored', () {
      expect(actionEnvironment(pysonContext: '{broken')['_user'], isNull);
      expect(actionEnvironment(pysonContext: '').containsKey('context'),
          isTrue);
    });
  });

  // ── Existing callers must behave as before (Many2One [id, name]) ───────
  group('callers', () {
    Map<String, dynamic> formEnv(Map<String, dynamic> values) =>
        recordEnvironment(
            values: formEvalValues(values), activeModel: 'x', activeId: 1);

    test('field states compare a Many2One with its id', () {
      final states = {
        'invisible': equal(eval_('party', null), 5),
        'readonly': not(bool_(eval_('lines', []))),
        'required': in_(eval_('state', ''), ['draft', 'quotation']),
      };
      final r = evaluateFieldStates(
        statesRaw: states,
        staticInvisible: false,
        staticReadonly: false,
        staticRequired: false,
        environment: formEnv({
          'party': [5, 'Jan'],
          'lines': [11, 12],
          'state': 'draft',
        }),
      );
      expect(r.invisible, isTrue);
      expect(r.readonly, isFalse);
      expect(r.required, isTrue);

      final empty = evaluateFieldStates(
        statesRaw: states,
        staticInvisible: false,
        staticReadonly: false,
        staticRequired: false,
        environment: formEnv({'party': null, 'lines': [], 'state': 'done'}),
      );
      expect(empty.invisible, isFalse);
      expect(empty.readonly, isTrue);
      expect(empty.required, isFalse);
    });

    test('page/button states: static invisible wins, missing states keep '
        'static values', () {
      expect(
          evaluateFieldStates(
            statesRaw: {'invisible': false},
            staticInvisible: true,
            staticReadonly: false,
            staticRequired: false,
            environment: const {},
          ).invisible,
          isTrue);
      final r = evaluateFieldStates(
        statesRaw: null,
        staticInvisible: false,
        staticReadonly: true,
        staticRequired: true,
        environment: const {},
      );
      expect(r.readonly, isTrue);
      expect(r.required, isTrue);
    });

    test('domain_readonly with a Many2One from the form', () {
      final r = evaluateDomainReadonly(
        fieldName: 'company',
        fieldDomainRaw: jsonEncode([
          ['company', '=', eval_('party_company', -1)]
        ]),
        screenDomain: const [],
        environment: formEnv({
          'party_company': [2, 'ACME'],
        }),
      );
      expect(r.readonly, isTrue);
      expect(r.forcedValue, 2);
    });

    test('action domain with session context and _user', () {
      final env = actionEnvironment(
        sessionContext: {'company': 1},
        userId: 7,
        activeModel: 'sale.sale',
      );
      final domain = evaluateActionDomain(
        jsonEncode([
          ['company', '=', eval_('company', -1)],
          ['create_uid', '=', eval_('_user')],
          [
            'OR',
            ['model', '=', eval_('active_model')],
            ['date', '>=', date(y: 2024, M: 1, d: 1)],
          ],
        ]),
        env,
      );
      expect(domain[0], ['company', '=', 1]);
      expect(domain[1], ['create_uid', '=', 7]);
      expect(domain[2][1], ['model', '=', 'sale.sale']);
      expect((domain[2][2] as List)[2].toString(), '2024-01-01');
    });

    test('action domain: empty, invalid and non-list input → []', () {
      expect(evaluateActionDomain(null, const {}), isEmpty);
      expect(evaluateActionDomain('', const {}), isEmpty);
      expect(evaluateActionDomain('[broken', const {}), isEmpty);
      expect(evaluateActionDomain('{}', const {}), isEmpty);
    });
  });
}

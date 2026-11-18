import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/model/model.dart';
import 'package:tryton_flutter_client/core/wizard/wizard.dart';

import '../model/fake_rpc.dart';

/// `TrytonWizard` (spec 13, SAO `Sao.Wizard`) with a fake RPC.
void main() {
  /// Recorded wizard calls (`method`, params, context).
  late List<(String, List<dynamic>, Map<String, dynamic>)> calls;

  Map<String, dynamic> view(String state,
          {Map<String, dynamic> fields = const {
            'name': {'type': 'char', 'string': 'Name'}
          },
          Map<String, dynamic> defaults = const {},
          Map<String, dynamic> values = const {},
          List<Map<String, dynamic>> buttons = const []}) =>
      {
        'view': {
          'fields_view': {
            'model': 'test.wizard.$state',
            'type': 'form',
            'view_id': null,
            'arch': '<form>${[
              for (final f in fields.keys) '<label name="$f"/><field name="$f"/>'
            ].join()}</form>',
            'fields': fields,
          },
          'buttons': buttons,
          'defaults': defaults,
          'values': values,
          'state': state,
        }
      };

  const cancel = {'state': 'end', 'string': 'Cancel', 'icon': 'tryton-cancel'};

  /// A wizard whose `execute` answers with [execute] per state.
  TrytonWizard wizard(Map<String, Object? Function(List<dynamic> params)> execute,
      {Object? Function()? delete, FakeRpc? models}) {
    calls = [];
    return TrytonWizard(
      action: 'test.wiz',
      name: 'Test',
      session: fakeSession(models ?? FakeRpc()),
      data: const {
        'model': 'party.party',
        'id': 3,
        'ids': [3],
        'action_id': 77
      },
      context: const {'company': 1},
      rpc: (method, params, {context}) async {
        calls.add((method, params, {...?context}));
        switch (method.split('.').last) {
          case 'create':
            return [12, 'start', 'end'];
          case 'execute':
            final handler = execute[params[2]];
            if (handler == null) throw StateError('no state ${params[2]}');
            return handler(params);
          case 'delete':
            return delete?.call();
        }
        return null;
      },
    );
  }

  List<String> methods() => [for (final c in calls) c.$1];

  test('two views: defaults/values, button data, end deletes the session',
      () async {
    final w = wizard({
      'start': (_) => view('start',
          defaults: {'name': 'Default'},
          buttons: [
            cancel,
            {'state': 'next', 'string': 'Next', 'default': true},
          ]),
      'next': (p) => view('ask',
          fields: {
            'note': {'type': 'char', 'string': 'Note'}
          },
          values: {'note': 'from server'},
          buttons: [cancel]),
    });
    await w.run();
    expect(methods(), ['wizard.test.wiz.create', 'wizard.test.wiz.execute']);
    final start = calls[1];
    expect(start.$2.sublist(0, 3), [12, <String, dynamic>{}, 'start']);
    expect(start.$3, {
      'company': 1,
      'active_id': 3,
      'active_ids': [3],
      'active_model': 'party.party',
      'action_id': 77,
    });
    expect(w.screen!.model.name, 'test.wizard.start');
    expect(w.screen!.currentRecord!.fieldGet('name'), 'Default');
    expect(w.buttons.map((b) => b.state), ['end', 'next']);
    expect(w.buttons.last.isDefault, isTrue);
    expect(w.endButton!.string, 'Cancel');

    await w.response(w.buttons.last);
    final next = calls.last;
    expect(next.$2[2], 'next');
    expect((next.$2[1] as Map)['start'], containsPair('name', 'Default'));
    expect(w.screen!.model.name, 'test.wizard.ask');
    expect(w.screen!.currentRecord!.fieldGet('note'), 'from server');
    expect(w.done, isFalse);

    await w.cancel();
    expect(methods().last, 'wizard.test.wiz.delete');
    expect(w.done, isTrue);
    expect(await w.finished, isNull);
  });

  test('x2many default [{}] in a wizard: a new child with its view '
      'defaults in the data of the button (issue #6)', () async {
    final models = FakeRpc({
      'test.wiz.line.default_get': (c) => {
            for (final n in c.params[0] as List)
              if (n == 'active') n: true
          },
    });
    final w = wizard({
      'start': (_) => view('start',
          fields: {
            'lines': {
              'type': 'one2many',
              'string': 'Lines',
              'relation': 'test.wiz.line',
              'views': {
                'form': {
                  'fields': {
                    'name': {'type': 'char', 'string': 'Name'},
                    'active': {'type': 'boolean', 'string': 'Active'},
                  }
                }
              },
            }
          },
          defaults: {
            'lines': [<String, dynamic>{}]
          },
          buttons: [
            cancel,
            {'state': 'go', 'string': 'Go', 'default': true},
          ]),
      'go': (_) => <String, dynamic>{},
    }, models: models);
    await w.run();
    final lines =
        w.screen!.currentRecord!.fieldGetClient('lines') as RecordGroup;
    expect(lines, hasLength(1));
    expect(lines.single.id, isNegative);
    expect(models.named('test.wiz.line.default_get').single.params[0],
        unorderedEquals(['name', 'active']));
    expect(lines.single.fieldGet('active'), isTrue);

    await w.response(w.buttons.last);
    final go = calls.lastWhere((c) =>
        c.$1.endsWith('.execute') && c.$2.length > 2 && c.$2[2] == 'go');
    // (wizard data = Python `get_on_change_value`: the values with id)
    expect((go.$2[1] as Map)['start']['lines'], [
      {'name': '', 'active': true, 'id': lines.single.id}
    ]);
  });

  test('a validate button with an invalid record shows the message',
      () async {
    final w = wizard({
      'start': (_) => view('start',
          fields: {
            'name': {'type': 'char', 'string': 'Name', 'required': true}
          },
          buttons: [
            cancel,
            {'state': 'go', 'string': 'Go', 'default': true, 'validate': true},
          ]),
      'go': (_) => <String, dynamic>{},
    });
    await w.run();
    await w.response(w.buttons.last);
    expect(w.invalidMessage, contains('Name'));
    expect(methods().where((m) => m.endsWith('execute')), hasLength(1));

    await w.screen!.model.fields['name']!
        .setClient(w.screen!.currentRecord!, 'X');
    await w.response(w.buttons.last);
    expect(w.invalidMessage, isNull);
    expect(w.done, isTrue, reason: 'no view → end state');
  });

  test('actions run after the end with the context without wizard keys',
      () async {
    final events = <String>[];
    final w = wizard({
      'start': (_) => {
            'actions': [
              [
                {'type': 'ir.action.act_window', 'name': 'A'},
                {'model': 'party.party', 'ids': [3]}
              ]
            ]
          },
    }, delete: () {
      events.add('delete');
      return null;
    });
    w.onAction = (action, data, context) async {
      events.add('action ${(action as Map)['name']}');
      expect(data, {
        'model': 'party.party',
        'ids': [3]
      });
      expect(context, {'company': 1});
    };
    await w.run();
    expect(events, ['delete', 'action A']);
    expect(w.done, isTrue);
  });

  test('actions of a state with view run at once, the wizard stays open',
      () async {
    // module configuration: `action` answers with the view `other` and
    // the action of the next config item (e.g. „Configure Company“)
    final events = <String>[];
    late TrytonWizard w;
    w = wizard({
      'start': (_) => view('first', buttons: [
            cancel,
            {'state': 'action', 'string': 'OK', 'default': true},
          ]),
      'action': (_) => {
            ...view('other', buttons: [
              cancel,
              {'state': 'action', 'string': 'Next', 'default': true},
            ]),
            'actions': [
              [
                {'type': 'ir.action.wizard', 'name': 'Configure Company'},
                <String, dynamic>{}
              ]
            ],
          },
    }, delete: () {
      events.add('delete');
      return 'reload menu';
    });
    w.onAction = (action, data, context) async {
      events.add('action ${(action as Map)['name']}');
      expect(context, {'company': 1}, reason: 'without active_* and action_id');
      expect(w.processing, isFalse, reason: 'the view stays usable');
      expect(w.screenState, 'other');
      expect(w.done, isFalse);
    };
    await w.run();
    await w.response(w.buttons.last);
    expect(events, ['action Configure Company']);
    expect(w.done, isFalse);
    expect(w.buttons.last.string, 'Next');

    await w.cancel();
    expect(events.last, 'delete');
    expect(await w.finished, 'reload menu');
  });

  test('at the end: finished before the actions; a failing action does not '
      'stop the next', () async {
    final events = <String>[];
    final w = wizard({
      'start': (_) => {
            'actions': [
              [{'type': 'ir.action.wizard', 'name': 'A'}, <String, dynamic>{}],
              [{'type': 'ir.action.wizard', 'name': 'B'}, <String, dynamic>{}],
            ]
          },
    }, delete: () {
      events.add('delete');
      return null;
    });
    w.onAction = (action, data, context) async {
      final name = (action as Map)['name'];
      events.add('action $name (done: ${w.done})');
      if (name == 'A') throw StateError('A failed');
    };
    await expectLater(w.run(), throwsStateError);
    expect(events, ['delete', 'action A (done: true)', 'action B (done: true)']);
  });

  test('the result of delete is returned (client action)', () async {
    final w = wizard({'start': (_) => <String, dynamic>{}},
        delete: () => 'reload context');
    await w.run();
    expect(await w.finished, 'reload context');
  });

  test('error in execute: without screen end, with screen stay', () async {
    final failing = wizard({});
    await expectLater(failing.run(), throwsStateError);
    expect(methods().last, 'wizard.test.wiz.delete');
    expect(failing.done, isTrue);

    var fail = true;
    final w = wizard({
      'start': (_) => view('start', buttons: [
            cancel,
            {'state': 'next', 'string': 'Next', 'default': true},
          ]),
      'next': (_) {
        if (fail) throw StateError('server');
        return <String, dynamic>{};
      },
    });
    await w.run();
    await expectLater(w.response(w.buttons.last), throwsStateError);
    expect(w.done, isFalse);
    expect(w.state, 'start');
    expect(w.screen, isNotNull);
    expect(w.processing, isFalse);

    fail = false;
    await w.response(w.buttons.last);
    expect(w.done, isTrue);
  });
}

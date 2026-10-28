import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/core/xml/form_xml_parser.dart';
import 'package:tryton_flutter_client/core/xml/view_definition.dart';

import '../model/fake_rpc.dart';

/// `screen.button` (spec 8.6, SAO `Sao.Screen.button`) with a fake RPC.
void main() {
  const arch = '<form>'
      '<field name="name"/><field name="state"/>'
      '<button name="confirm" string="Confirm"'
      ' states="{&quot;invisible&quot;: {&quot;__class__&quot;: &quot;Equal&quot;,'
      ' &quot;s1&quot;: {&quot;__class__&quot;: &quot;Eval&quot;, &quot;v&quot;: &quot;state&quot;},'
      ' &quot;s2&quot;: &quot;done&quot;}}"/>'
      '<button name="compute" string="Compute" type="instance"'
      ' change="[&quot;name&quot;, &quot;id&quot;]"/>'
      '<button name="print_it" string="Print" keyword="print"/>'
      '</form>';
  const fields = {
    'name': {'type': 'char', 'string': 'Name'},
    'state': {'type': 'char', 'string': 'State'},
  };

  FakeRpc server() => FakeRpc({
        'read': (c) => [
              for (final id in c.params[0] as List)
                {
                  'id': id,
                  'name': 'N$id',
                  'state': 'draft',
                  'rec_name': 'N$id',
                  '_timestamp': 'ts$id',
                  '_write': true,
                  '_delete': true,
                }
            ],
        'write': (c) => null,
      });

  /// A form screen showing record 1 of [rpc].
  Future<TrytonScreen> formScreen(FakeRpc rpc) async {
    final screen = TrytonScreen(
        const ScreenAttributes('test.order', mode: ['form'], viewsPreload: {
          'form': {
            'type': 'form',
            'view_id': 1,
            'arch': arch,
            'fields': fields,
          }
        }),
        session: fakeSession(rpc));
    screen.load([1]);
    screen.currentRecord = screen.group.first;
    await screen.switchView();
    return screen;
  }

  ButtonNode buttonOf(TrytonScreen screen, String name) =>
      screen.currentView!.buttons.firstWhere((b) => b.name == name);

  test('parser: keyword, type, change and rule of buttons', () {
    final root = FormXmlParser().parse(
        '<form><button name="a" keyword="relate" type="class" rule="1"'
        ' change="[&quot;x&quot;]"/></form>');
    final button = root.children.single as ButtonNode;
    expect(button.keyword, 'relate');
    expect(button.type, 'class');
    expect(button.isInstance, isFalse);
    expect(button.rule, isTrue);
    expect(button.change, ['x']);
  });

  test('class button: save, call with ids and _timestamp, reload',
      () async {
    final rpc = server()..handlers['confirm'] = (c) => null;
    final screen = await formScreen(rpc);
    final record = screen.currentRecord!;
    await screen.model.fields['name']!.setClient(record, 'Changed');
    final readsBefore = rpc.named('test.order.read').length;

    await screen.button(buttonOf(screen, 'confirm'));
    expect(rpc.names.where((n) => n == 'test.order.write' || n == 'test.order.confirm'),
        ['test.order.write', 'test.order.confirm'],
        reason: 'saved first');
    final call = rpc.named('test.order.confirm').single;
    expect(call.params, [
      [1]
    ]);
    expect(call.context['_timestamp'], containsPair('test.order,1', isNull),
        reason: 'like SAO: timestamp after the save (record cancelled)');
    expect(rpc.named('test.order.read').length, greaterThan(readsBefore),
        reason: 'reloaded');
    expect(record.modified, isFalse);
  });

  test('class button: string result is a client action after reload',
      () async {
    final rpc = server()..handlers['confirm'] = (c) => 'switch tree';
    final screen = TrytonScreen(
        const ScreenAttributes('test.order', mode: ['form', 'tree'],
            viewsPreload: {
              'form': {
                'type': 'form',
                'view_id': 1,
                'arch': arch,
                'fields': fields,
              },
              'tree': {
                'type': 'tree',
                'view_id': 2,
                'arch': '<tree><field name="name"/></tree>',
                'fields': {
                  'name': {'type': 'char', 'string': 'Name'}
                },
              },
            }),
        session: fakeSession(rpc));
    screen.load([1]);
    screen.currentRecord = screen.group.first;
    await screen.switchView();
    await screen.button(buttonOf(screen, 'confirm'));
    expect(screen.currentView!.viewType, 'tree');
  });

  test('class button: an action result runs (with data), then reload',
      () async {
    final action = {'type': 'ir.action.act_window', 'res_model': 'x'};
    final rpc = server()..handlers['confirm'] = (c) => action;
    final screen = await formScreen(rpc);
    final calls = <(dynamic, Map<String, dynamic>)>[];
    screen.onAction = (a, data, context) async => calls.add((a, data));
    final reads = rpc.named('test.order.read').length;
    await screen.button(buttonOf(screen, 'confirm'));
    expect(calls.single.$1, action);
    expect(calls.single.$2, {
      'model': 'test.order',
      'id': 1,
      'ids': [1]
    });
    expect(rpc.named('test.order.read').length, greaterThan(reads));
  });

  test('class button: on error the records are reloaded too', () async {
    final rpc = server()..handlers['confirm'] = (c) => throw StateError('x');
    final screen = await formScreen(rpc);
    final reads = rpc.named('test.order.read').length;
    await expectLater(
        screen.button(buttonOf(screen, 'confirm')), throwsStateError);
    expect(rpc.named('test.order.read').length, greaterThan(reads));
  });

  test('instance button: values of change + id, changes applied, no save',
      () async {
    final rpc = server()
      ..handlers['compute'] = (c) => {'name': 'Computed'};
    final screen = await formScreen(rpc);
    await screen.button(buttonOf(screen, 'compute'));
    final call = rpc.named('test.order.compute').single;
    expect(call.params, [
      {'name': 'N1', 'id': 1}
    ]);
    final record = screen.currentRecord!;
    expect(record.fieldGet('name'), 'Computed');
    expect(record.modified, isTrue);
    expect(rpc.named('test.order.write'), isEmpty);
  });

  test('confirm "Cancel" and failed pre_validate stop the button', () async {
    final rpc = server()..handlers['confirm'] = (c) => null;
    final screen = await formScreen(rpc);
    screen.onConfirm = (_) async => false;
    final confirm = buttonOf(screen, 'confirm');
    await screen.button(ButtonNode(
        name: confirm.name, statesRaw: confirm.statesRaw, confirm: 'Sure?'));
    expect(rpc.named('test.order.confirm'), isEmpty);

    // pre_validate: name must be "X"
    final messages = <String>[];
    screen.onPreValidationFailed = (m) async => messages.add(m);
    await screen.button(const ButtonNode(name: 'confirm', statesRaw: {
      'pre_validate': [
        ['name', '=', 'X']
      ]
    }));
    expect(rpc.named('test.order.confirm'), isEmpty);
    expect(messages.single, contains('Name'));
  });

  test('getButtons: class buttons that are not invisible/readonly',
      () async {
    final rpc = server();
    final screen = await formScreen(rpc);
    expect([for (final b in screen.getButtons()) b.name],
        ['confirm', 'print_it'],
        reason: 'instance buttons are not offered');
    await screen.model.fields['state']!.setClient(screen.currentRecord!, 'done');
    expect([for (final b in screen.getButtons()) b.name], ['print_it']);
  });
}

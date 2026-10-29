import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/error_processing.dart';
import 'package:tryton_flutter_client/core/wizard/wizard.dart';
import 'package:tryton_flutter_client/features/actions/action_service.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';

import '../views/form_harness.dart';

/// UI fake: records messages and URLs, chooses [choice] of several.
class _FakeUi implements ActionUi {
  final messages = <String>[];
  final urls = <String>[];
  List<Map<String, dynamic>>? offered;
  int? choice;

  @override
  Future<void> message(String text) async => messages.add(text);

  @override
  Future<Map<String, dynamic>?> choose(
      List<Map<String, dynamic>> actions) async {
    offered = actions;
    return choice == null ? null : actions[choice!];
  }

  @override
  Future<void> openUrl(String url) async => urls.add(url);

  @override
  Future<void> runWizard(TrytonWizard wizard,
      {required bool window, required String title}) async {
    await wizard.run();
    if (!wizard.done) await wizard.cancel();
  }

  @override
  RpcErrorProcessor? get errorProcessor => null;

  @override
  String get noActionDefined => 'No action defined.';
  @override
  String get nameSeparator => ', ';
  @override
  String generatingReport() => 'generating';
  @override
  String reportGenerated(String name, String format) => '$name.$format';
  @override
  String notSupported(String name, String type) => '$name: $type';
}

/// `ActionService` (spec 12.1–12.6) with a fake RPC.
void main() {
  late FakeFormRpc rpc;
  late TabsNotifier tabs;
  late ActionService service;

  setUp(() {
    rpc = FakeFormRpc({
      'model.party.party.read': (p) => [
            for (final id in p[0] as List) {'id': id, 'rec_name': 'P$id'}
          ],
    });
    tabs = TabsNotifier();
    service = ActionService(
      ModelService(
          rpc: rpc,
          getContext: () => {'language': 'de', 'company': 7},
          getDatabase: () => 'test'),
      tabs,
      sessionContext: () => {'language': 'de', 'company': 7},
      userId: () => 42,
    );
  });

  test('act_window: PYSON environment, domains, views and tab', () async {
    await service.execute({
      'type': 'ir.action.act_window',
      'name': 'Invoices',
      'res_model': 'account.invoice',
      'views': [
        [11, 'tree'],
        [12, 'form']
      ],
      'pyson_context':
          '{"party": {"__class__": "Eval", "v": "active_id"}, "u": {"__class__": "Eval", "v": "_user"}}',
      'pyson_domain':
          '[["party", "in", {"__class__": "Eval", "v": "active_ids"}], ["company", "=", {"__class__": "Eval", "v": "company"}], ["x", "=", {"__class__": "Eval", "v": "context"}]]',
      'pyson_order': '[["date", "DESC"]]',
      'pyson_search_value':
          '[["model", "=", {"__class__": "Eval", "v": "active_model"}]]',
      'domains': [
        ['Mine', '[["user", "=", {"__class__": "Eval", "v": "_user"}]]', true],
        ['All', '[]', false],
      ],
      'context_model': 'account.invoice.context',
      'context_domain': '[]',
      'limit': 50,
      'res_id': 5,
    }, data: {
      'model': 'party.party',
      'id': 3,
      'ids': [3, 4]
    }, context: {
      'active_id': 99,
      'active_ids': [99],
      'active_model': 'other',
      'extra': true,
    });

    final tab = tabs.state.tabs.single;
    expect(tab.title, 'Invoices', reason: 'no keyword → no suffix');
    final a = tab.attributes;
    expect(a.model, 'account.invoice');
    expect(a.viewIds, [11, 12]);
    expect(a.mode, ['tree', 'form']);
    expect(a.context, {'extra': true, 'party': 3, 'u': 42},
        reason: 'active_* of the passed context are removed');
    expect(a.domain[0], [
      'party',
      'in',
      [3, 4]
    ]);
    expect(a.domain[1], ['company', '=', 7]);
    expect((a.domain[2] as List)[2], containsPair('party', 3),
        reason: 'context = the environment incl. the action context');
    expect(a.order, [
      ['date', 'DESC']
    ]);
    expect(a.searchValue, [
      ['model', '=', 'party.party']
    ]);
    expect(a.tabDomain.map((t) => t.domain).first, [
      ['user', '=', 42]
    ]);
    expect(a.tabDomain.map((t) => t.count), [true, false]);
    expect(a.contextModel, 'account.invoice.context');
    expect(a.limit, 50);
    expect(a.resId, 5);
  });

  test('keyword: name suffix with the rec_names of the first 5 ids',
      () async {
    final action = {
      'type': 'ir.action.act_window',
      'name': 'Invoices',
      'res_model': 'account.invoice',
      'domains': const [],
    };
    await service.execute(action,
        data: {
          'model': 'party.party',
          'id': 1,
          'ids': [1, 2, 3, 4, 5, 6, -1]
        },
        keyword: true);
    expect(tabs.state.tabs.single.title, 'Invoices (P1, P2, P3, P4, P5,...)');
    expect(rpc.named('model.party.party.read').single.params, [
      [1, 2, 3, 4, 5],
      ['rec_name']
    ]);

    await service.execute(action,
        data: {
          'model': 'party.party',
          'id': 1,
          'ids': [1]
        },
        keyword: true);
    expect(tabs.state.tabs.last.title, 'Invoices (P1)');
  });

  test('action as id → ir.action.get_action_value', () async {
    rpc.handlers['model.ir.action.get_action_value'] = (p) => {
          'type': 'ir.action.act_window',
          'name': 'Parties',
          'res_model': 'party.party',
          'domains': const [],
        };
    await service.execute(17);
    expect(rpc.named('model.ir.action.get_action_value').single.params, [17]);
    expect(tabs.state.tabs.single.model, 'party.party');
  });

  test('url opens externally, wizard runs create → execute → delete', () async {
    rpc.handlers['wizard.w.create'] = (_) => [1, 'start', 'end'];
    rpc.handlers['wizard.w.execute'] = (_) => <String, dynamic>{};
    rpc.handlers['wizard.w.delete'] = (_) => null;
    final ui = _FakeUi();
    await service.execute(
        {'type': 'ir.action.url', 'name': 'Web', 'url': 'https://x.org'},
        ui: ui);
    expect(ui.urls, ['https://x.org']);
    await service.execute(
        {'type': 'ir.action.wizard', 'name': 'Wiz', 'wiz_name': 'w'},
        ui: ui);
    expect(rpc.calls.map((c) => c.method),
        containsAllInOrder(['wizard.w.create', 'wizard.w.execute', 'wizard.w.delete']));
    expect(tabs.state.tabs, isEmpty);
  });

  group('keywords (12.6)', () {
    Map<String, dynamic> window(String name) => {
          'type': 'ir.action.act_window',
          'name': name,
          'res_model': 'party.party',
          'domains': const [],
          'keyword': 'tree_open',
        };

    test('one action runs directly', () async {
      rpc.handlers['model.ir.action.keyword.get_keyword'] =
          (p) => [window('Parties')];
      await service.execKeyword('tree_open', {'model': 'ir.ui.menu', 'id': 8});
      expect(rpc.named('model.ir.action.keyword.get_keyword').single.params, [
        'tree_open',
        ['ir.ui.menu', 8]
      ]);
      expect(tabs.state.tabs.single.title, 'Parties',
          reason: 'menu: no ids → no suffix');
    });

    test('several: selection dialog; none: message (with warning)',
        () async {
      final ui = _FakeUi()..choice = 1;
      rpc.handlers['model.ir.action.keyword.get_keyword'] =
          (p) => [window('Menu / A'), window('Menu / B')];
      await service.execKeyword('tree_open', {'model': 'x', 'id': 1}, ui: ui);
      expect(ui.offered, hasLength(2));
      expect(tabs.state.tabs.single.title, 'Menu / B');

      rpc.handlers['model.ir.action.keyword.get_keyword'] = (p) => [];
      await service.execKeyword('tree_open', {'model': 'x', 'id': 1}, ui: ui);
      expect(ui.messages, ['No action defined.']);
      await service.execKeyword('tree_open', {'model': 'x', 'id': 1},
          ui: ui, warning: false);
      expect(ui.messages, hasLength(1));
    });
  });
}

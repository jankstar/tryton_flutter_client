import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/model/model.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';

import '../model/fake_rpc.dart';

const _fields = {
  'name': {'type': 'char', 'string': 'Name'},
  'code': {'type': 'char', 'string': 'Code'},
};

const _views = {
  'tree': {
    'type': 'tree',
    'view_id': 1,
    'arch': '<tree><field name="name"/></tree>',
    'fields': {
      'name': {'type': 'char', 'string': 'Name'},
    },
  },
  'form': {
    'type': 'form',
    'view_id': 2,
    'arch': '<form><field name="name"/><field name="code"/></form>',
    'fields': _fields,
  },
};

/// Server with [count] records (ids 1…count); `search` answers the slice
/// of offset/limit, `search_count` the number (capped).
FakeRpc _server({int count = 25}) {
  final ids = [for (var i = 1; i <= count; i++) i];
  return FakeRpc({
    'search': (c) {
      final offset = c.params[1] as int;
      final limit = c.params[2] as int?;
      return ids
          .skip(offset)
          .take(limit ?? ids.length)
          .toList();
    },
    'search_count': (c) => ids.length,
    'read': (c) => [
          for (final id in c.params[0] as List)
            {
              'id': id,
              'name': 'N$id',
              'code': 'C$id',
              'rec_name': 'N$id',
              '_timestamp': 't',
              '_write': true,
              '_delete': true,
            }
        ],
    'default_get': (c) => {'name': 'New'},
    'copy': (c) => [100],
  });
}

TrytonScreen _screen(FakeRpc rpc,
        {int? limit = 10,
        List<dynamic> domain = const [],
        List<TabDomain> tabs = const [],
        dynamic contextDomain,
        List<dynamic>? order,
        List<String> mode = const ['tree', 'form']}) =>
    TrytonScreen(
      ScreenAttributes('party.party',
          mode: mode,
          viewsPreload: _views,
          limit: limit,
          domain: domain,
          tabDomain: tabs,
          contextDomain: contextDomain,
          order: order),
      session: fakeSession(rpc),
    );

void main() {
  group('search (8.3)', () {
    test('domain: search text AND screen domain AND context and tab domain',
        () async {
      final rpc = _server();
      final screen = _screen(rpc,
          domain: [
            ['active', '=', true]
          ],
          contextDomain:
              '[["company", "=", {"__class__": "Eval", "v": "company", "d": -1}]]',
          tabs: const [
            TabDomain('Draft', [
              ['state', '=', 'draft']
            ])
          ]);
      screen.group.context = {'company': 3};
      await screen.switchView();
      await screen.searchFilter('ab');
      final search = rpc.named('party.party.search').single;
      expect(search.params[0], [
        'AND',
        [
          'AND',
          [
            'AND',
            [
              ['rec_name', 'ilike', '%ab%']
            ],
            [
              ['active', '=', true]
            ]
          ],
          [
            ['company', '=', 3]
          ]
        ],
        [
          ['state', '=', 'draft']
        ]
      ]);
      expect(search.params.sublist(1), [0, 10, null]);
    });

    test('search_count only for a full page, without error dialog',
        () async {
      final rpc = _server();
      final screen = _screen(rpc);
      await screen.switchView();
      await screen.searchFilter();
      expect(screen.group.length, 10);
      final count = rpc.named('party.party.search_count').single;
      expect(count.params.sublist(1), [0, 1000], reason: 'limit*100+offset');
      expect(count.processException, isFalse);
      expect(screen.searchCount, 25);
      expect(screen.statusText, '_@10/25');
      screen.currentRecord = screen.group[2];
      expect(screen.statusText, '3@10/25');

      final small = _server(count: 4);
      final screen2 = _screen(small);
      await screen2.switchView();
      await screen2.searchFilter();
      expect(small.named('party.party.search_count'), isEmpty);
      expect(screen2.searchCount, 4);
      expect(screen2.statusText, '_/4');
    });

    test('paging: next/previous, offset reset on new domain', () async {
      final rpc = _server();
      final screen = _screen(rpc);
      await screen.switchView();
      await screen.searchFilter();
      expect(screen.hasPreviousPage, isFalse);
      expect(screen.hasNextPage, isTrue);
      await screen.searchNext();
      expect(screen.offset, 10);
      expect([for (final r in screen.group) r.id].first, 11);
      screen.currentRecord = screen.group.first;
      expect(screen.position, 11);
      await screen.searchNext();
      expect(screen.offset, 20);
      expect(screen.group.length, 5);
      expect(screen.hasNextPage, isFalse);
      await screen.searchPrev();
      expect(screen.offset, 10);

      await screen.searchFilter('x');
      expect(screen.offset, 0, reason: 'domain changed');
    });

    test('empty page with offset > 0 steps back one page', () async {
      var count = 25;
      final rpc = _server();
      rpc.handlers['search'] = (c) {
        final offset = c.params[1] as int;
        return [for (var i = offset + 1; i <= count && i <= offset + 10; i++) i];
      };
      final screen = _screen(rpc);
      await screen.switchView();
      await screen.searchFilter();
      await screen.searchNext();
      await screen.searchNext();
      expect(screen.offset, 20);
      count = 15; // records deleted meanwhile
      await screen.searchFilter();
      expect(screen.offset, 10);
      expect([for (final r in screen.group) r.id], [11, 12, 13, 14, 15]);
    });

    test('searchMore appends the next records (endless scrolling)',
        () async {
      final rpc = _server();
      final screen = _screen(rpc);
      await screen.switchView();
      await screen.searchFilter();
      expect(screen.hasMore, isTrue);
      await screen.searchMore();
      expect(screen.group.length, 20);
      expect(screen.offset, 0);
      expect(rpc.named('party.party.search').last.params[1], 10);
      await screen.searchMore();
      expect(screen.group.length, 25);
      expect(screen.hasMore, isFalse);
      expect(screen.statusText, '_/25');
    });

    test('tab counters: search_count of tab AND screen domain', () async {
      final rpc = _server();
      rpc.handlers['search_count'] = (c) =>
          c.params[2] == 1000 && (c.params[0] as List).first == 'AND' ? 7 : 25;
      final screen = _screen(rpc, tabs: const [
        TabDomain('Draft', [
          ['state', '=', 'draft']
        ], count: true),
        TabDomain('All', []),
      ]);
      await screen.switchView();
      await screen.searchFilter();
      await screen.countTabDomain();
      expect(screen.tabCounters, [7, null]);
      final tabCount = rpc
          .named('party.party.search_count')
          .where((c) => c.params[2] == 1000)
          .last;
      expect(tabCount.params[0], [
        'AND',
        [
          ['state', '=', 'draft']
        ],
        <dynamic>[]
      ]);

      await screen.setTab(1);
      expect(rpc.named('party.party.search').last.params[0], <dynamic>[]);
    });

    test('sort by column: ASC → DESC → default order', () async {
      final rpc = _server();
      final screen = _screen(rpc, order: [
        ['code', 'ASC']
      ]);
      await screen.switchView();
      await screen.searchFilter();
      expect(rpc.named('party.party.search').last.params[3], [
        ['code', 'ASC']
      ]);
      await screen.sortBy('name');
      expect(rpc.named('party.party.search').last.params[3], [
        ['name', 'ASC']
      ]);
      expect(screen.sortDirection('name'), 'ASC');
      await screen.sortBy('name');
      expect(screen.sortDirection('name'), 'DESC');
      await screen.sortBy('name');
      expect(screen.order, [
        ['code', 'ASC']
      ]);
      expect(screen.sortDirection('name'), isNull);
    });
  });

  group('views (8.2)', () {
    test('switching between tree and form shares group and record',
        () async {
      final rpc = _server();
      final screen = _screen(rpc);
      await screen.switchView();
      expect(screen.currentView!.viewType, 'tree');
      expect(screen.nextViewType, 'form');
      expect(screen.numberOfViews, 2);
      await screen.searchFilter();
      final record = screen.group[3];
      screen.currentRecord = record;
      await screen.switchView(viewType: 'form');
      expect(screen.currentView!.viewType, 'form');
      expect(identical(screen.currentRecord, record), isTrue);
      expect(record.isLoaded('code'), isTrue, reason: 'form loads all fields');
      expect(screen.model.fields['code']!.loading, 'lazy');
      expect(screen.model.fields['name']!.loading, 'eager');

      await screen.displayNext();
      expect(screen.currentRecord!.id, 5);
      await screen.displayPrevious();
      await screen.displayPrevious();
      expect(screen.currentRecord!.id, 3);

      await screen.switchView();
      expect(screen.currentView!.viewType, 'tree');
      expect(screen.currentRecord!.id, 3);
      expect(rpc.named('party.party.fields_view_get'), isEmpty,
          reason: 'preloaded views');
    });

    test('fields_view_get with screen_size and view_tree_width', () async {
      final rpc = _server()
        ..handlers['fields_view_get'] =
            (c) => _views[c.params[1] as String];
      final screen = TrytonScreen(
          const ScreenAttributes('party.party',
              mode: ['tree', 'graph', 'form'], viewIds: [7, 8]),
          session: fakeSession(rpc))
        ..screenSize = () => [800, 600];
      await screen.switchView();
      final call = rpc.named('party.party.fields_view_get').single;
      expect(call.params, [7, 'tree']);
      expect(call.context['screen_size'], [800, 600]);
      expect(call.context['view_tree_width'], isTrue);
      await screen.switchView();
      expect(screen.currentView!.viewType, 'form', reason: 'graph skipped');
      expect(rpc.named('party.party.fields_view_get').last.params,
          [null, 'form']);
    });

    test('an invalid record in the form blocks the switch', () async {
      final rpc = _server();
      final screen = _screen(rpc, mode: const ['form', 'tree']);
      await screen.switchView();
      screen.model.fields['code']!.description['required'] = true;
      final record = await screen.newRecord();
      expect(record, isNotNull);
      expect(await screen.switchView(), isFalse);
      expect(screen.currentView!.viewType, 'form');
      await screen.model.fields['code']!.setClient(record!, 'X');
      expect(await screen.switchView(), isTrue);
      expect(screen.currentView!.viewType, 'tree');
    });
  });

  group('record operations (8.5)', () {
    test('new_position: id DESC top, id ASC bottom, root top', () {
      final rpc = _server();
      expect(_screen(rpc).newPosition, 0);
      expect(
          _screen(rpc, order: [
            ['id', 'ASC']
          ]).newPosition,
          -1);
      expect(
          _screen(rpc, order: [
            ['id', 'DESC']
          ]).newPosition,
          0);
    });

    test('new from the list switches to the form and inserts on top',
        () async {
      final rpc = _server();
      final screen = _screen(rpc);
      await screen.switchView();
      await screen.searchFilter();
      final record = await screen.newRecord();
      expect(screen.currentView!.viewType, 'form');
      expect(identical(screen.group.first, record), isTrue);
      expect(record!.id, isNegative);
      expect(record.fieldGet('name'), 'New');
      expect(screen.modified(), isTrue);
      await screen.cancelCurrent();
      expect(screen.group.length, 10);
      expect(screen.modified(), isFalse);
    });

    test('copy loads the copies at new_position and selects the first',
        () async {
      final rpc = _server();
      final screen = _screen(rpc);
      await screen.switchView();
      await screen.searchFilter();
      screen.selectedRecords = [screen.group[1]];
      expect(await screen.copy(), [100]);
      expect(rpc.named('party.party.copy').single.params, [
        [2],
        <String, dynamic>{}
      ]);
      expect(screen.group.first.id, 100);
      expect(screen.currentRecord!.id, 100);
    });

    test('delete removes the records from the group', () async {
      final rpc = _server()..handlers['delete'] = (c) => null;
      final screen = _screen(rpc);
      await screen.switchView();
      await screen.searchFilter();
      screen.selectedRecords = [screen.group[0], screen.group[1]];
      expect(await screen.remove(delete: true, forceRemove: true), isTrue);
      expect(rpc.named('party.party.delete').single.params, [
        [1, 2]
      ]);
      expect(screen.group.length, 8);
      expect(screen.selectedRecords, isEmpty);
    });
  });

  group('client actions (8.7)', () {
    test('next/previous/switch/close/reload context', () async {
      final rpc = _server();
      final screen = _screen(rpc);
      var closed = 0, contextReloaded = 0, menuReloaded = 0;
      screen
        ..onClose = (() async => closed++)
        ..onReloadContext = (() async => contextReloaded++)
        ..onReloadMenu = (() async => menuReloaded++);
      await screen.switchView();
      await screen.searchFilter();
      screen.currentRecord = screen.group.first;
      await screen.clientAction('next');
      expect(screen.currentRecord!.id, 2);
      await screen.clientAction('previous');
      expect(screen.currentRecord!.id, 1);
      await screen.clientAction('switch form');
      expect(screen.currentView!.viewType, 'form');
      await screen.clientAction('switch tree 1');
      expect(screen.currentView!.viewType, 'tree');
      await screen.clientAction('reload');
      expect(rpc.named('party.party.search'), hasLength(2));
      await screen.clientAction('close');
      await screen.clientAction('reload context');
      await screen.clientAction('reload menu');
      expect((closed, contextReloaded, menuReloaded), (1, 2, 1));
    });

    test('new/copy/delete only with access', () async {
      final rpc = _server();
      final screen = _screen(rpc);
      screen.model.access =
          const ModelAccess(create: false, delete: false, write: true);
      await screen.switchView();
      await screen.searchFilter();
      screen.selectedRecords = [screen.group.first];
      await screen.clientAction('new');
      await screen.clientAction('copy');
      await screen.clientAction('delete');
      await screen.clientAction('remove');
      expect(screen.currentView!.viewType, 'tree');
      expect(rpc.names.where((n) => n.endsWith('copy') || n.endsWith('delete')),
          isEmpty);
      expect(screen.group.length, 10);
    });
  });

  test('attributes from an act_window', () {
    final attributes = ScreenAttributes.fromActWindow({
      'res_model': 'real_estate.base_object',
      'views': [
        [1012, 'tree'],
        [1014, 'form']
      ],
      'pyson_domain': '[["type", "=", "building"]]',
      'pyson_context': '{"x": {"__class__": "Eval", "v": "company"}}',
      'pyson_order': '[["name", "ASC"]]',
      'pyson_search_value': '[]',
      'domains': [
        ['Draft', '[["state", "=", "draft"]]', true],
        ['All', '', false],
      ],
      'context_model': 'real_estate.base_object.context',
      'context_domain': '[]',
      'limit': 0,
    }, sessionContext: {
      'company': 1
    });
    expect(attributes.model, 'real_estate.base_object');
    expect(attributes.viewIds, [1012, 1014]);
    expect(attributes.mode, ['tree', 'form']);
    expect(attributes.domain, [
      ['type', '=', 'building']
    ]);
    expect(attributes.context, {'x': 1});
    expect(attributes.order, [
      ['name', 'ASC']
    ]);
    expect(attributes.tabDomain.map((t) => t.name), ['Draft', 'All']);
    expect(attributes.tabDomain.map((t) => t.domain), [
      [
        ['state', '=', 'draft']
      ],
      <dynamic>[]
    ]);
    expect(attributes.tabDomain.map((t) => t.count), [true, false]);
    expect(attributes.contextModel, 'real_estate.base_object.context');
    expect(attributes.limit, 0);
  });
}

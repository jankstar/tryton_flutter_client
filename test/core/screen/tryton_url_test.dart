import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/core/screen/tryton_url.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/core/session/profiles.dart';
import 'package:tryton_flutter_client/features/actions/url_opener.dart';

import '../model/fake_rpc.dart';

const _views = {
  'tree': {
    'type': 'tree',
    'view_id': 11,
    'arch': '<tree><field name="name"/></tree>',
    'fields': {
      'name': {'type': 'char', 'string': 'Name'},
    },
  },
  'form': {
    'type': 'form',
    'view_id': 12,
    'arch': '<form><field name="name"/></form>',
    'fields': {
      'name': {'type': 'char', 'string': 'Name'},
    },
  },
};

FakeRpc _server() => FakeRpc({
      'search': (c) => [7],
      'search_count': (c) => 1,
      'read': (c) => [
            for (final id in c.params[0] as List)
              {'id': id, 'name': 'N$id', 'rec_name': 'N$id', '_timestamp': 't'}
          ],
    });

/// URLs of screens (spec 8.9) and their evaluation (spec 12.7, E7).
void main() {
  final domain = [
    ['date', '>=', const TrytonDate(2026, 1, 31)],
    ['name', 'ilike', '%ä & b%'],
  ];

  test('round trip: list with domain, context (date), tabs, name and views',
      () async {
    final screen = TrytonScreen(
      ScreenAttributes('party.party',
          viewsPreload: _views,
          domain: domain,
          context: {'company': 1, 'at': const TrytonDate(2026, 2, 1)},
          tabDomain: const [
            TabDomain('All', []),
            TabDomain('Mine', [
              ['user', '=', 1]
            ], count: true),
          ]),
      session: fakeSession(_server()),
    );
    await screen.switchView();
    final url = screenUrl(screen,
        baseUrl: 'http://erp.example.com:8000/', database: 'tryton', name: 'Parties & Co');
    expect(url, startsWith('tryton://erp.example.com:8000/tryton/model/party.party;'));

    final parsed = TrytonUrl.parse(url)!;
    expect(parsed.host, 'erp.example.com');
    expect(parsed.port, 8000);
    expect(parsed.database, 'tryton');
    expect(parsed.type, 'model');
    expect(parsed.name, 'Parties & Co');
    final attributes = parsed.modelAttributes()!;
    expect(attributes.model, 'party.party');
    expect(attributes.mode, ['tree', 'form'], reason: 'without id');
    expect(attributes.domain, domain, reason: 'with the date type');
    expect(attributes.context, {'company': 1, 'at': const TrytonDate(2026, 2, 1)});
    expect(attributes.viewIds, [11]);
    expect([for (final t in attributes.tabDomain) (t.name, t.count)],
        [('All', false), ('Mine', true)]);
    expect(attributes.tabDomain[1].domain, [
      ['user', '=', 1]
    ]);
  });

  test('form with a record: the id in the path, its view first', () async {
    final screen = TrytonScreen(
      const ScreenAttributes('party.party',
          mode: ['tree', 'form'], viewsPreload: _views),
      session: fakeSession(_server()),
    );
    await screen.switchView();
    await screen.searchFilter();
    screen.currentRecord = screen.group.first;
    await screen.switchView(viewType: 'form');
    final url = screenUrl(screen, baseUrl: 'https://erp.example.com', database: 'db');
    expect(url, 'tryton://erp.example.com/db/model/party.party/7;views=%5B12%2C11%5D');
    final attributes = TrytonUrl.parse(url)!.modelAttributes()!;
    expect(attributes.resId, 7);
    expect(attributes.mode, ['form', 'tree']);
    expect(attributes.viewIds, [12, 11]);
  });

  test('malformed URLs and parameters are ignored', () {
    expect(TrytonUrl.parse('https://example.com/db/model/x'), isNull);
    expect(TrytonUrl.parse('tryton://host/db'), isNull, reason: 'no type');
    expect(TrytonUrl.parse('tryton://host:abc/db/model/x'), isNull);
    expect(TrytonUrl.parse('tryton://host/db/model/x;domain'), isNull,
        reason: 'strict parsing');
    expect(TrytonUrl.parse('tryton://host/db/model/x/abc')!.modelAttributes(),
        isNull, reason: 'id not a number');
    expect(
        TrytonUrl.parse('tryton://host/db/model/x;domain=%5Bbroken')!
            .modelAttributes(),
        isNull);
    final wizard =
        TrytonUrl.parse('tryton://host/db/wizard/party.check_vies;window=true')!;
    expect(wizard.type, 'wizard');
    expect(wizard.path, 'party.check_vies');
    expect(wizard.value('window', false), isTrue);
  });

  test('session and profile of a URL', () {
    final url = TrytonUrl.parse('tryton://erp.example.com:8000/prod/model/x')!;
    expect(urlMatchesSession(url, 'http://erp.example.com:8000/', 'prod'), isTrue);
    expect(urlMatchesSession(url, 'http://erp.example.com:8000/', 'test'), isFalse);
    expect(urlMatchesSession(url, 'http://other:8000/', 'prod'), isFalse);
    const profiles = [
      ConnectionProfile(name: 'Test', serverUrl: 'http://erp.example.com:8000', database: 'test'),
      ConnectionProfile(name: 'Prod', serverUrl: 'http://erp.example.com:8000', database: 'prod'),
    ];
    expect(profileFor(url, profiles)?.name, 'Prod');
    expect(
        profileFor(TrytonUrl.parse('tryton://elsewhere/prod/model/x')!, profiles),
        isNull);
  });
}

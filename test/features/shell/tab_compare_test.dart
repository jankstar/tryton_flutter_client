import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';

/// Duplicate tabs (spec 10.2, SAO `Tab.create` + `Form.compare`).
void main() {
  const base = ScreenAttributes('party.party',
      viewIds: [3, 4],
      domain: [
        ['active', '=', true]
      ],
      context: {'company': 1},
      contextDomain: '[]',
      searchValue: [
        ['name', 'ilike', '%a%']
      ],
      tabDomain: [
        TabDomain('All', [])
      ]);

  test('sameAs compares the screen attributes of 10.2', () {
    expect(
        base.sameAs(const ScreenAttributes('party.party',
            viewIds: [3, 4],
            domain: [
              ['active', '=', true]
            ],
            context: {'company': 1},
            contextDomain: '[]',
            searchValue: [
              ['name', 'ilike', '%a%']
            ],
            tabDomain: [
              TabDomain('All', [])
            ],
            // not compared
            limit: 50,
            order: [
              ['name', 'ASC']
            ])),
        isTrue);
    for (final other in const [
      ScreenAttributes('party.address'),
      ScreenAttributes('party.party', resId: 5),
      ScreenAttributes('party.party', domain: [
        ['active', '=', false]
      ]),
      ScreenAttributes('party.party', contextDomain: '[["a","=",1]]'),
      ScreenAttributes('party.party', viewIds: [3]),
      ScreenAttributes('party.party', mode: ['form', 'tree']),
      ScreenAttributes('party.party', context: {'company': 2}),
      ScreenAttributes('party.party', searchValue: [
        ['name', 'ilike', '%b%']
      ]),
      ScreenAttributes('party.party', tabDomain: [TabDomain('Other', [])]),
    ]) {
      expect(other.sameAs(base), isFalse, reason: '$other');
    }
    // no search value equals an empty one
    expect(
        const ScreenAttributes('m')
            .sameAs(const ScreenAttributes('m', searchValue: [])),
        isTrue);
  });

  test('an identical tab is activated, not duplicated', () {
    final tabs = TabsNotifier()
      ..openTab(title: 'Parties', attributes: base)
      ..openTab(title: 'Addresses', model: 'party.address');
    expect(tabs.state.activeIndex, 1);
    tabs.openTab(title: 'Parties again', attributes: base);
    expect(tabs.state.tabs.map((t) => t.title), ['Parties', 'Addresses']);
    expect(tabs.state.activeIndex, 0);

    // The tab left its first view (e.g. form opened from the list): a new
    // tab is opened.
    final id = tabs.state.tabs.first.id;
    var firstView = false;
    tabs.setFirstViewCheck(id, () => firstView);
    tabs.openTab(title: 'Parties 2', attributes: base);
    expect(tabs.state.tabs, hasLength(3));
    expect(tabs.state.activeIndex, 2);

    firstView = true;
    tabs.closeTab(tabs.state.tabs.last.id);
    tabs.openTab(title: 'Parties 3', attributes: base);
    expect(tabs.state.tabs, hasLength(2));
    expect(tabs.state.activeIndex, 0);
  });

  test('next/previous tab cyclic, board tabs recognised', () {
    final tabs = TabsNotifier()
      ..openTab(title: 'A', model: 'a')
      ..openTab(title: 'B', model: 'b')
      ..openTab(
          title: 'Board',
          attributes: const ScreenAttributes('', mode: ['board']));
    expect(tabs.state.tabs.last.isBoard, isTrue);
    expect(tabs.state.tabs.first.isBoard, isFalse);
    tabs.nextTab();
    expect(tabs.state.activeIndex, 0);
    tabs.previousTab();
    expect(tabs.state.activeIndex, 2);
    tabs.previousTab();
    expect(tabs.state.activeIndex, 1);
  });

  test('requestCloseAll stops at a cancelling tab and activates it',
      () async {
    final tabs = TabsNotifier()
      ..openTab(title: 'A', model: 'a')
      ..openTab(title: 'B', model: 'b')
      ..openTab(title: 'C', model: 'c');
    tabs.addCloseGuard(tabs.state.tabs[1].id, () async => false);
    expect(await tabs.requestCloseAll(), isFalse);
    expect(tabs.state.tabs.map((t) => t.title), ['A', 'B']);
    expect(tabs.state.activeIndex, 1);

    tabs.closeTab(tabs.state.tabs[1].id); // without asking
    expect(await tabs.requestCloseAll(), isTrue);
    expect(tabs.state.tabs, isEmpty);
  });
}

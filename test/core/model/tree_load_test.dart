import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/model/model.dart';

import 'fake_rpc.dart';
import 'model_fixtures.dart';

/// Reads of tree children (menu, hierarchical lists, x2many trees): a
/// child record's read takes the records of all sibling child groups
/// (Python `sum(self.parent.group.children, [])`), so only one read may
/// run per set of records.
void main() {
  // 1 → 11, 12; 2 → 21, 22; 3 → 31
  const childs = {
    1: [11, 12],
    2: [21, 22],
    3: [31],
  };

  late FakeRpc rpc;
  late RecordGroup root;
  late List<Completer<void>> answers;
  Object? failWith;

  TrytonModel menuModel() {
    final model = TrytonModel(
      'ir.ui.menu',
      session: fakeSession(rpc),
      sessionContext: () => const {},
    );
    model.addFields({
      'name': fieldDesc('char'),
      'childs': fieldDesc('one2many', {
        'relation': 'ir.ui.menu',
        'relation_field': 'parent',
      }),
    });
    return model;
  }

  setUp(() {
    answers = [];
    failWith = null;
    rpc = FakeRpc({
      'ir.ui.menu.read': (c) async {
        final ids = c.params[0] as List;
        // the reads of the root group answer at once
        if (!ids.any((id) => (id as int) > 10)) {
          return [
            for (final id in ids)
              {'id': id, 'name': 'M$id', 'childs': childs[id] ?? <int>[]},
          ];
        }
        final answer = Completer<void>();
        answers.add(answer);
        await answer.future;
        if (failWith case final error?) throw error;
        return [
          for (final id in ids) {'id': id, 'name': 'M$id', 'childs': <int>[]},
        ];
      },
    });
    root = RecordGroup(menuModel());
    root.load([1, 2, 3]);
  });

  Future<List<RecordGroup>> childGroups() async {
    await root.get(1)!.load('name');
    return [
      for (final id in [1, 2, 3])
        root.get(id)!.fieldGetClient('childs') as RecordGroup,
    ];
  }

  List<List<dynamic>> childReads() => [
    for (final c in rpc.named('ir.ui.menu.read'))
      if ((c.params[0] as List).any((id) => (id as int) > 10))
        c.params[0] as List,
  ];

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('sibling groups loaded at once share one read', () async {
    final groups = await childGroups();
    expect(rpc.named('ir.ui.menu.read'), hasLength(1));
    // every row of every expanded entry asks for its name (the menu)
    final loads = [
      for (final g in groups)
        for (final r in g) r.load('name', processException: false),
    ];
    await settle();
    expect(childReads(), hasLength(1), reason: 'one read for all siblings');
    expect(childReads().single, unorderedEquals([11, 12, 21, 22, 31]));
    answers.single.complete();
    await Future.wait(loads);
    expect(childReads(), hasLength(1));
    for (final g in groups) {
      for (final r in g) {
        expect(r.isLoaded('name'), isTrue, reason: 'record ${r.id}');
        expect(r.fieldGet('name'), 'M${r.id}');
      }
    }
  });

  test('a failing read: every waiting load gets the error, a later load '
      'reads again', () async {
    final groups = await childGroups();
    failWith = StateError('server down');
    final loads = [
      for (final g in groups)
        for (final r in g)
          r
              .load('name', processException: false)
              .then<Object?>((_) => null, onError: (Object e) => e),
    ];
    await settle();
    expect(childReads(), hasLength(1));
    answers.single.complete();
    final errors = await Future.wait(loads);
    expect(errors, everyElement(isA<StateError>()));

    // reset (like a reload) and try again: a new read, no stale future
    failWith = null;
    root.reload([11, 12, 21, 22, 31]);
    final again = groups[1].first.load('name');
    await settle();
    expect(childReads(), hasLength(2));
    answers.last.complete();
    await again;
    expect(groups[1].first.fieldGet('name'), 'M21');
  });

  test('a load not covered by the running read waits for it and reads '
      'only what is missing', () async {
    final groups = await childGroups();
    final first = groups.first.first.load('name');
    await settle();
    expect(childReads(), hasLength(1));
    // a record added later is not part of the running read
    final added = Record(groups[2].model, id: 32, group: groups[2]);
    groups[2].add(added, modified: false);
    final late_ = added.load('name');
    await settle();
    expect(childReads(), hasLength(1), reason: 'waits for the running read');
    answers.first.complete();
    await first;
    await settle();
    expect(childReads(), hasLength(2));
    expect(childReads().last, [32]);
    answers.last.complete();
    await late_;
    expect(added.fieldGet('name'), 'M32');
  });
}

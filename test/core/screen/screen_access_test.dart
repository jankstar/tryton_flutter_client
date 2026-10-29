import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/model/model.dart';
import 'package:tryton_flutter_client/core/screen/screen.dart';

import '../model/fake_rpc.dart';

/// Access rights (MODELACCESS) → readonly and toolbar sensitivity (spec 4,
/// 10.3).
void main() {
  const views = {
    'form': {
      'type': 'form',
      'view_id': 1,
      'arch': '<form><field name="name"/></form>',
      'fields': {
        'name': {'type': 'char', 'string': 'Name'}
      },
    },
  };

  FakeRpc server() => FakeRpc({
        'read': (c) => [
              for (final id in c.params[0] as List)
                {
                  'id': id,
                  'name': 'N$id',
                  '_timestamp': 't',
                  '_write': true,
                  '_delete': id != 2,
                }
            ],
      });

  /// A form screen on record [id] with [access] from the session.
  Future<TrytonScreen> screen(ModelAccess access, {int id = 1}) async {
    final session = fakeSession(server())..accessOf = (_) => access;
    final s = TrytonScreen(
        const ScreenAttributes('test.m', mode: ['form'], viewsPreload: views),
        session: session);
    s.load([id]);
    s.currentRecord = s.group.first;
    await s.switchView();
    return s;
  }

  test('the model takes the access of the session; explicit wins', () {
    final session = ModelSession(accessOf: (m) =>
        m == 'a' ? const ModelAccess(write: false) : null);
    expect(TrytonModel('a', session: session).access.write, isFalse);
    expect(TrytonModel('b', session: session).access.write, isTrue,
        reason: 'unknown → full access');
    expect(
        TrytonModel('a',
                session: session, access: const ModelAccess(write: true))
            .access
            .write,
        isTrue);
  });

  test('group readonly without write and create (unless skip_model_access)',
      () async {
    final ro = await screen(const ModelAccess(write: false, create: false));
    expect(ro.group.readonly, isTrue);
    expect(ro.currentRecord!.readonly, isTrue);
    ro.group.skipModelAccess = true;
    expect(ro.group.readonly, isFalse);

    final createOnly = await screen(const ModelAccess(write: false));
    expect(createOnly.group.readonly, isFalse);
  });

  test('toolbar: New/Copy create, Save create or write, Delete delete and '
      'deletable', () async {
    final full = await screen(const ModelAccess());
    expect(full.canCreate, isTrue);
    expect(full.canSave(modified: true), isTrue);
    expect(full.canSave(modified: false), isFalse);
    expect(full.canDelete, isTrue);

    final noCreate =
        await screen(const ModelAccess(create: false, delete: false));
    expect(noCreate.canCreate, isFalse);
    expect(noCreate.canSave(modified: true), isTrue, reason: 'write right');
    expect(noCreate.canDelete, isFalse);

    final notDeletable = await screen(const ModelAccess(), id: 2);
    expect(notDeletable.canDelete, isFalse, reason: '_delete of the record');

    final readOnly = await screen(const ModelAccess(
        write: false, create: false, delete: false));
    expect(readOnly.canSave(modified: true), isFalse);
  });

  test('revision view: everything disabled, the group read only', () async {
    final s = await screen(const ModelAccess());
    s.group.revision = DateTime.utc(2026, 1, 2, 3, 4, 5);
    expect(s.revision, isTrue);
    expect(s.group.readonly, isTrue);
    expect((s.canCreate, s.canSave(modified: true), s.canDelete),
        (false, false, false));
    s.group.revision = null;
    expect(s.revision, isFalse);
    expect(s.canCreate, isTrue);
  });

  test('client actions new/copy/delete check the rights', () async {
    final rpc = server()..handlers['copy'] = (_) => [9];
    final session = fakeSession(rpc)
      ..accessOf = (_) => const ModelAccess(create: false, delete: false);
    final s = TrytonScreen(
        const ScreenAttributes('test.m', mode: ['form'], viewsPreload: views),
        session: session);
    s.load([1]);
    s.currentRecord = s.group.first;
    await s.switchView();
    await s.clientAction('new');
    await s.clientAction('copy');
    await s.clientAction('delete');
    expect(rpc.names.where((n) => n.endsWith('copy') || n.endsWith('delete')),
        isEmpty);
    expect(s.group.length, 1);
  });
}

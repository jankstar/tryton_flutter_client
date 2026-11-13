import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/shared/utils/file_actions.dart';

import 'form_harness.dart';

class _FakeFiles extends FileActions {
  List<PickedFile> picks = const [];
  final opened = <String>[];
  final written = <(String, List<int>)>[];

  @override
  Future<List<PickedFile>> pick({bool multiple = false, bool images = false}) async =>
      picks;

  @override
  Future<String> writeTemp(String name, List<int> bytes) async {
    written.add((name, bytes));
    return '/tmp/$name';
  }

  @override
  Future<void> open(String path) async => opened.add(path);
}

/// Attachments, notes, logs of a form (spec 11.4–11.6, F8).
void main() {
  late _FakeFiles files;
  setUp(() => FileActions.instance = files = _FakeFiles());
  tearDown(() => FileActions.instance = FileActions());

  final attachmentFields = {
    'name': {'type': 'char', 'string': 'Name'},
    'type': {
      'type': 'selection',
      'string': 'Type',
      'selection': [
        ['data', 'Data'],
        ['link', 'Link']
      ]
    },
    'data': {'type': 'binary', 'string': 'Data', 'filename': 'name'},
    'link': {'type': 'char', 'string': 'Link'},
    'resource': {
      'type': 'reference',
      'string': 'Resource',
      'selection': [
        ['test.form', 'Form']
      ]
    },
  };
  final noteFields = {
    'message': {'type': 'text', 'string': 'Message'},
    'unread': {'type': 'boolean', 'string': 'Unread'},
    'resource': attachmentFields['resource'],
  };

  FakeFormRpc server(Map<String, Object? Function(List<dynamic>)> extra) =>
      FakeFormRpc({
        'model.test.form.fields_view_get': (_) => formView(
            '<form><field name="name"/></form>',
            {'name': {'type': 'char', 'string': 'Name'}}),
        'model.test.form.read': (p) {
          final names = p[1] as List;
          if (names.contains('xml_id')) {
            return [
              {
                'id': 1,
                'create_uid.': {'rec_name': 'Admin'},
                'create_date': DateTime(2026, 1, 2, 3, 4, 5, 6),
                'write_uid.': null,
                'write_date': null,
                'xml_id': 'party.party_1',
              }
            ];
          }
          return [
            {'id': 1, 'name': 'Rec', 'rec_name': 'Rec', '_timestamp': '1'}
          ];
        },
        'model.test.form.resources': (_) =>
            {'attachment_count': 2, 'note_count': 1, 'note_unread': 1},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        ...extra,
      });

  testWidgets('attachments: list (≤ 20), open data, Add creates records',
      (tester) async {
    final rpc = server({
      'model.ir.attachment.search_read': (p) => [
            {'id': 10, 'rec_name': 'contract.pdf', 'name': 'contract.pdf', 'type': 'data', 'link': null},
            {'id': 11, 'rec_name': 'Web', 'name': 'Web', 'type': 'link', 'link': 'https://x'},
          ],
      'model.ir.attachment.read': (p) {
        if ((p[1] as List).length == 1 && (p[1] as List).single == 'data') {
          return [
            {'id': 10, 'data': TrytonBytes('%PDF'.codeUnits)}
          ];
        }
        return <dynamic>[];
      },
      'model.ir.attachment.fields_view_get': (p) => p[1] == 'tree'
          ? {'type': 'tree', 'view_id': 1, 'arch': '<tree><field name="name"/></tree>', 'fields': attachmentFields}
          : formView('<form><field name="name"/><field name="type"/>'
              '<field name="data"/><field name="link"/></form>', attachmentFields),
      'model.ir.attachment.search': (_) => <int>[],
      'model.ir.attachment.search_count': (_) => 0,
      'model.ir.attachment.default_get': (_) => <String, dynamic>{},
      'model.ir.attachment.create': (p) => [100 + (p[0] as List).length],
      'model.ir.attachment.view_toolbar_get': (_) => <String, dynamic>{},
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.pumpAndSettle();
    expect(find.text('2'), findsWidgets, reason: 'badge of resources');

    await tester.tap(find.byKey(const ValueKey('attachment-button')));
    await tester.pumpAndSettle();
    final search = rpc.named('model.ir.attachment.search_read').single;
    expect(search.params[0], [
      ['resource', '=', 'test.form,1']
    ]);
    expect(search.params[2], 20);
    expect(find.text('contract.pdf'), findsOneWidget);
    await tester.tap(find.text('contract.pdf'));
    await tester.pumpAndSettle();
    expect(files.written.single.$1, 'contract.pdf');
    expect(files.opened, ['/tmp/contract.pdf']);

    files.picks = [
      (name: 'a.txt', bytes: Uint8List.fromList([1])),
      (name: 'b.txt', bytes: Uint8List.fromList([2, 3])),
    ];
    await tester.tap(find.byKey(const ValueKey('attachment-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attachment-add')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await pumpFrames(tester);
    expect(find.byKey(const ValueKey('attachments-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resource-dialog-close')));
    await pumpFrames(tester);
    // one create per record (Python Group.save)
    final created = [
      for (final c in rpc.named('model.ir.attachment.create'))
        ...(c.params[0] as List)
    ];
    expect(created, hasLength(2));
    expect({for (final c in created) (c as Map)['name']}, {'a.txt', 'b.txt'},
        reason: 'new records at new_position: order not relevant');
    final first = created.firstWhere((c) => (c as Map)['name'] == 'a.txt') as Map;
    expect(first['name'], 'a.txt');
    expect(first['type'], 'data');
    expect(first['resource'], 'test.form,1');
    expect((first['data'] as TrytonBytes).bytes, [1]);
  });

  testWidgets('notes: closing marks the shown notes as read', (tester) async {
    final rpc = server({
      'model.ir.note.fields_view_get': (p) => p[1] == 'tree'
          ? {
              'type': 'tree',
              'view_id': 2,
              'arch': '<tree><field name="message"/><field name="unread"/></tree>',
              'fields': noteFields
            }
          : formView('<form><field name="message"/></form>', noteFields),
      'model.ir.note.search': (_) => [5, 6],
      'model.ir.note.search_count': (_) => 2,
      'model.ir.note.read': (p) => [
            for (final id in p[0] as List)
              {'id': id, 'message': 'N$id', 'unread': id == 5, '_timestamp': '1'}
          ],
      'model.ir.note.write': (_) => null,
      'model.ir.note.view_toolbar_get': (_) => <String, dynamic>{},
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(find.byTooltip('Note'));
    await pumpFrames(tester);
    expect(find.byKey(const ValueKey('notes-dialog')), findsOneWidget);
    expect(find.text('N5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resource-dialog-close')));
    await pumpFrames(tester);
    expect(rpc.named('model.ir.note.write').single.params, [
      [5],
      {'unread': false}
    ]);
    expect(find.byKey(const ValueKey('notes-dialog')), findsNothing);
  });

  testWidgets('notes dialog: a slim toolbar like Python WinForm – no notes, '
      'attachments, actions or reports of a note', (tester) async {
    final rpc = server({
      'model.ir.note.fields_view_get': (p) => p[1] == 'tree'
          ? {
              'type': 'tree',
              'view_id': 2,
              'arch': '<tree><field name="message"/><field name="unread"/></tree>',
              'fields': noteFields
            }
          : formView('<form><field name="message"/></form>', noteFields),
      'model.ir.note.search': (_) => [5],
      'model.ir.note.search_count': (_) => 1,
      'model.ir.note.read': (p) => [
            for (final id in p[0] as List)
              {'id': id, 'message': 'N$id', 'unread': false, '_timestamp': '1'}
          ],
      'model.ir.note.write': (_) => null,
      'model.ir.note.view_toolbar_get': (_) => <String, dynamic>{},
      'model.ir.note.resources': (_) => <String, dynamic>{},
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(find.byTooltip('Note'));
    await pumpFrames(tester);
    final dialog = find.byKey(const ValueKey('notes-dialog'));
    Finder inDialog(Finder f) => find.descendant(of: dialog, matching: f);
    void slim(String view) {
      for (final tip in ['Note', 'Launch actions', 'Open report', 'Print report',
          'Related records', 'Email', 'Duplicate', 'View logs']) {
        expect(inDialog(find.byTooltip(tip)), findsNothing,
            reason: '$view: $tip');
      }
      expect(inDialog(find.byKey(const ValueKey('attachment-button'))),
          findsNothing, reason: view);
      expect(inDialog(find.byTooltip('Delete')), findsWidgets, reason: view);
    }

    slim('list');
    // the form of the note: also slim
    // (a tap opens the form on touch platforms, else the switch)
    await tester.tap(find.text('N5'));
    await pumpFrames(tester);
    final toForm = inDialog(find.byTooltip('Switch to form'));
    if (toForm.evaluate().isNotEmpty) {
      await tester.tap(toForm.first);
      await pumpFrames(tester);
    }
    expect(inDialog(find.text('N5')), findsWidgets);
    slim('form');
  });

  testWidgets('logs: header with model, ID, module/XML ID, created by/at',
      (tester) async {
    final rpc = server({
      'model.ir.model.log.fields_view_get': (p) => {
            'type': 'tree',
            'view_id': 3,
            'arch': '<tree><field name="event"/></tree>',
            'fields': {
              'event': {'type': 'char', 'string': 'Event'}
            },
          },
      'model.ir.model.log.search': (_) => <int>[],
      'model.ir.model.log.search_count': (_) => 0,
      'model.ir.model.log.view_toolbar_get': (_) => <String, dynamic>{},
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(find.byTooltip('View logs'));
    await pumpFrames(tester);
    String text(String key) => tester
        .widget<TextField>(find.byKey(ValueKey('log-$key')))
        .controller!
        .text;
    expect(find.byKey(const ValueKey('logs-dialog')), findsOneWidget);
    expect(text('model'), 'test.form');
    expect(text('id'), '1');
    expect(text('module'), 'party');
    expect(text('xml_id'), 'party_1');
    expect(text('create_uid'), 'Admin');
    expect(text('create_date'), '01/02/26 03:04:05.006000');
    expect(text('write_uid'), '');
    final read = rpc.named('model.test.form.read').last.params[1] as List;
    expect(read, containsAll(['create_uid.rec_name', 'create_date', 'write_uid.rec_name', 'write_date', 'xml_id']));
    final search = rpc.named('model.ir.model.log.search').single;
    expect(search.params[0], [
      ['resource', '=', 'test.form,1']
    ]);
  });
}

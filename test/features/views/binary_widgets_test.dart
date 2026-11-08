import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/shared/utils/file_actions.dart';

import 'form_harness.dart';

/// File actions without dialogs: [picks] are „chosen“, saved/opened
/// files are recorded.
class _FakeFiles extends FileActions {
  List<PickedFile> picks = const [];
  final saved = <(String, Uint8List)>[];
  final opened = <String>[];
  final written = <(String, List<int>)>[];

  @override
  Future<List<PickedFile>> pick({bool multiple = false, bool images = false}) async =>
      picks;

  @override
  Future<bool> save(String name, Uint8List bytes) async {
    saved.add((name, bytes));
    return true;
  }

  @override
  Future<String> writeTemp(String name, List<int> bytes) async {
    written.add((name, bytes));
    return '/tmp/$name';
  }

  @override
  Future<void> open(String path) async => opened.add(path);
}

// 1×1 transparent PNG
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48,
  0x44, 0x52, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 0x1F, 0x15, 0xC4, 0x89,
  0, 0, 0, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0, 1, 0, 0, 5, 0,
  1, 0x0D, 0x0A, 0x2D, 0xB4, 0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
  0x60, 0x82,
]);

void main() {
  late _FakeFiles files;
  setUp(() => FileActions.instance = files = _FakeFiles());
  tearDown(() => FileActions.instance = FileActions());

  /// Form test.form (record 1) with [arch]; `read` of the content
  /// (separate read of the binary field) answers [content].
  FakeFormRpc server(String arch, Map<String, dynamic> fields,
          Map<String, dynamic> values, Map<String, Object?> content) =>
      FakeFormRpc({
        'model.test.form.fields_view_get': (_) => formView(arch, fields),
        'model.test.form.read': (p) {
          final names = p[1] as List;
          if (names.length == 1 && content.containsKey(names.single)) {
            return [
              {'id': 1, names.single: content[names.single]}
            ];
          }
          return [
            {'id': 1, '_timestamp': '1.0', ...values}
          ];
        },
        'model.test.form.write': (_) => null,
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.form.resources': (_) => <String, dynamic>{},
      });

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
  }

  testWidgets('binary: size and filename, Save As reads the content, '
      'Clear, Select sets data and filename', (tester) async {
    final rpc = server(
        '<form><field name="data" filename="name" filename_visible="1"/>'
            '<field name="name" invisible="1"/></form>',
        {
          'data': {'type': 'binary', 'string': 'File', 'filename': 'name'},
          'name': {'type': 'char', 'string': 'Name'},
        },
        {'data': 2048, 'name': 'a.txt'},
        {'data': TrytonBytes('hello'.codeUnits)});
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    // only the size was loaded (context data: size)
    expect(rpc.named('model.test.form.read').first.context['test.form.data'],
        'size');
    expect(find.text('2.05kB'), findsOneWidget);
    expect(find.text('a.txt'), findsOneWidget);
    expect(find.byKey(const ValueKey('binary-select-data')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('binary-save-data')));
    await tester.pumpAndSettle();
    expect(files.saved.single.$1, 'a.txt');
    expect(String.fromCharCodes(files.saved.single.$2), 'hello',
        reason: 'content read separately');

    await tester.tap(find.byKey(const ValueKey('binary-clear-data')));
    await tester.pumpAndSettle();
    expect(find.text('0B'), findsOneWidget);
    files.picks = [(name: 'b.pdf', bytes: Uint8List.fromList([1, 2, 3]))];
    await tester.tap(find.byKey(const ValueKey('binary-select-data')));
    await tester.pumpAndSettle();
    expect(find.text('3B'), findsOneWidget);
    await save(tester);
    final values = rpc.named('model.test.form.write').single.params[1] as Map;
    expect(values['name'], 'b.pdf');
    expect((values['data'] as TrytonBytes).bytes, [1, 2, 3]);
  });

  testWidgets('image: preview of the separately read content, Clear',
      (tester) async {
    final rpc = server(
        '<form><field name="photo" widget="image" width="100" height="80" '
            'border="circle"/></form>',
        {
          'photo': {'type': 'binary', 'string': 'Photo'},
        },
        {'photo': _png.length},
        {'photo': TrytonBytes(_png)});
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image-photo')), findsOneWidget);
    expect(find.byType(ClipOval), findsWidgets, reason: 'border circle');
    await tester.tap(find.byKey(const ValueKey('binary-clear-photo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('image-photo')), findsNothing);
    await save(tester);
    expect(rpc.named('model.test.form.write').single.params[1], {'photo': null});
  });

  testWidgets('image larger than image.max_size is not loaded', (tester) async {
    final rpc = server('<form><field name="photo" widget="image"/></form>', {
      'photo': {'type': 'binary', 'string': 'Photo'},
    }, {
      'photo': 2000000
    }, {
      'photo': TrytonBytes(_png)
    });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    expect(
        rpc.named('model.test.form.read').where((c) =>
            (c.params[1] as List).length == 1 &&
            (c.params[1] as List).single == 'photo'),
        isEmpty,
        reason: 'no separate read of the content');
    expect(find.byKey(const ValueKey('image-photo')), findsNothing);
  });

  testWidgets('richtext: formatted text, toolbar, saved as sanitized HTML',
      (tester) async {
    final rpc = server(
        '<form><field name="notes" widget="richtext"/></form>',
        {
          'notes': {'type': 'text', 'string': 'Notes'},
        },
        {'notes': '<div><b>Hello</b></div>'},
        const {});
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    expect(find.byKey(const ValueKey('richtext-toolbar-notes')), findsOneWidget);
    final editor = tester.widget<QuillEditor>(find.byKey(const ValueKey('richtext-notes')));
    final controller = editor.controller;
    expect(controller.document.toPlainText(), 'Hello\n');
    expect(controller.document.toDelta().first.attributes, {'bold': true});
    // type at the end of the line (the editor continues the bold
    // style), centred
    controller.replaceText(5, 0, ' world', null);
    controller.formatText(0, 1, Attribute.centerAlignment);
    await tester.pumpAndSettle();
    await save(tester);
    expect(rpc.named('model.test.form.write').single.params[1], {
      'notes': '<div align="center"><b>Hello world</b></div>'
    });
  });

  testWidgets('richtext readonly: formatted, no toolbar', (tester) async {
    final rpc = server(
        '<form><field name="notes" widget="richtext" readonly="1"/></form>',
        {
          'notes': {'type': 'text', 'string': 'Notes'},
        },
        {'notes': '<div><i>Read</i> only</div>'},
        const {});
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    expect(find.byKey(const ValueKey('richtext-toolbar-notes')), findsNothing);
    final editor = tester.widget<QuillEditor>(find.byKey(const ValueKey('richtext-notes')));
    expect(editor.controller.readOnly, isTrue);
    expect(editor.controller.document.toPlainText(), 'Read only\n');
  });

  testWidgets('document: image preview, Open writes a temporary file',
      (tester) async {
    final rpc = server(
        '<form><field name="doc" widget="document" filename="fname"/>'
            '<field name="fname" invisible="1"/></form>',
        {
          'doc': {'type': 'binary', 'string': 'Document'},
          'fname': {'type': 'char', 'string': 'File name'},
        },
        {'doc': _png.length, 'fname': 'scan.png'},
        {'doc': TrytonBytes(_png)});
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('document-image-doc')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('document-open-doc')));
    await tester.pumpAndSettle();
    expect(files.written.single.$1, 'scan.png');
    expect(files.opened.single, '/tmp/scan.png');
  });
}

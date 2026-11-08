import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/features/actions/action_service.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';
import 'package:tryton_flutter_client/shared/utils/file_actions.dart';
import 'package:tryton_flutter_client/shared/utils/zip_reader.dart';

import '../views/form_harness.dart';

/// Writes, opens and prints without the file system.
class _FakeFiles extends FileActions {
  final written = <(String, List<int>)>[];
  final opened = <String>[];
  final printed = <(String, String)>[];

  @override
  Future<String> writeTemp(String name, List<int> bytes) async {
    written.add((name, bytes));
    return '/tmp/$name';
  }

  @override
  Future<void> open(String path) async => opened.add(path);

  @override
  Future<void> print(String name, String type, Uint8List bytes, String path) async =>
      printed.add((name, type));
}

/// A ZIP with [files]: the first stored, the others deflated.
Uint8List _zip(Map<String, String> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  void u16(BytesBuilder b, int v) => b.add([v & 0xff, v >> 8 & 0xff]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xff, v >> 8 & 0xff, v >> 16 & 0xff, v >> 24 & 0xff]);
  var i = 0;
  for (final MapEntry(key: name, value: text) in files.entries) {
    final raw = Uint8List.fromList(text.codeUnits);
    final deflate = i > 0;
    final data = deflate ? Uint8List.fromList(ZLibEncoder(raw: true).convert(raw)) : raw;
    final offset = out.length;
    u32(out, 0x04034b50);
    u16(out, 20); u16(out, 0); u16(out, deflate ? 8 : 0); u16(out, 0); u16(out, 0);
    u32(out, 0); u32(out, data.length); u32(out, raw.length);
    u16(out, name.length); u16(out, 0);
    out.add(name.codeUnits);
    out.add(data);
    u32(central, 0x02014b50);
    u16(central, 20); u16(central, 20); u16(central, 0); u16(central, deflate ? 8 : 0);
    u16(central, 0); u16(central, 0);
    u32(central, 0); u32(central, data.length); u32(central, raw.length);
    u16(central, name.length); u16(central, 0); u16(central, 0); u16(central, 0); u16(central, 0);
    u32(central, 0); u32(central, offset);
    central.add(name.codeUnits);
    i++;
  }
  final cdOffset = out.length;
  final cd = central.toBytes();
  out.add(cd);
  u32(out, 0x06054b50);
  u16(out, 0); u16(out, 0); u16(out, files.length); u16(out, files.length);
  u32(out, cd.length); u32(out, cdOffset); u16(out, 0);
  return out.toBytes();
}

/// Reports (spec 12.4, G2).
void main() {
  late FakeFormRpc rpc;
  late ActionService service;
  late _FakeFiles files;
  List<dynamic> answer = const [];

  setUp(() {
    FileActions.instance = files = _FakeFiles();
    rpc = FakeFormRpc({
      'report.account.invoice.execute': (_) => answer,
    });
    service = ActionService(
      ModelService(rpc: rpc, getContext: () => {'language': 'de'}, getDatabase: () => 'test'),
      TabsNotifier(),
      sessionContext: () => {'language': 'de'},
      userId: () => 1,
    );
  });
  tearDown(() => FileActions.instance = FileActions());

  const action = {
    'type': 'ir.action.report',
    'name': 'Invoice',
    'report_name': 'account.invoice',
  };
  const data = {
    'model': 'account.invoice',
    'id': 5,
    'ids': [5, 6]
  };

  test('execute(ids, data, ctx ∪ direct_print) → file written and opened',
      () async {
    answer = ['pdf', TrytonBytes('%PDF-1'.codeUnits), false, 'Invoice-5'];
    await service.execute(action, data: data);
    final call = rpc.named('report.account.invoice.execute').single;
    expect(call.params[0], [5, 6]);
    expect((call.params[1] as Map)['model'], 'account.invoice');
    expect(call.context['direct_print'], isFalse);
    expect(call.context['language'], 'de');
    expect(files.written.single.$1, 'Invoice-5.pdf');
    expect(String.fromCharCodes(files.written.single.$2), '%PDF-1');
    expect(files.opened, ['/tmp/Invoice-5.pdf']);
    expect(files.printed, isEmpty);
  });

  test('direct_print of the action or print_p of the server → printed',
      () async {
    answer = ['pdf', TrytonBytes('%PDF-1'.codeUnits), false, 'Invoice-5'];
    await service.execute({...action, 'direct_print': true}, data: data);
    expect(rpc.calls.last.context['direct_print'], isTrue);
    expect(files.printed, [('Invoice-5.pdf', 'pdf')]);
    expect(files.opened, isEmpty);

    answer = ['odt', TrytonBytes([1, 2]), true, 'Letter'];
    await service.execute(action, data: data);
    expect(files.printed.last, ('Letter.odt', 'odt'));
  });

  test('zip: the contained files one by one', () async {
    final zip = _zip({'a.pdf': '%PDF-a', 'sub/b.txt': 'hello hello hello'});
    expect([for (final f in readZip(zip)) (f.name, String.fromCharCodes(f.bytes))],
        [('a.pdf', '%PDF-a'), ('sub/b.txt', 'hello hello hello')]);
    answer = ['zip', TrytonBytes(zip), false, 'Invoices'];
    await service.execute(action, data: data);
    expect([for (final w in files.written) w.$1], ['a.pdf', 'b.txt']);
    expect(files.opened, ['/tmp/a.pdf', '/tmp/b.txt']);
  });
}

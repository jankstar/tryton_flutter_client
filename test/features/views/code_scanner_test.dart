import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/features/views/code_scanner.dart';

import 'form_harness.dart';

/// Code scanner (spec 11.11, F9): Scan button of a form with
/// `scan_code`, each code → `on_scan_code`, sounds, loop and submit.
void main() {
  final sounds = <bool>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sounds.clear();
    codeScannerCamera = null;
    codeScannerSound = sounds.add;
  });

  FakeFormRpc server(String mode, Object? Function(String code) onScan,
          {String states = ''}) =>
      FakeFormRpc({
        'model.test.form.fields_view_get': (_) => formView(
            '<form scan_code="$mode" scan_code_depends=\'["name"]\' $states>'
            '<field name="name"/></form>',
            {'name': {'type': 'char', 'string': 'Name'}}),
        'model.test.form.read': (_) => [
              {'id': 1, 'name': 'N1', '_timestamp': '1'}
            ],
        'model.test.form.write': (_) => null,
        'model.test.form.on_scan_code': (p) => onScan(p[1] as String),
        'model.test.form.resources': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  Future<void> scan(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const ValueKey('scan-code-entry')), code);
    await tester.tap(find.byKey(const ValueKey('scan-code-ok')));
    await tester.pumpAndSettle();
  }

  testWidgets('loop: codes with the depends values; stays open while they '
      'change the record, closes on a code without changes', (tester) async {
    final rpc = server('loop', (code) => code == 'END' ? {} : {'name': code});
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(find.byKey(const ValueKey('scan-code')));
    await tester.pumpAndSettle();
    expect(find.byType(CodeScannerDialog), findsOneWidget);
    expect(find.text('No camera available – enter or scan the code with a hand scanner.'),
        findsOneWidget);

    await scan(tester, 'ABC');
    final calls = rpc.named('model.test.form.on_scan_code');
    expect(calls.single.params, [
      {'name': 'N1', 'id': 1},
      'ABC',
    ]);
    expect(sounds, [true]);
    expect(find.byType(CodeScannerDialog), findsOneWidget, reason: 'loop');
    expect(tester.widget<TextField>(textFieldOf('Name')).controller!.text, 'ABC');

    await scan(tester, 'END');
    expect(sounds, [true, true]);
    expect(find.byType(CodeScannerDialog), findsNothing);
  });

  testWidgets('an error: failure sound, the dialog closes, the error is '
      'shown; the sound can be switched off', (tester) async {
    final rpc = server('one', (_) => throw Exception('unknown code'));
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(find.byKey(const ValueKey('scan-code')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scan-code-sound')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(codeScannerSoundKey), isFalse);
    await scan(tester, 'X');
    expect(sounds, isEmpty, reason: 'sound off');
    expect(find.byType(CodeScannerDialog), findsNothing);
    expect(find.textContaining('unknown code'), findsWidgets);
  });

  testWidgets('one with sound: failure sound on an error', (tester) async {
    final rpc = server('one', (_) => throw Exception('unknown code'));
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(find.byKey(const ValueKey('scan-code')));
    await tester.pumpAndSettle();
    await scan(tester, 'X');
    expect(sounds, [false]);
  });

  testWidgets('submit: the record is saved after the code', (tester) async {
    final rpc = server('submit', (code) => {'name': code});
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    await tester.tap(find.byKey(const ValueKey('scan-code')));
    await tester.pumpAndSettle();
    await scan(tester, 'S1');
    final writes = rpc.named('model.test.form.write');
    expect(writes, hasLength(1));
    expect(writes.single.params[1], {'name': 'S1'});
    expect(find.byType(CodeScannerDialog), findsNothing, reason: 'not loop');
  });

  testWidgets('scan_code_states: invisible hides the button', (tester) async {
    final rpc = server('one', (_) => {},
        states: 'scan_code_states=\'{"invisible": true}\'');
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    expect(find.byKey(const ValueKey('scan-code')), findsNothing);
  });
}

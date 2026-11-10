import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/views/form_label_style.dart';

import 'form_harness.dart';

/// Read-only form fields have a dotted underline, editable ones a solid
/// one (SAO `theme.less` `[readonly]`, spec 9.2.2).
void main() {
  FakeFormRpc server() => FakeFormRpc({
        'model.test.form.fields_view_get': (_) => formView(
            '<form>'
            '<label name="name"/><field name="name"/>'
            '<label name="code"/><field name="code"/>'
            '<label name="net"/><field name="net"/>'
            '<label name="state"/><field name="state"/>'
            '<label name="party"/><field name="party"/>'
            '</form>',
            {
              'name': {'type': 'char', 'string': 'Name'},
              'code': {'type': 'char', 'string': 'Code', 'readonly': true},
              'net': {'type': 'numeric', 'string': 'Net', 'readonly': true},
              'state': {
                'type': 'char',
                'string': 'State',
                'states': '{"readonly": true}',
              },
              'party': {
                'type': 'many2one',
                'string': 'Party',
                'relation': 'party.party',
                'readonly': true,
              },
            }),
        'model.test.form.read': (_) => [
              {
                'id': 1,
                '_timestamp': '1',
                'name': 'N',
                'code': 'C',
                'net': '1.00',
                'state': 'posted',
                'party': 7,
                'party.': {'id': 7, 'rec_name': 'P'},
              }
            ],
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.form.resources': (_) => <String, dynamic>{},
      });

  InputBorder? borderOf(WidgetTester tester, String label) =>
      tester.widget<TextField>(textFieldOf(label)).decoration!.border;

  testWidgets('read-only fields dotted, editable ones solid', (tester) async {
    await pumpForm(tester, server(), model: 'test.form', recordId: 1);
    final name = borderOf(tester, 'Name');
    expect(name, isA<UnderlineInputBorder>());
    expect(name, isNot(isA<DottedUnderlineInputBorder>()));
    for (final label in ['Code', 'Net', 'State', 'Party']) {
      expect(borderOf(tester, label), isA<DottedUnderlineInputBorder>(),
          reason: label);
    }
  });

  testWidgets('narrow window: dotted as well', (tester) async {
    await pumpForm(tester, server(),
        model: 'test.form', recordId: 1, size: const Size(400, 900));
    expect(borderOf(tester, 'Code'), isA<DottedUnderlineInputBorder>());
    expect(borderOf(tester, 'Name'),
        isNot(isA<DottedUnderlineInputBorder>()));
  });

  test('the decorator keeps the dots when it changes colour or width', () {
    const border = DottedUnderlineInputBorder();
    expect(border.copyWith(borderSide: const BorderSide(width: 2)),
        isA<DottedUnderlineInputBorder>());
    expect(
        ShapeBorder.lerp(const UnderlineInputBorder(), border, 1),
        isA<DottedUnderlineInputBorder>());
  });
}

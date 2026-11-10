import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'form_harness.dart';

/// Resizing the window never overflows a form (many2one buttons, labels,
/// numbers, dates) – every width from narrow to wide.
void main() {
  FakeFormRpc server() => FakeFormRpc({
        'model.test.form.fields_view_get': (_) => formView(
            '<form col="6">'
            '<label name="party"/><field name="party"/>'
            '<label name="address"/><field name="address"/>'
            '<label name="ref"/><field name="ref"/>'
            '<label name="date"/><field name="date"/>'
            '<label name="state"/><field name="state"/>'
            '<label name="amount"/><field name="amount"/>'
            '<group col="-1" colspan="6"><field name="active"/>'
            '<field name="party"/><field name="amount"/></group>'
            '</form>',
            {
              'party': {'type': 'many2one', 'string': 'Party', 'relation': 'party.party'},
              'address': {'type': 'many2one', 'string': 'Invoice Address', 'relation': 'party.address'},
              'ref': {'type': 'char', 'string': 'Reference'},
              'date': {'type': 'date', 'string': 'Invoice Date'},
              'state': {
                'type': 'selection',
                'string': 'State',
                'selection': [['draft', 'Draft'], ['posted', 'Posted']],
              },
              'amount': {'type': 'numeric', 'string': 'Untaxed Amount', 'digits': [16, 2]},
              'active': {'type': 'boolean', 'string': 'Active'},
            }),
        'model.test.form.read': (_) => [
              {
                'id': 1,
                '_timestamp': '1',
                'party': 3,
                'party.': {'rec_name': 'Mieter 34, Musterstraße 1'},
                'address': 4,
                'address.': {'rec_name': 'Musterstraße 1, 10115 Berlin'},
                'ref': '1-20-190',
                'state': 'posted',
                'active': true,
              }
            ],
        'model.test.form.resources': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
      });

  testWidgets('no overflow at any width', (tester) async {
    await pumpForm(tester, server(),
        model: 'test.form', recordId: 1, size: const Size(1400, 900));
    final errors = <String>[];
    for (var width = 1400.0; width >= 320; width -= 3) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pump();
      final e = tester.takeException();
      if (e != null) errors.add('$width: $e');
    }
    expect(errors, isEmpty);
  });
}

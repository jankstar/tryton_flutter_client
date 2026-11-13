import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/views/embedded_tree_widget.dart';
import 'package:tryton_flutter_client/features/views/tree_view.dart';

import 'form_harness.dart';

/// Form layout (spec 9.2.2, E12): grid columns shared by all rows,
/// natural widths, horizontal box, one height per row, remaining height
/// for notebook and lists, fixed button footer.
void main() {
  /// A form `test.form` (record 1) with [arch] and [fields]; one2many
  /// fields hold the lines 11 and 12 of `test.line`.
  FakeFormRpc server(String arch, Map<String, dynamic> fields,
          [Map<String, dynamic> values = const {}]) =>
      FakeFormRpc({
        'model.test.form.fields_view_get': (_) => formView(arch, fields),
        'model.test.form.read': (p) => [
              {
                'id': 1,
                '_timestamp': '1',
                for (final MapEntry(:key, :value) in fields.entries)
                  if ((value as Map)['type'] == 'one2many') key: [11, 12],
                ...values,
              }
            ],
        'model.test.form.write': (_) => null,
        'model.test.line.fields_view_get': (p) => p[1] == 'tree'
            ? {
                'type': 'tree',
                'arch': '<tree><field name="name"/></tree>',
                'fields': {
                  'name': {'type': 'char', 'string': 'Name'},
                },
              }
            : formView('<form><field name="name"/></form>', {
                'name': {'type': 'char', 'string': 'Name'},
              }),
        'model.test.line.read': (p) => [
              for (final id in p[0] as List)
                {'id': id, 'name': 'L$id', '_timestamp': '1'}
            ],
        'model.test.line.view_toolbar_get': (_) => <String, dynamic>{},
        'model.ir.model.search_read': (_) => <dynamic>[],
        'model.ir.model.get_notification': (_) => <String, dynamic>{},
        'model.test.form.resources': (_) => <String, dynamic>{},
      });

  Map<String, dynamic> char(String label) => {'type': 'char', 'string': label};
  Map<String, dynamic> lines(String label) =>
      {'type': 'one2many', 'string': label, 'relation': 'test.line'};

  /// The input box (InputDecorator) of the field labelled [label]: the
  /// label in the field, or the label cell `label:` before it (wide
  /// windows, spec 9.2.2) – then the nearest box right of it on its line.
  Rect box(WidgetTester tester, String label) {
    final inField = find.ancestor(
        of: find.byWidgetPredicate((w) =>
            (w is Text && w.data == label) ||
            (w is RichText && w.text.toPlainText() == label)),
        matching: find.byType(InputDecorator));
    if (inField.evaluate().isNotEmpty) return tester.getRect(inField.first);
    final l = tester.getRect(find.text('$label:').first);
    Rect? best;
    for (final e in find.byType(InputDecorator).evaluate()) {
      final box = e.renderObject! as RenderBox;
      final r = box.localToGlobal(Offset.zero) & box.size;
      if (r.top > l.bottom + 8 || r.bottom < l.top - 8 || r.left < l.right - 2) {
        continue;
      }
      if (best == null || r.left < best.left) best = r;
    }
    return best!;
  }

  /// The table of the x2many field titled [title].
  Rect list(WidgetTester tester, String title) => tester.getRect(find
      .ancestor(of: find.text(title), matching: find.byType(EmbeddedTreeWidget))
      .first);

  testWidgets('columns: the same widths in every row (a non-expanding '
      'column of row 1 is kept in rows 2 and 3)', (tester) async {
    // like the header of party.party
    final rpc = server(
        '<form col="6">'
        '<label name="name"/><field name="name" xexpand="1"/>'
        '<label name="code"/><field name="code"/>'
        '<group col="-1" colspan="2" id="checkboxes" xexpand="0">'
        '<label name="active"/><field name="active" xexpand="0"/></group>'
        '<newline/><label name="lang"/><field name="lang"/>'
        '<label name="ref"/><field name="ref"/>'
        '<newline/><label name="salutation"/><field name="salutation"/>'
        '</form>',
        {
          'name': char('Name'),
          'code': char('Code'),
          'active': {'type': 'boolean', 'string': 'Active'},
          'lang': char('Language'),
          'ref': char('Reference'),
          'salutation': char('Salutation'),
        });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final name = box(tester, 'Name');
    for (final label in ['Language', 'Salutation']) {
      expect(box(tester, label).left, name.left, reason: label);
      expect(box(tester, label).width, name.width, reason: label);
    }
    expect(box(tester, 'Reference').left, box(tester, 'Code').left);
    expect(box(tester, 'Reference').width, box(tester, 'Code').width);
    // (the label cell of the checkbox, spec 9.2.2)
    expect(tester.getRect(find.text('Active:')).left, greaterThan(box(tester, 'Code').right));
  });

  testWidgets('natural widths: numbers and dates do not fill their cell; the '
      'numbers of a column have the same width', (tester) async {
    final rpc = server(
        '<form><label name="planned"/><field name="planned"/>'
        '<label name="note"/><field name="note"/>'
        '<label name="owner_share"/><field name="owner_share"/>'
        '<label name="date"/><field name="date"/></form>',
        {
          'planned': {'type': 'numeric', 'string': 'Planned', 'digits': '[16, 2]'},
          'note': char('Note'),
          'owner_share': {
            'type': 'numeric',
            'string': 'Actual costs of the owner',
            'digits': '[16, 2]',
          },
          'date': {'type': 'date', 'string': 'Date'},
        });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final planned = box(tester, 'Planned');
    final share = box(tester, 'Actual costs of the owner');
    expect(planned.left, share.left);
    expect(planned.width, share.width, reason: 'one below the other');
    // the cells are half of the form (1400 px), the inputs narrower
    expect(planned.width, lessThan(400));
    expect(box(tester, 'Date').width, lessThan(400));
    // (the label columns take their part of the width)
    expect(box(tester, 'Note').width, greaterThan(planned.width * 2),
        reason: 'char fills its column');
  });

  testWidgets('one height per row: char, selection and many2one inputs line '
      'up', (tester) async {
    final rpc = server(
        '<form col="6"><field name="type"/><field name="name"/>'
        '<field name="party"/></form>',
        {
          'type': {
            'type': 'selection',
            'string': 'Type',
            'selection': [
              ['out', 'Customer'],
              ['in', 'Supplier'],
            ],
          },
          'name': char('Number'),
          'party': {'type': 'many2one', 'string': 'Party', 'relation': 'test.party'},
        },
        {
          'type': 'out',
          'party': 5,
          'party.': {'rec_name': 'P'},
        });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final number = box(tester, 'Number');
    for (final label in ['Type', 'Party']) {
      expect(box(tester, label).top, number.top, reason: label);
      expect(box(tester, label).height, number.height, reason: label);
    }
  });

  testWidgets('horizontal box (col="-1"): the fields side by side in their '
      'natural width', (tester) async {
    final rpc = server(
        '<form><group col="-1" id="box"><field name="street"/>'
        '<field name="zip"/><field name="active"/></group></form>',
        {
          'street': char('Street'),
          'zip': {'type': 'integer', 'string': 'Zip'},
          'active': {'type': 'boolean', 'string': 'Active'},
        });
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final street = box(tester, 'Street'), zip = box(tester, 'Zip');
    expect(zip.top, street.top, reason: 'one line');
    expect(zip.left, greaterThan(street.right));
    expect(street.width, lessThanOrEqualTo(220));
    expect(zip.width, lessThanOrEqualTo(120));
    expect(tester.getRect(find.text('Active')).left, greaterThan(zip.right));
  });

  testWidgets('colspan of the XML: a list without colspan shares its row',
      (tester) async {
    final rpc = server(
        '<form col="2"><field name="lines"/><field name="name"/></form>',
        {'lines': lines('Lines'), 'name': char('Name')});
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final table = list(tester, 'Lines');
    expect(box(tester, 'Name').left, greaterThan(table.right - 1));
    expect(table.width, lessThan(800), reason: 'not the whole width');
  });

  group('remaining height (yexpand)', () {
    testWidgets('a list takes the height of the window', (tester) async {
      final rpc = server('<form><field name="name"/><field name="lines" colspan="4"/></form>',
          {'name': char('Name'), 'lines': lines('Lines')});
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      expect(list(tester, 'Lines').bottom, greaterThan(850),
          reason: 'down to the end of the 1000 px window');
      expect(tester.getSize(find.byType(TreeView)).height, greaterThan(600));
    });

    testWidgets('lists side by side share it; a list shown as form keeps its '
        'natural height', (tester) async {
      final rpc = server(
          '<form><field name="addresses" mode="form,tree" colspan="4"/>'
          '<field name="contacts" colspan="2"/>'
          '<field name="categories" colspan="2"/></form>',
          {
            'addresses': lines('Addresses'),
            'contacts': lines('Contacts'),
            'categories': lines('Categories'),
          });
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      final addresses = list(tester, 'Addresses');
      final contacts = list(tester, 'Contacts');
      final categories = list(tester, 'Categories');
      expect(addresses.height, lessThan(200), reason: 'inline form: natural');
      expect(contacts.top, categories.top);
      expect(contacts.height, categories.height);
      expect(contacts.bottom, greaterThan(850), reason: 'the rest of the window');
    });

    testWidgets('a notebook takes it, its page passes it to the list',
        (tester) async {
      final rpc = server(
          '<form><field name="name"/><notebook><page string="P1" id="p1">'
          '<field name="lines" colspan="4"/></page></notebook></form>',
          {'name': char('Name'), 'lines': lines('Lines')});
      await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
      expect(list(tester, 'Lines').bottom, greaterThan(850));
    });
  });

  testWidgets('buttons of the top level in the fixed footer, their text on '
      'one line', (tester) async {
    final rpc = server(
        '<form><field name="lines" colspan="4"/>'
        '<group id="buttons" col="-1">'
        '<button name="post" string="Post the invoice with a long text"/>'
        '</group></form>',
        {'lines': lines('Lines')});
    await pumpForm(tester, rpc, model: 'test.form', recordId: 1);
    final footer = find.byKey(const ValueKey('form-button-footer'));
    expect(footer, findsOneWidget);
    final button = find.descendant(
        of: footer, matching: find.text('Post the invoice with a long text'));
    expect(button, findsOneWidget);
    expect(tester.widget<Text>(button).maxLines, 1);
    expect(tester.getRect(footer).top,
        greaterThanOrEqualTo(list(tester, 'Lines').bottom),
        reason: 'below the scrolling form');
  });

  testWidgets('a button over columns of hidden fields keeps its size, the '
      'label beside a selection its line (invoice amounts)', (tester) async {
    // like account.invoice with account_deposit: the amounts group
    // beside the taxes list
    Map<String, dynamic> amount(String label, {bool hidden = false}) => {
          'type': 'numeric',
          'string': label,
          if (hidden) 'states': '{"invisible": true}',
        };
    final rpc = server(
        '<form><group col="2" colspan="4" id="taxes_amount_state">'
        '<field name="lines"/>'
        '<group col="4" colspan="1" id="amount_state">'
        '<group col="2" colspan="2" id="reconciled_state">'
        '<label name="state"/><field name="state"/></group>'
        '<group col="4" colspan="2" id="amount">'
        '<label name="untaxed" xalign="1.0" xexpand="1" xfill="0"/>'
        '<field name="untaxed" xalign="1.0" xexpand="0"/>'
        '<label name="source_untaxed" string="expected" xalign="1.0" '
        'xexpand="1" xfill="0"/>'
        '<field name="source_untaxed" xalign="1.0" xexpand="0"/>'
        '<label name="total" xalign="1.0" xexpand="1" xfill="0"/>'
        '<field name="total" xalign="1.0" xexpand="0"/>'
        '<button name="recall_deposit" string="Recall Deposit" colspan="2"/>'
        '</group></group></group></form>',
        {
          'lines': lines('Taxes'),
          'state': {
            'type': 'selection',
            'string': 'State',
            'selection': [
              ['draft', 'Draft'],
            ],
          },
          'untaxed': amount('Untaxed'),
          'source_untaxed': amount('Source', hidden: true),
          'total': amount('Total'),
        },
        {'state': 'draft'});
    await pumpForm(tester, rpc,
        model: 'test.form', recordId: 1, size: const Size(1040, 900));
    final text = find.text('Recall Deposit');
    expect(tester.getRect(text).width, closeTo(tester.getSize(text).width, 0.5),
        reason: 'the button is not scaled down');
    expect(tester.getRect(find.text('State:')).height,
        tester.getRect(find.text('Total:')).height,
        reason: 'the label stays on one line');
  });

  testWidgets('a long label beside a date: the date keeps its natural '
      'width', (tester) async {
    final rpc = server(
        '<form col="2"><label string="A rather long label for the date field" '
        'id="l"/><field name="day"/></form>',
        {'day': {'type': 'date', 'string': 'Day'}});
    await pumpForm(tester, rpc,
        model: 'test.form', recordId: 1, size: const Size(640, 600));
    final date = tester.getSize(find.byType(InputDecorator).first);
    expect(date.width, greaterThanOrEqualTo(150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a list in a titled group (wizard of contract moves): no '
      'intrinsic size asked of the list', (tester) async {
    final rpc = server(
        '<form col="10"><group col="4" id="g1" homogeneous="1" '
        'string="Selection"><label name="name"/><field name="name" '
        'colspan="1"/><newline/><label name="lines" string=" "/>'
        '<field name="lines" colspan="1" width="200"/></group><newline/>'
        '<group col="4" id="g2" string="Execution"><label name="day"/>'
        '<field name="day"/><label name="tags"/><field name="tags"/></group>'
        '</form>',
        {
          'name': char('Name'),
          'lines': lines('Lines'),
          'day': {'type': 'date', 'string': 'Day'},
          'tags': {
            'type': 'multiselection',
            'string': 'Tags',
            'selection': [
              ['a', 'A'],
              ['b', 'B'],
            ],
          },
        });
    await pumpForm(tester, rpc,
        model: 'test.form', recordId: 1, size: const Size(1400, 900));
    expect(tester.takeException(), isNull);
    expect(list(tester, 'Lines').width, greaterThanOrEqualTo(200));
  });

  testWidgets('narrow window (< 600 px): one column', (tester) async {
    final rpc = server('<form><field name="name"/><field name="code"/></form>',
        {'name': char('Name'), 'code': char('Code')});
    await pumpForm(tester, rpc,
        model: 'test.form', recordId: 1, size: const Size(420, 900));
    expect(box(tester, 'Code').top, greaterThan(box(tester, 'Name').bottom));
    expect(box(tester, 'Code').width, box(tester, 'Name').width);
  });
}

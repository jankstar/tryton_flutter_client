import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/model/model.dart';

import '../pyson/pyson_test_helpers.dart';
import 'model_fixtures.dart';

/// RecordGroup (5.3) and x2many commands (5.7) without server.
void main() {
  late RecordGroup root;
  late Record sale;
  late RecordGroup lines;

  setUp(() {
    root = RecordGroup(saleModel());
    sale = loadedSale(root);
    lines = sale.fieldGetClient('lines') as RecordGroup;
  });

  group('child group', () {
    test('parent / parentName / childName from the field', () async {
      expect(identical(lines.parent, sale), isTrue);
      expect(lines.parentName, 'sale');
      expect(lines.childName, 'lines');
      expect(lines.map((r) => r.id), [10, 11]);
      expect(identical(lines.rootGroup, root), isTrue);
      // Preloaded values are set, not modified.
      expect(lines.get(10)!.fieldGet('quantity'), 1.0);
      expect(lines.get(10)!.modified, isFalse);
    });

    test('context: session ⊕ parent ⊕ field context, over two levels', () async {
      expect(root.context, {'language': 'de', 'company': 1});
      expect(lines.context, {
        'language': 'de',
        'company': 1,
        'sale_state': 'draft',
      });
      final line = lines.get(10)!;
      final details = line.fieldGetClient('details') as RecordGroup;
      details.context = {'own': true};
      expect(details.context, {
        'language': 'de',
        'company': 1,
        'sale_state': 'draft',
        'line_quantity': 1.0,
        'own': true,
      });
      expect(details.localContext, {
        'sale_state': 'draft',
        'line_quantity': 1.0,
        'own': true,
      });
      // The field context follows the parent values.
      await sale.fieldSetClient('state', 'done');
      expect(details.context['sale_state'], 'done');
    });

    test('_datetime from parent_datetime_field', () async {
      final model = TrytonModel('a')
        ..addFields({
          'date': fieldDesc('date'),
          'lines': fieldDesc('one2many',
              {'relation': 'b', 'relation_field': 'a', 'datetime_field': 'date'}),
        });
      final a = RecordGroup(model).newRecord();
      await a.fieldSetClient('date', DateTime(2024, 1, 2));
      final group = a.fieldGetClient('lines') as RecordGroup;
      expect(group.context['_datetime'].toString(), '2024-01-02');
      expect(group.readonly, isTrue, reason: 'history is readonly');
    });

    test('getEval / exprEval with _parent_ (nested)', () async {
      final line = lines.get(10)!;
      final details = line.fieldGetClient('details') as RecordGroup;
      final detail = details.newRecord();
      details.add(detail);
      expect(detail.exprEval(jsonEncode(eval_('_parent_line.quantity'))), 1.0);
      expect(
          detail.exprEval(jsonEncode(eval_('_parent_line._parent_sale.party'))),
          7);
      expect(detail.exprEval(jsonEncode(eval_('_parent_line.id'))), 10);
      expect(detail.getOnChangeArgs(['_parent_line._parent_sale.state']),
          {'_parent_line._parent_sale.state': 'draft'});
    });

    test('add sets the parent field and marks the parent modified', () async {
      final line = lines.newRecord();
      lines.add(line);
      await line.idle;
      expect(line.fieldGet('sale'), sale.id);
      expect(line.modifiedFields, containsAll(['id', 'sale']));
      expect(sale.modifiedFields, contains('lines'));
      expect(lines.length, 3);
    });

    test('remove / unremove', () async {
      final line = lines.get(10)!;
      lines.remove(line, remove: true);
      expect(lines.recordRemoved, [line]);
      expect(line.removed, isTrue);
      expect(lines.length, 2, reason: 'saved records stay until saved');
      lines.remove(line, remove: false);
      expect(lines.recordRemoved, isEmpty);
      expect(lines.recordDeleted, [line]);
      lines.unremove(line);
      expect(lines.recordRemoved, isEmpty);
      expect(lines.recordDeleted, isEmpty);

      final fresh = lines.newRecord();
      lines.add(fresh);
      lines.remove(fresh, remove: false);
      expect(lines.contains(fresh), isFalse, reason: 'new records leave');
      expect(fresh.destroyed, isTrue);
      expect(lines.recordDeleted, isEmpty);
    });

    test('domain: screen domains + parent field domain', () async {
      root.screenDomains.add([
        ['party', '=', 7]
      ]);
      expect(root.domain, [
        [
          ['party', '=', 7]
        ]
      ]);
      final party = sale.model.fields['party']!;
      expect(party.getDomains(sale).$1, [
        ['party', '=', 7]
      ]);
      expect(party.getDomain(sale), [
        ['id', '=', 7]
      ]);
      // Child group: [screen domains, field domain of the parent field].
      expect(lines.domain, [<dynamic>[], <dynamic>[]]);
    });
  });

  group('x2many commands (5.7)', () {
    List<dynamic> commands() => sale.model.fields['lines']!.get(sale);

    test('unchanged lines → no commands, get() leaves the field out', () async {
      expect(commands(), isEmpty);
      expect(sale.get(), isEmpty);
    });

    test('create: new lines without relation_field', () async {
      final line = lines.newRecord();
      lines.add(line);
      await line.fieldSetClient('quantity', 3);
      expect(commands(), [
        [
          'create',
          [
            {'product': null, 'quantity': 3.0}
          ]
        ]
      ]);
      expect(sale.get(), {'lines': commands()});
    });

    test('write + add: modified saved lines', () async {
      await lines.get(10)!.fieldSetClient('quantity', 5);
      expect(commands(), [
        ['add', [10]],
        [
          'write',
          [10],
          {'quantity': 5.0}
        ],
      ]);
    });

    test('add only: an existing record linked to the group', () async {
      final other = Record(lines.model, id: 20)
        ..set({'quantity': 1.0}, modified: false);
      lines.add(other, modified: false);
      expect(commands(), [
        ['add', [20]]
      ]);
    });

    test('remove and delete', () async {
      lines.remove(lines.get(10)!, remove: true);
      lines.remove(lines.get(11)!, remove: false);
      expect(commands(), [
        ['remove', [10]],
        ['delete', [11]],
      ]);
    });

    test('all commands together, in order', () async {
      final line = lines.newRecord();
      lines.add(line);
      await line.fieldSetClient('quantity', 9);
      await lines.get(10)!.fieldSetClient('product', 99);
      lines.remove(lines.get(11)!, remove: true);
      final deleted = Record(lines.model, id: 12);
      lines.add(deleted, modified: false);
      lines.remove(deleted, remove: false);
      expect(commands(), [
        ['add', [10]],
        [
          'create',
          [
            {'product': null, 'quantity': 9.0}
          ]
        ],
        [
          'write',
          [10],
          {'product': 99}
        ],
        ['remove', [11]],
        ['delete', [12]],
      ]);
    });

    test('getEval: remaining ids without removed/deleted', () async {
      final line = lines.newRecord();
      lines.add(line);
      lines.remove(lines.get(10)!, remove: false);
      expect(sale.getEval()['lines'], [11, line.id]);
      lines.remove(lines.get(11)!, remove: true);
      expect(sale.getEval()['lines'], [line.id]);
    });

    test('getOnChangeValue: values of the remaining lines', () async {
      await lines.get(10)!.fieldSetClient('quantity', 4);
      lines.remove(lines.get(11)!, remove: true);
      expect(sale.model.fields['lines']!.getOnChangeValue(sale), [
        {'quantity': 4.0, 'id': 10}
      ]);
      // many2many: id list
      final tags = sale.model.fields['tags']!;
      tags.set(sale, [5, 6]);
      expect(tags.getOnChangeValue(sale), [5, 6]);
    });

    test('readonly one2many is still written, empty one2many left out', () async {
      final readonlyLines =
          sale.fieldGetClient('readonly_lines') as RecordGroup;
      final line = readonlyLines.newRecord();
      readonlyLines.add(line);
      await line.idle;
      expect(sale.get().keys, contains('readonly_lines'));
    });

    test('setClient with ids: unknown records removed, new ones loaded', () async {
      final field = sale.model.fields['lines']!;
      await field.setClient(sale, [11, 12]);
      expect(lines.recordRemoved.map((r) => r.id), [10]);
      expect(lines.map((r) => r.id), [10, 11, 12]);
      expect(sale.modifiedFields, contains('lines'));
      // Like SAO: load(modified) marks every given id → 11 is added again
      // (harmless for the server).
      expect(commands(), [
        ['add', [11, 12]],
        ['remove', [10]],
      ]);
    });

    test('defaults: list of values creates new lines', () async {
      final newSale = RecordGroup(saleModel()).newRecord();
      await newSale.setDefault({
        'lines': [
          {'quantity': 1.0},
          {}
        ]
      });
      final group = newSale.fieldGetClient('lines') as RecordGroup;
      expect(group.length, 2);
      expect(group.every((r) => r.id < 0), isTrue);
      expect(newSale.get()['lines'], [
        [
          'create',
          [
            {'product': null, 'quantity': 1.0},
            {'product': null, 'quantity': null},
          ]
        ]
      ]);
    });

    test('on_change result: add / update / remove / delete', () async {
      await sale.model.fields['lines']!.setOnChange(sale, {
        'add': [
          [
            0,
            {'quantity': 7.0}
          ]
        ],
        'update': [
          {'id': 10, 'quantity': 2.5}
        ],
        'remove': [11],
      });
      expect(lines.first.id, isNegative);
      expect(lines.first.fieldGet('quantity'), 7.0);
      expect(lines.get(10)!.fieldGet('quantity'), 2.5);
      expect(lines.recordRemoved.map((r) => r.id), [11]);
      expect(sale.modifiedFields, contains('lines'));
      await sale.model.fields['lines']!.setOnChange(sale, {'delete': [10]});
      expect(lines.recordDeleted.map((r) => r.id), [10]);
    });

    test('on_change result: a list replaces the content', () async {
      await sale.model.fields['lines']!.setOnChange(sale, [
        {'quantity': 1.0}
      ]);
      final created = lines.where((r) => r.id < 0).toList();
      expect(created, hasLength(1));
    });
  });

  group('timestamps (5.4.4)', () {
    test('only the record when no child is touched', () async {
      expect(sale.getTimestamp(), {'sale.sale,1': '100.0'});
    });

    test('modified, removed and deleted children are included', () async {
      await lines.get(10)!.fieldSetClient('quantity', 3);
      expect(sale.getTimestamp(), {
        'sale.sale,1': '100.0',
        'sale.line,10': '110.0',
      });
      lines.remove(lines.get(11)!, remove: false);
      expect(sale.getTimestamp(), {
        'sale.sale,1': '100.0',
        'sale.line,10': '110.0',
        'sale.line,11': '111.0',
      });
    });

    test('grandchildren of a modified child are included', () async {
      final line = lines.get(10)!;
      line.set({
        'details': [100],
        'details.': [
          {'id': 100, 'note': 'x', '_timestamp': '120.0'}
        ],
      }, modified: false);
      final details = line.fieldGetClient('details') as RecordGroup;
      await details.get(100)!.fieldSetClient('note', 'y');
      expect(sale.getTimestamp(), {
        'sale.sale,1': '100.0',
        'sale.line,10': '110.0',
        'sale.line.detail,100': '120.0',
      });
    });
  });

  group('root group', () {
    test('load: placeholders, preloaded values, removed lists cleaned', () async {
      final group = RecordGroup(saleModel());
      group.load([1, 2], preloaded: {
        2: {'name': 'Zwei'}
      });
      expect(group.map((r) => r.id), [1, 2]);
      expect(group.get(1)!.loaded, isEmpty);
      expect(group.get(2)!.fieldGet('name'), 'Zwei');
      group.remove(group.get(1)!, remove: true, modified: false);
      group.remove(group.get(2)!, remove: false, modified: false);
      group.load([2, 3]);
      // 2 is loaded again → no longer deleted; 1 stays removed.
      expect(group.recordDeleted, isEmpty);
      expect(group.recordRemoved.map((r) => r.id), [1]);
      expect(group.map((r) => r.id), [1, 2, 3]);
    });

    test('load(modified) marks the records and notifies', () async {
      final group = RecordGroup(saleModel());
      var notified = 0;
      group.addListener(() => notified++);
      group.load([4], modified: true);
      expect(group.get(4)!.modifiedFields, {'id'});
      expect(notified, 1);
    });

    test('reload resets unchanged records only', () async {
      final group = RecordGroup(saleModel());
      final a = loadedSale(group);
      group.load([2], preloaded: {
        2: {'name': 'B'}
      });
      final b = group.get(2)!;
      await b.fieldSetClient('name', 'B2');
      group.reload([1, 2]);
      expect(a.loaded, isEmpty);
      expect(b.fieldGet('name'), 'B2');
    });

    test('without a ModelRpc server calls fail with NoModelRpc', () async {
      await sale.fieldSetClient('name', 'Neu');
      expect(root.save(), throwsA(isA<NoModelRpc>()));
      expect(RecordGroup(saleModel()).delete([sale]),
          throwsA(isA<NoModelRpc>()));
    });
  });
}

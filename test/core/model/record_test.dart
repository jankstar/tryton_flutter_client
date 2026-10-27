import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/model/model.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

import '../pyson/pyson_test_helpers.dart';
import 'model_fixtures.dart';

void main() {
  group('TrytonModel', () {
    test('addFields adds new fields and extends existing descriptions', () {
      final model = TrytonModel('x');
      expect(
          model.addFields({
            'a': fieldDesc('char'),
            'b': fieldDesc('integer'),
          }),
          ['a', 'b']);
      expect(model.fields['a'], isA<CharField>());
      expect(model.fields['a']!.name, 'a');
      expect(
          model.addFields({
            'a': {'help': 'Hilfe'},
            'c': fieldDesc('many2one', {'relation': 'y'}),
          }),
          ['c']);
      expect(model.fields['a'], isA<CharField>());
      expect(model.fields['a']!.description['help'], 'Hilfe');
    });

    test('a field class for every type (5.6)', () {
      final types = {
        'char': CharField,
        'text': TextField,
        'selection': SelectionField,
        'multiselection': MultiSelectionField,
        'boolean': BooleanField,
        'integer': IntegerField,
        'float': FloatField,
        'numeric': NumericField,
        'date': DateField,
        'datetime': DateTimeField,
        'timestamp': DateTimeField,
        'time': TimeField,
        'timedelta': TimeDeltaField,
        'many2one': Many2OneField,
        'one2one': One2OneField,
        'reference': ReferenceField,
        'one2many': One2ManyField,
        'many2many': Many2ManyField,
        'binary': BinaryField,
        'dict': DictField,
        'unknown': CharField,
      };
      for (final MapEntry(key: type, value: cls) in types.entries) {
        expect(Field.create({'name': 'f', 'type': type}).runtimeType, cls,
            reason: type);
      }
    });

    test('server methods are marked stubs', () {
      expect(() => TrytonModel('x').execute('read', []),
          throwsA(isA<NotYetImplemented>()));
    });
  });

  group('Record state', () {
    test('new records get negative ids from a global counter', () {
      final model = saleModel();
      final a = Record(model);
      final b = Record(model);
      final c = RecordGroup(model).newRecord();
      expect(a.id, isNegative);
      expect(b.id, a.id - 1);
      expect(c.id, b.id - 1);
      // An explicit id does not use the counter.
      final saved = Record(model, id: 5);
      expect(saved.id, 5);
      expect(Record(model).id, c.id - 1);
    });

    test('set: values loaded, not modified; oldest _timestamp kept', () {
      final sale = loadedSale(RecordGroup(saleModel()));
      expect(sale.modified, isFalse);
      expect(sale.loaded, containsAll(['name', 'state', 'party', 'lines']));
      expect(sale.timestamp, '100.0');
      sale.set({'_timestamp': '200.0', 'name': 'S2'}, modified: false);
      expect(sale.timestamp, '100.0');
      expect(sale.fieldGet('name'), 'S2');
      // rec_name is kept, unknown fields are ignored.
      sale.set({'rec_name': 'S2 (Jan)', 'unknown': 1}, modified: false);
      expect(sale.values['rec_name'], 'S2 (Jan)');
      expect(sale.values.containsKey('unknown'), isFalse);
    });

    test('setClient marks modifiedFields only on a real change', () {
      final sale = loadedSale(RecordGroup(saleModel()));
      sale.fieldSetClient('name', '  S1 ');
      expect(sale.modifiedFields, isEmpty, reason: 'strip → same value');
      sale.fieldSetClient('name', 'Neu');
      expect(sale.modifiedFields, {'name'});
      sale.fieldSetClient('party', [8, 'Eva']);
      expect(sale.modifiedFields, {'name', 'party'});
      sale.fieldSetClient('sale_date', null, forceChange: true);
      expect(sale.modifiedFields, {'name', 'party'});
      expect(sale.modified, isTrue);
    });

    test('changes notify the listeners of the root group', () {
      final group = RecordGroup(saleModel());
      final sale = loadedSale(group);
      var notified = 0;
      group.addListener(() => notified++);
      sale.fieldSetClient('name', 'Neu');
      expect(notified, 1);
      sale.fieldSetClient('name', 'Neu');
      expect(notified, 1);
      // A change in a child line reaches the root group.
      final line = (sale.fieldGetClient('lines') as RecordGroup).get(10)!;
      line.fieldSetClient('quantity', 5);
      expect(notified, 2);
    });

    test('get: only modified fields, no readonly, no empty x2many', () {
      final sale = loadedSale(RecordGroup(saleModel()));
      expect(sale.get(), isEmpty);
      sale.fieldSetClient('name', 'Neu');
      sale.fieldSetClient('total', TrytonDecimal('9'));
      expect(sale.get(), {'name': 'Neu'});

      final newSale = RecordGroup(saleModel()).newRecord();
      // New record: all fields, but not the readonly numeric and no empty
      // x2many commands.
      expect(newSale.get(), {
        'name': '',
        'state': null,
        'party': null,
        'sale_date': null,
      });
    });

    test('getEval: loaded fields in eval format and id', () {
      final sale = loadedSale(RecordGroup(saleModel()));
      expect(sale.getEval(), {
        'name': 'S1',
        'state': 'draft',
        'party': 7,
        'sale_date': null,
        'lines': [10, 11],
        'id': 1,
      });
    });

    test('getOnChangeValue: saved record only loaded and modified fields', () {
      final sale = loadedSale(RecordGroup(saleModel()));
      expect(sale.getOnChangeValue(), {'id': 1});
      sale.fieldSetClient('party', [8, 'Eva']);
      expect(sale.getOnChangeValue(), {'party': 8, 'id': 1});
      expect(sale.getOnChangeValue(skip: ['party']), {'id': 1});
    });

    test('rights: _write/_delete, group access, history, removed', () {
      final group = RecordGroup(saleModel());
      final sale = loadedSale(group);
      expect((sale.readonly, sale.deletable), (false, true));
      sale.set({'_write': false, '_delete': false}, modified: false);
      expect((sale.canWrite, sale.canDelete), (false, false));
      expect((sale.readonly, sale.deletable), (true, false));

      final noAccess = RecordGroup(saleModel(
          access: const ModelAccess(write: false, create: false)));
      expect(noAccess.readonly, isTrue);
      expect(noAccess.newRecord().readonly, isTrue);
      expect((noAccess..skipModelAccess = true).readonly, isFalse);

      final history = RecordGroup(saleModel(), context: {'_datetime': 1});
      expect(history.readonly, isTrue);

      final group2 = RecordGroup(saleModel());
      final sale2 = loadedSale(group2);
      group2.remove(sale2, remove: true);
      expect(sale2.removed, isTrue);
      expect(sale2.readonly, isTrue);
    });

    test('cancel discards values and flags', () {
      final sale = loadedSale(RecordGroup(saleModel()));
      sale.fieldSetClient('name', 'Neu');
      sale.exception = true;
      sale.cancel();
      expect(sale.values, isEmpty);
      expect(sale.loaded, isEmpty);
      expect(sale.modified, isFalse);
      expect(sale.timestamp, isNull);
      expect(sale.exception, isFalse);
    });

    test('exprEval: PYSON string with record values, context, active_*', () {
      final sale = loadedSale(RecordGroup(saleModel()));
      expect(sale.exprEval(jsonEncode(eval_('party'))), 7);
      expect(sale.exprEval(jsonEncode(eval_('context.language'))), 'de');
      expect(sale.exprEval(jsonEncode(eval_('active_model'))), 'sale.sale');
      expect(sale.exprEval(jsonEncode(eval_('active_id'))), 1);
      expect(sale.exprEval(''), isNull);
      expect(sale.exprEval('[]'), isEmpty);
      expect(sale.exprEval('{}'), isEmpty);
    });

    test('setState evaluates states into stateAttrs', () {
      final sale = loadedSale(RecordGroup(saleModel()));
      final state = sale.model.fields['state']!;
      state.setState(sale);
      expect(state.stateAttrs(sale)['readonly'], isFalse);
      sale.set({'state': 'done'}, modified: false);
      state.setState(sale);
      expect(state.stateAttrs(sale)['readonly'], isTrue);
    });

    test('getPath / getIndexPath / rootParent', () {
      final group = RecordGroup(saleModel());
      final sale = loadedSale(group);
      final lines = sale.fieldGetClient('lines') as RecordGroup;
      final line = lines.get(11)!;
      // Like SAO: the child field name is attached to the parent entry
      // (get_by_path: record 1, then its field 'lines', then record 11).
      expect(line.getPath(), [('lines', 1), ('', 11)]);
      expect(line.getIndexPath(), [0, 1]);
      expect(identical(line.rootParent, sale), isTrue);
    });

    test('record server methods are marked stubs', () {
      final sale = loadedSale(RecordGroup(saleModel()));
      expect(sale.save(), throwsA(isA<NotYetImplemented>()));
      expect(sale.defaultGet(), throwsA(isA<NotYetImplemented>()));
      expect(Record(sale.model, id: 9).load('name'),
          throwsA(isA<NotYetImplemented>()));
      // Already loaded / new records need no server.
      expect(sale.load('name'), completes);
      expect(RecordGroup(saleModel()).newRecord().reload(), completes);
    });
  });
}

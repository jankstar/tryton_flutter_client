import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/model/model.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

import 'model_fixtures.dart';

/// Field classes (spec 5.6) without server.
void main() {
  late TrytonModel model;
  late Record record;

  setUp(() {
    model = TrytonModel('test.model')
      ..addFields({
        'char': fieldDesc('char'),
        'lead': fieldDesc('char', {'strip': 'leading'}),
        'sel': fieldDesc('selection'),
        'multi': fieldDesc('multiselection'),
        'flag': fieldDesc('boolean'),
        'int': fieldDesc('integer'),
        'float': fieldDesc('float', {'digits': '[16, 2]'}),
        'num': fieldDesc('numeric'),
        'date': fieldDesc('date'),
        'dt': fieldDesc('datetime'),
        'time': fieldDesc('time'),
        'delta': fieldDesc('timedelta', {'converter': 'conv'}),
        'm2o': fieldDesc('many2one', {'relation': 'party.party'}),
        'ref': fieldDesc('reference'),
        'bin': fieldDesc('binary'),
        'dict': fieldDesc('dict'),
      });
    record = RecordGroup(model, context: {'conv': {'h': 3600}}).newRecord();
  });

  test('char: default "", strip', () async {
    expect(record.fieldGet('char'), '');
    await record.fieldSetClient('char', null);
    expect(record.fieldGet('char'), '');
    await record.fieldSetClient('lead', '  x  ');
    expect(record.fieldGet('lead'), 'x  ');
  });

  test('selection: setClient drops the server label', () async {
    record.set({'sel': 'a', 'sel:string': 'A'}, modified: false);
    expect(record.values['sel:string'], 'A');
    await record.fieldSetClient('sel', 'b');
    expect(record.values.containsKey('sel:string'), isFalse);
    expect(record.fieldGet('sel'), 'b');
  });

  test('multiselection: sorted, empty → null, get_eval → []', () async {
    expect(record.fieldGet('multi'), isNull);
    expect(model.fields['multi']!.getEval(record), <dynamic>[]);
    await record.fieldSetClient('multi', ['b', 'a']);
    expect(record.fieldGet('multi'), ['a', 'b']);
    await record.fieldSetClient('multi', 'c');
    expect(record.fieldGet('multi'), ['c']);
    await record.fieldSetClient('multi', null);
    expect(record.fieldGet('multi'), isNull);
    expect(model.fields['multi']!.singleValue, isFalse);
  });

  test('boolean: never null', () async {
    expect(record.fieldGet('flag'), isFalse);
    await record.fieldSetClient('flag', 1);
    expect(record.fieldGet('flag'), isTrue);
    record.set({'flag': null}, modified: false);
    expect(record.fieldGet('flag'), isFalse);
  });

  test('integer / float / numeric: convert and factor', () async {
    await record.fieldSetClient('int', '42');
    expect(record.fieldGet('int'), 42);
    await record.fieldSetClient('int', 'abc');
    expect(record.fieldGet('int'), isNull);
    await record.fieldSetClient('float', '1.5');
    expect(record.fieldGet('float'), 1.5);
    final float = model.fields['float'] as FloatField;
    // Percent: input 12.345 % with factor 100, rounded to the digits.
    await float.setClient(record, 12.345, factor: 100);
    expect(record.fieldGet('float'), 0.12);
    expect(float.getClient(record, factor: 100), 12.0);
    expect(float.digits(record), [16, 2]);
    expect(float.digits(record, factor: 100), [18, 0]);
    await record.fieldSetClient('num', '3.10');
    expect(record.fieldGet('num'), const TrytonDecimal('3.10'));
    await record.fieldSetClient('num', '');
    expect(record.fieldGet('num'), isNull);
  });

  test('date / datetime / time conversions', () async {
    await record.fieldSetClient('date', DateTime(2024, 5, 17, 13, 5));
    expect(record.fieldGet('date'), const TrytonDate(2024, 5, 17));

    await record.fieldSetClient('dt', const TrytonDate(2024, 5, 17));
    expect(record.fieldGet('dt'), DateTime(2024, 5, 17));
    await record.fieldSetClient('dt', const TrytonTime(9, 30, 0, 0));
    expect(record.fieldGet('dt'), DateTime(2024, 5, 17, 9, 30));
    await record.fieldSetClient('dt', const TrytonDate(2024, 6, 1));
    expect(record.fieldGet('dt'), DateTime(2024, 6, 1, 9, 30),
        reason: 'keeps the time');
    await record.fieldSetClient('dt', null);
    await record.fieldSetClient('dt', const TrytonTime(9, 30, 0, 0));
    expect(record.fieldGet('dt'), isNull, reason: 'no date to combine');

    await record.fieldSetClient('time', DateTime(2024, 5, 17, 8, 15, 30));
    final t = record.fieldGet('time') as TrytonTime;
    expect((t.hour, t.minute, t.second), (8, 15, 30));
  });

  test('timedelta: Duration, converter from the group context', () async {
    await record.fieldSetClient('delta', const Duration(hours: 2));
    expect(record.fieldGet('delta'), const Duration(hours: 2));
    expect((model.fields['delta'] as TimeDeltaField).converter(record.group),
        {'h': 3600});
  });

  test('many2one: id + rec_name, negative ids only for the parent field', () async {
    final m2o = model.fields['m2o']!;
    record.set({
      'm2o': 5,
      'm2o.': {'rec_name': 'Jan'}
    }, modified: false);
    expect(record.fieldGet('m2o'), 5);
    expect(record.fieldGetClient('m2o'), 'Jan');
    expect(m2o.getEval(record), 5);
    await record.fieldSetClient('m2o', 5);
    expect(record.fieldGetClient('m2o'), 'Jan', reason: 'same id keeps name');
    await record.fieldSetClient('m2o', [6, 'Eva']);
    expect((record.fieldGet('m2o'), record.fieldGetClient('m2o')), (6, 'Eva'));
    await record.fieldSetClient('m2o', 7);
    expect(record.fieldGetClient('m2o'), '');
    await record.fieldSetClient('m2o', -3);
    expect(record.fieldGet('m2o'), isNull);
    expect(m2o.isEmpty(record), isTrue);
  });

  test('reference: [model, id] inside, "model,id" outside', () async {
    final ref = model.fields['ref']!;
    record.set({
      'ref': 'party.party,5',
      'ref.': {'rec_name': 'Jan'}
    }, modified: false);
    expect(record.fieldGet('ref'), 'party.party,5');
    expect(ref.getEval(record), 'party.party,5');
    expect(record.fieldGetClient('ref'), ['party.party', 'Jan']);
    await record.fieldSetClient('ref', [
      'sale.sale',
      [7, 'S7']
    ]);
    expect(record.fieldGet('ref'), 'sale.sale,7');
    expect(record.fieldGetClient('ref'), ['sale.sale', 'S7']);
    await record.fieldSetClient('ref', 'sale.sale,7');
    expect(record.fieldGetClient('ref'), ['sale.sale', 'S7']);
    await record.fieldSetClient('ref', ['sale.sale', -2]);
    expect(ref.isEmpty(record), isTrue);
    await record.fieldSetClient('ref', null);
    expect(record.fieldGet('ref'), isNull);
    expect(record.fieldGetClient('ref'), isNull);
  });

  test('binary: size, change by identity, content is a stub', () async {
    final bin = model.fields['bin'] as BinaryField;
    final bytes = TrytonBytes([1, 2, 3]);
    await record.fieldSetClient('bin', bytes);
    expect(bin.getSize(record), 3);
    record.modifiedFields.clear();
    await record.fieldSetClient('bin', bytes);
    expect(record.modified, isFalse);
    expect(await bin.getData(record), same(bytes));
    final saved = Record(model, id: 3)..set({'bin': 1024}, modified: false);
    expect(bin.getSize(saved), 1024);
    expect(bin.getData(saved), throwsA(isA<NoModelRpc>()));
  });

  test('dict: keys sorted, get returns a copy', () async {
    await record.fieldSetClient('dict', {'b': 1, 'a': 2});
    final value = record.fieldGet('dict') as Map;
    expect(value.keys, ['a', 'b']);
    value['c'] = 3;
    expect((record.fieldGet('dict') as Map).containsKey('c'), isFalse);
    record.modifiedFields.clear();
    await record.fieldSetClient('dict', {'a': 2, 'b': 1});
    expect(record.modified, isFalse, reason: 'same content');
  });

  test('setDefault / setOnChange mark the field modified', () async {
    final saved = Record(model, id: 4);
    await saved.setDefault({'char': 'x', 'm2o': 3, 'm2o.': {'rec_name': 'P'}});
    expect(saved.modifiedFields, containsAll(['char', 'm2o']));
    expect(saved.fieldGetClient('m2o'), 'P');
    saved.modifiedFields.clear();
    // A field of a saved record must be loaded before set_on_change.
    saved.set({'int': 1}, modified: false);
    await saved.setOnChange({'int': 3, 'unknown': 1});
    expect(saved.modifiedFields, {'int'});
  });
}

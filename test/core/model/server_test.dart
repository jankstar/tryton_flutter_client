import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/model/model.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';

import 'fake_rpc.dart';
import 'model_fixtures.dart';

/// Data layer part 2 (D2–D8, D10) against a fake ModelRpc.
void main() {
  group('load (D2)', () {
    late FakeRpc rpc;
    late RecordGroup group;

    Map<String, dynamic> saleValues(int id) => {
          'id': id,
          'name': 'S$id',
          'state': 'draft',
          'party': 7,
          'party.': {'id': 7, 'rec_name': 'Jan'},
          'lines': <int>[],
          'rec_name': 'S$id',
          '_timestamp': '$id.5',
          '_write': true,
          '_delete': id != 4,
        };

    setUp(() {
      rpc = FakeRpc({
        'sale.sale.read': (c) => [
              for (final id in c.params[0] as List) saleValues(id as int)
            ],
      });
      group = RecordGroup(saleModel(modelSession: fakeSession(rpc, limit: 30)));
      group.load([1, 2, 3, 4, 5]);
    });

    test('eager: neighbours (limit / min(fields, 10)) and extra fields',
        () async {
      await group.get(3)!.load('name');
      final call = rpc.calls.single;
      expect(call.name, 'sale.sale.read');
      // 13 fields → limit 30 ~/ 10 = 3 records: itself, then alternating.
      expect(call.params[0], [3, 2, 4]);
      expect(
          call.params[1],
          containsAll([
            'name',
            'state',
            'party',
            'party.rec_name',
            'lines',
            'rec_name',
            '_timestamp',
            '_write',
            '_delete',
          ]));
      expect(call.params[1], isNot(contains('total.rec_name')));
      expect(call.context['language'], 'de');
      expect(group.get(2)!.isLoaded('name'), isTrue);
      expect(group.get(1)!.isLoaded('name'), isFalse);
      expect(group.get(5)!.isLoaded('name'), isFalse);
    });

    test('answer format: <f>. dict, rights, timestamp', () async {
      final r = group.get(4)!;
      await r.load('party');
      expect(r.fieldGet('party'), 7);
      expect(r.fieldGetClient('party'), 'Jan');
      expect(r.timestamp, '4.5');
      expect((r.canWrite, r.deletable), (true, false));
      expect(r.values['rec_name'], 'S4');
      expect(r.modified, isFalse);
    });

    test('locally modified fields are not overwritten', () async {
      final r2 = group.get(2)!;
      await r2.fieldSetClient('name', 'Lokal');
      await group.get(3)!.load('name');
      expect(r2.fieldGet('name'), 'Lokal');
      expect(r2.fieldGet('state'), 'draft');
      expect(group.get(3)!.fieldGet('name'), 'S3');
    });

    test('loaded fields are not read again', () async {
      await group.get(3)!.load('name');
      await group.get(3)!.load('state');
      await group.get(2)!.load('name');
      expect(rpc.calls, hasLength(1));
    });

    test('error: exception = true, values null, error rethrown', () async {
      rpc.handlers['sale.sale.read'] = (_) => throw const UserError('kaputt');
      await expectLater(group.get(3)!.load('name'), throwsA(isA<UserError>()));
      final r = group.get(3)!;
      expect(r.exception, isTrue);
      expect(r.readonly, isTrue);
      expect(r.fieldGet('party'), isNull);
      expect(r.isLoaded('name'), isTrue);
    });

    test('binary fields only as size; lazy loading with x2many sub-fields',
        () async {
      final rpc = FakeRpc({
        'test.lazy.read': (c) => [
              {
                'id': 1,
                'name': 'L',
                'image': 2048,
                'lines': [10],
                'lines.': [
                  {
                    'id': 10,
                    'qty': 2.0,
                    'product': 3,
                    'product.': {'rec_name': 'P3'},
                    '_timestamp': '10.0',
                  }
                ],
              }
            ],
      });
      final model = TrytonModel('test.lazy', session: fakeSession(rpc))
        ..addFields({
          'name': fieldDesc('char', {'loading': 'lazy'}),
          'image': fieldDesc('binary', {'loading': 'lazy'}),
          'lines': fieldDesc('one2many', {
            'relation': 'test.line',
            'loading': 'lazy',
            'visible': true,
            'views': {
              'tree': {
                'fields': {
                  'qty': fieldDesc('float'),
                  'product': fieldDesc('many2one', {'relation': 'p'}),
                }
              }
            },
          }),
        });
      final g = RecordGroup(model)..load([1, 2]);
      await g.get(1)!.load('name');
      final call = rpc.calls.single;
      expect(call.params[0], [1], reason: 'lazy: no neighbours');
      expect(
          call.params[1],
          containsAll([
            'name',
            'image',
            'lines',
            'lines.qty',
            'lines.product',
            'lines.product.rec_name',
            'lines._timestamp',
            'lines._write',
            'lines._delete',
          ]));
      expect(call.context['test.lazy.image'], 'size');
      expect(call.context['related_read_limit'], 20);
      final record = g.get(1)!;
      expect((model.fields['image'] as BinaryField).getSize(record), 2048);
      final line = (record.fieldGetClient('lines') as RecordGroup).get(10)!;
      expect(line.fieldGet('qty'), 2.0);
      expect(line.fieldGetClient('product'), 'P3');
      expect(line.timestamp, '10.0');
    });

    test('id lists in batches of 1000', () async {
      final rpc = FakeRpc({
        'test.batch.read': (c) => [
              for (final id in c.params[0] as List) {'id': id, 'name': 'n'}
            ],
      });
      final model =
          TrytonModel('test.batch', session: fakeSession(rpc, limit: 30000))
            ..addFields({'name': fieldDesc('char')});
      final g = RecordGroup(model)
        ..load([for (var i = 1; i <= 2500; i++) i]);
      await g.first.load('name');
      expect([for (final c in rpc.calls) (c.params[0] as List).length],
          [1000, 1000, 500]);
      expect(g.every((r) => r.isLoaded('name')), isTrue);
    });
  });

  group('save (D3, D4)', () {
    late FakeRpc rpc;
    late RecordGroup root;

    setUp(() {
      rpc = FakeRpc({
        'sale.sale.create': (c) => [42],
        'sale.sale.write': (c) => null,
        'sale.sale.read': (c) => [
              for (final id in c.params[0] as List)
                {'id': id, 'name': 'S', '_timestamp': '200.0'}
            ],
      });
      root = RecordGroup(saleModel(modelSession: fakeSession(rpc)));
    });

    test('create: values incl. x2many create command, then reload',
        () async {
      final sale = root.add(root.newRecord());
      await sale.fieldSetClient('name', 'Neu');
      final lines = sale.fieldGetClient('lines') as RecordGroup;
      final line = lines.add(lines.newRecord());
      await line.fieldSetClient('quantity', 2);
      await line.idle;
      await sale.idle;
      expect(await sale.save(), isTrue);
      expect(rpc.names, ['sale.sale.create', 'sale.sale.read']);
      expect(rpc.calls.first.params, [
        [
          {
            'name': 'Neu',
            'state': null,
            'party': null,
            'sale_date': null,
            'lines': [
              [
                'create',
                [
                  {'product': null, 'quantity': 2.0}
                ]
              ]
            ],
          }
        ]
      ]);
      expect(sale.id, 42);
      expect(rpc.calls[1].params[0], [42]);
      expect(sale.modified, isFalse);
      expect(sale.timestamp, '200.0');
    });

    test('write: only modified values, _timestamp incl. modified children',
        () async {
      final sale = loadedSale(root);
      final lines = sale.fieldGetClient('lines') as RecordGroup;
      await lines.get(10)!.fieldSetClient('quantity', 5);
      await sale.idle;
      expect(await sale.save(), isTrue);
      final write = rpc.named('sale.sale.write').single;
      expect(write.params, [
        [1],
        {
          'lines': [
            ['add', [10]],
            [
              'write',
              [10],
              {'quantity': 5.0}
            ],
          ]
        }
      ]);
      expect(write.context['_timestamp'], {
        'sale.sale,1': '100.0',
        'sale.line,10': '110.0',
      });
      expect(write.context['language'], 'de');
    });

    test('a child record is saved through its parent', () async {
      final sale = loadedSale(root);
      final line = (sale.fieldGetClient('lines') as RecordGroup).get(11)!;
      await line.fieldSetClient('quantity', 9);
      await sale.idle;
      expect(await line.save(), isTrue);
      expect(rpc.names, ['sale.sale.write', 'sale.sale.read']);
      expect(rpc.calls.any((c) => c.model == 'sale.line'), isFalse);
    });

    test('parallel saves are serialised (one write)', () async {
      final sale = loadedSale(root);
      await sale.fieldSetClient('name', 'X');
      final results = await Future.wait([sale.save(), sale.save()]);
      expect(results, [true, true]);
      expect(rpc.named('sale.sale.write'), hasLength(1));
    });

    test('conflict: ConcurrencyRunner decides (write anyway / cancel)',
        () async {
      var writes = 0;
      rpc.handlers['sale.sale.write'] = (c) {
        writes++;
        if (c.context.containsKey('_timestamp')) {
          throw const ConcurrencyException();
        }
        return null;
      };
      var choice = true;
      root.model.session.concurrencyRunner = (model, ids, action) async {
        expect(model, 'sale.sale');
        expect(ids, [1]);
        try {
          await action(true);
          return true;
        } on ConcurrencyException {
          if (!choice) return false;
          await action(false); // write anyway
          return true;
        }
      };
      final sale = loadedSale(root);
      await sale.fieldSetClient('name', 'X');
      expect(await sale.save(), isTrue);
      expect(writes, 2);
      expect(rpc.named('sale.sale.write').last.context.containsKey('_timestamp'),
          isFalse);

      choice = false;
      final group2 = RecordGroup(root.model);
      final other = loadedSale(group2);
      await other.fieldSetClient('name', 'Y');
      expect(await other.save(), isFalse);
      expect(other.modified, isTrue, reason: 'cancelled: changes kept');
    });

    test('without runner the ConcurrencyException reaches the caller',
        () async {
      rpc.handlers['sale.sale.write'] =
          (_) => throw const ConcurrencyException();
      final sale = loadedSale(root);
      await sale.fieldSetClient('name', 'X');
      expect(sale.save(), throwsA(isA<ConcurrencyException>()));
    });

    test('on_write: further ids are reloaded', () async {
      rpc.handlers['sale.sale.on_write_ids'] = (c) => [1, 2];
      root.onWrite = ['on_write_ids'];
      final sale = loadedSale(root);
      root.load([2], preloaded: {
        2: {'name': 'Zwei'}
      });
      await sale.fieldSetClient('name', 'X');
      await sale.save(forceReload: false);
      expect(rpc.names, ['sale.sale.write', 'sale.sale.on_write_ids']);
      expect(rpc.calls.last.params, [
        [1]
      ]);
      expect(root.get(2)!.loaded, isEmpty, reason: 'reset for reloading');
    });

    test('group: delete with _timestamp', () async {
      rpc.handlers['sale.sale.delete'] = (c) => null;
      final sale = loadedSale(root);
      root.remove(sale, remove: false, modified: false);
      expect(await root.save(), isTrue);
      final delete = rpc.named('sale.sale.delete').single;
      expect(delete.params, [
        [1]
      ]);
      expect(delete.context['_timestamp'], {'sale.sale,1': '100.0'});
      expect(root, isEmpty);
    });
  });

  group('default_get (D7)', () {
    test('default_<field> in the context, x2many defaults, parent field',
        () async {
      final rpc = FakeRpc({
        'sale.sale.default_get': (c) => {
              'state': 'draft',
              'party': 7,
              'party.': {'rec_name': 'Jan'},
              'lines': [
                {'quantity': 1.0}
              ],
            },
        'sale.line.default_get': (c) => {'quantity': 3.0},
      });
      final root = RecordGroup(saleModel(modelSession: fakeSession(rpc)));
      final sale =
          await root.newRecordWithDefaults(defaults: {'name': 'Vorgabe'});
      final call = rpc.calls.single;
      expect(call.params[0], containsAll(['name', 'state', 'lines']));
      expect(call.context['default_name'], 'Vorgabe');
      expect(sale.fieldGet('state'), 'draft');
      expect(sale.fieldGetClient('party'), 'Jan');
      expect(sale.modifiedFields, containsAll(['state', 'party', 'lines']));
      final lines = sale.fieldGetClient('lines') as RecordGroup;
      expect(lines.single.fieldGet('quantity'), 1.0);
      expect(lines.single.id, isNegative);

      final line = await lines.newRecordWithDefaults();
      expect(line.fieldGet('quantity'), 3.0);
      expect(line.fieldGet('sale'), sale.id, reason: 'parent field');
    });
  });

  group('on_change chain (D5, D6)', () {
    late FakeRpc rpc;
    late TrytonModel model;

    setUp(() {
      rpc = FakeRpc({
        'test.oc.on_change_party': (c) => {'name': 'Von Party'},
        'test.oc.on_change_with_total': (c) => {'total': 10.0},
        'test.oc.on_change_with_code': (c) => {'code': 'C'},
        'test.oc.on_change_with_tax': (c) => {'tax': 1.9},
        'test.oc.on_change_notify': (c) => [
              ['info', 'Hinweis']
            ],
        'test.oc.autocomplete_city': (c) => ['Berlin', 'Bonn'],
        'party.party.read': (c) => [
              {'id': 8, 'rec_name': 'Eva'}
            ],
      });
      final session = fakeSession(rpc)
        ..notificationFields = {
          'test.oc': ['party']
        };
      model = TrytonModel('test.oc', session: session)
        ..addFields({
          'party': fieldDesc('many2one', {
            'relation': 'party.party',
            'on_change': ['party', 'name'],
          }),
          'name': fieldDesc('char'),
          'total': fieldDesc('float', {
            'on_change_with': ['party']
          }),
          'code': fieldDesc('char', {
            'on_change_with': ['party']
          }),
          'tax': fieldDesc('float', {
            'on_change_with': ['party', 'total']
          }),
          'city': fieldDesc('char', {
            'autocomplete': ['party']
          }),
          'lines': fieldDesc('one2many', {
            'relation': 'test.ocline',
            'relation_field': 'parent',
            'views': {
              'tree': {
                'fields': {
                  'parent': fieldDesc('many2one', {'relation': 'test.oc'}),
                  'product': fieldDesc('many2one', {
                    'relation': 'product.product',
                    'on_change': [
                      'product',
                      '_parent_parent.party',
                      '_parent_parent.missing'
                    ],
                  }),
                }
              }
            },
          }),
        });
    });

    test('order: on_change, notify, on_change_with (+ later), autocomplete',
        () async {
      final group = RecordGroup(model);
      final notifications = <List<dynamic>>[];
      group.onNotify = notifications.add;
      final r = group.add(group.newRecord());
      await r.fieldSetClient('party', [8, 'Eva']);
      expect(rpc.names, [
        'test.oc.on_change_party',
        'test.oc.on_change_notify',
        'test.oc.on_change_with_total',
        'test.oc.on_change_with_code',
        'test.oc.on_change_with_tax',
        'test.oc.on_change_notify',
        'test.oc.autocomplete_city',
      ]);
      // Only the declared dependencies (+ id) are sent.
      expect(rpc.calls.first.params, [
        {'party': 8, 'name': '', 'id': r.id}
      ]);
      // Like Python: the values of one round are collected for all fields.
      expect(rpc.named('test.oc.on_change_with_total').single.params, [
        {'party': 8, 'total': null, 'code': ''}
      ]);
      // "later": tax sees the total computed in the first round.
      expect(rpc.named('test.oc.on_change_with_tax').single.params, [
        {'party': 8, 'total': 10.0, 'tax': null}
      ]);
      expect(r.fieldGet('name'), 'Von Party');
      expect((r.fieldGet('total'), r.fieldGet('code'), r.fieldGet('tax')),
          (10.0, 'C', 1.9));
      expect(r.modifiedFields,
          containsAll(['party', 'name', 'total', 'code', 'tax']));
      expect(r.autocompletion['city'], ['Berlin', 'Bonn']);
      expect(rpc.named('test.oc.autocomplete_city').single.processException,
          isFalse);
      expect(notifications, hasLength(2));
      expect(notifications.first, [
        ['info', 'Hinweis']
      ]);
    });

    test('on_change_with as one call when the dependencies contain id',
        () async {
      model.fields['total']!.description['on_change_with'] = ['party', 'id'];
      model.fields['code']!.description['on_change_with'] = ['party', 'id'];
      model.fields['tax']!.description.remove('on_change_with');
      rpc.handlers['test.oc.on_change_with'] =
          (c) => {'total': 5.0, 'code': 'X'};
      final group = RecordGroup(model);
      final r = group.add(group.newRecord());
      await r.fieldSetClient('party', [8, 'Eva']);
      final call = rpc.named('test.oc.on_change_with').single;
      expect(call.params[1], ['total', 'code']);
      expect((r.fieldGet('total'), r.fieldGet('code')), (5.0, 'X'));
    });

    test('the queue keeps the order of two changes', () async {
      final first = Completer<Map<String, dynamic>>();
      var calls = 0;
      rpc.handlers['test.oc.on_change_party'] = (c) {
        calls++;
        return calls == 1 ? first.future : {'name': 'Zweite'};
      };
      final group = RecordGroup(model);
      final r = group.add(group.newRecord());
      final a = r.fieldSetClient('party', [8, 'Eva']);
      final b = r.fieldSetClient('party', [9, 'Max']);
      await Future<void>.delayed(Duration.zero);
      expect(rpc.named('test.oc.on_change_party'), hasLength(1),
          reason: 'second chain waits for the first');
      first.complete({'name': 'Erste'});
      await Future.wait([a, b]);
      final partyCalls = rpc.named('test.oc.on_change_party');
      expect(partyCalls, hasLength(2));
      expect(partyCalls[1].params[0]['party'], 9);
      // The second chain started after the first chain had finished.
      expect(rpc.calls.indexOf(partyCalls[1]),
          greaterThan(rpc.calls.indexOf(rpc.named('test.oc.autocomplete_city').first)));
      expect(r.fieldGet('name'), 'Zweite');
    });

    test('errors are not swallowed: the future of setClient fails',
        () async {
      rpc.handlers['test.oc.on_change_party'] =
          (_) => throw const UserError('Nein');
      final group = RecordGroup(model);
      final r = group.add(group.newRecord());
      await expectLater(
          r.fieldSetClient('party', [8, 'Eva']), throwsA(isA<UserError>()));
      // The queue continues with the next change.
      rpc.handlers['test.oc.on_change_party'] = (_) => {'name': 'ok'};
      await r.fieldSetClient('party', [9, 'Max']);
      expect(r.fieldGet('name'), 'ok');
    });

    test('dependencies with _parent_ paths; missing paths are left out',
        () async {
      rpc.handlers['test.ocline.on_change_product'] = (c) => {};
      rpc.handlers['product.product.read'] = (c) => [
            {'id': 3, 'rec_name': 'P3'}
          ];
      final group = RecordGroup(model);
      final parent = group.add(group.newRecord());
      await parent.fieldSetClient('party', [8, 'Eva']);
      rpc.calls.clear();
      final lines = parent.fieldGetClient('lines') as RecordGroup;
      final line = lines.add(lines.newRecord());
      await line.idle;
      await line.fieldSetClient('product', [3, 'P3']);
      final call = rpc.named('test.ocline.on_change_product').single;
      expect(call.params, [
        {'product': 3, '_parent_parent.party': 8, 'id': line.id}
      ]);
    });
  });

  group('One2Many set_on_change (D4, D5)', () {
    test('add / update with unknown fields (fields_get)', () async {
      final rpc = FakeRpc({
        'test.so.on_change_party': (c) => {
              'lines': {
                'add': [
                  [
                    0,
                    {'product': 3, 'discount': 0.1}
                  ]
                ],
                'update': [
                  {'id': 10, 'discount': 0.2}
                ],
              }
            },
        'test.soline.fields_get': (c) => {
              'discount': {'type': 'float', 'string': 'Rabatt'}
            },
        'test.soline.read': (c) => [
              {'id': 10, 'discount': 0.0}
            ],
        'product.product.read': (c) => [
              {'id': 3, 'rec_name': 'P3'}
            ],
      });
      final model = TrytonModel('test.so', session: fakeSession(rpc))
        ..addFields({
          'party': fieldDesc('many2one', {
            'relation': 'party.party',
            'on_change': ['party']
          }),
          'lines': fieldDesc('one2many', {
            'relation': 'test.soline',
            'relation_field': 'parent',
            'views': {
              'tree': {
                'fields': {
                  'parent': fieldDesc('many2one', {'relation': 'test.so'}),
                  'product': fieldDesc('many2one', {'relation': 'product.product'}),
                }
              }
            },
          }),
        });
      final group = RecordGroup(model)..load([1]);
      final record = group.get(1)!
        ..set({
          'party': 7,
          'party.': {'rec_name': 'Jan'},
          'lines': [10],
          'lines.': [
            {
              'id': 10,
              'product': 4,
              'product.': {'rec_name': 'P4'}
            }
          ],
        }, modified: false);
      await record.fieldSetClient('party', [8, 'Eva']);
      await record.idle;
      final lines = record.fieldGetClient('lines') as RecordGroup;
      expect(rpc.named('test.soline.fields_get').single.params, [
        ['discount']
      ]);
      expect(lines.model.fields['discount'], isA<FloatField>());
      expect(lines.first.id, isNegative);
      expect(lines.first.fieldGet('discount'), 0.1);
      expect(lines.first.fieldGet('product'), 3);
      expect(lines.get(10)!.fieldGet('discount'), 0.2);
      expect(record.modifiedFields, contains('lines'));
      final commands = model.fields['lines']!.get(record) as List;
      expect(commands.first, ['add', [10]]);
      expect(commands[1][0], 'create');
    });
  });

  group('validation (D8)', () {
    late FakeRpc rpc;

    setUp(() {
      rpc = FakeRpc({
        'party.party.read': (c) => [
              {'id': 5, 'rec_name': 'Fünf'}
            ],
      });
    });

    test('a unique value from the screen domain is set (domain_readonly)',
        () async {
      final root = RecordGroup(saleModel(modelSession: fakeSession(rpc)));
      root.screenDomains.add([
        ['party', '=', 5],
        ['state', '=', 'draft'],
      ]);
      final sale = root.add(root.newRecord());
      expect(sale.validate(), isTrue);
      await sale.idle;
      expect(sale.fieldGet('party'), 5);
      expect(sale.fieldGet('state'), 'draft');
      final attrs = sale.model.fields['party']!.stateAttrs(sale);
      expect(attrs['domain_readonly'], isTrue);
      sale.validate();
      expect(sale.model.fields['party']!.stateAttrs(sale)['readonly'], isTrue);
      // rec_name of the forced id is read in the background.
      await Future<void>.delayed(Duration.zero);
      expect(sale.fieldGetClient('party'), 'Fünf');
      expect(rpc.named('party.party.read').single.processException, isFalse);
    });

    test('also invisible fields get unique values of their domain', () async {
      final model = TrytonModel('test.v', session: fakeSession(rpc))
        ..addFields({
          'code': fieldDesc('char', {
            'domain': jsonEncode([
              ['code', '=', 'A']
            ]),
            'states': jsonEncode({'invisible': true}),
          }),
          'visible_code': fieldDesc('char', {
            'domain': jsonEncode([
              ['visible_code', '=', 'B']
            ]),
          }),
        });
      final group = RecordGroup(model);
      final r = group.add(group.newRecord());
      r.validate();
      await r.idle;
      expect(r.fieldGet('code'), 'A');
      expect(r.fieldGet('visible_code'), '',
          reason: 'empty, optional, visible: left alone');
    });

    test('required, domain and children; invalidMessage max. 5', () async {
      final model = TrytonModel('test.v', session: fakeSession(rpc))
        ..addFields({
          'name': fieldDesc('char', {'required': true, 'string': 'Name'}),
          'code': fieldDesc('char', {
            'string': 'Code',
            'domain': jsonEncode([
              ['code', 'like', 'S%']
            ]),
          }),
          'lines': fieldDesc('one2many', {
            'relation': 'test.vline',
            'string': 'Zeilen',
            'views': {
              'tree': {
                'fields': {
                  'qty': fieldDesc('float', {'required': true}),
                }
              }
            },
          }),
        });
      final group = RecordGroup(model);
      final r = group.add(group.newRecord());
      await r.fieldSetClient('code', 'X');
      final lines = r.fieldGetClient('lines') as RecordGroup;
      lines.add(lines.newRecord());
      expect(r.validate(softValidation: true), isFalse,
          reason: 'domain and children');
      expect(r.invalidFields().containsKey('name'), isFalse);
      expect(r.validate(), isFalse);
      final invalid = r.invalidFields();
      expect(invalid['name'], 'required');
      expect(invalid['code'], [
        ['code', 'like', 'S%']
      ]);
      expect(invalid['lines'], 'children');
      expect(
          r.invalidMessage(),
          '"Code" is not valid according to its domain.\n'
          'The values of "Zeilen" are not valid.\n'
          '"Name" is required.');

      final many = TrytonModel('test.many', session: fakeSession(rpc))
        ..addFields({
          for (var i = 1; i <= 7; i++)
            'f$i': fieldDesc('char', {'required': true, 'string': 'F$i'}),
        });
      final g = RecordGroup(many);
      final m = g.add(g.newRecord());
      m.validate();
      final lines2 = m.invalidMessage().split('\n');
      expect(lines2, hasLength(6));
      expect(lines2.last, '...');
      // Translated texts from the UI
      expect(
          r.invalidMessage(const InvalidMessages(
              required: '„%s“ ist erforderlich.',
              domain: '„%s“ ist ungültig.',
              children: 'Werte von „%s“ ungültig.')),
          contains('„Name“ ist erforderlich.'));
    });

    test('dict keys: domains of the known keys', () async {
      final model = TrytonModel('test.d', session: fakeSession(rpc))
        ..addFields({'attrs': fieldDesc('dict', {'schema_model': 'test.key'})});
      final group = RecordGroup(model);
      final r = group.add(group.newRecord());
      final dict = model.fields['attrs'] as DictField;
      dict.keys['size'] = {
        'name': 'size',
        'domain': jsonEncode([
          ['size', '>', 0]
        ]),
      };
      await r.fieldSetClient('attrs', {'size': 0});
      expect(r.validate(), isFalse);
      expect(r.invalidFields()['attrs'], 'domain');
      await r.fieldSetClient('attrs', {'size': 3});
      expect(r.validate(), isTrue);
    });
  });

  group('pre_validate, resources (D10)', () {
    test('pre_validate sends the modified fields and id', () async {
      final rpc = FakeRpc({'sale.sale.pre_validate': (c) => null});
      final sale =
          loadedSale(RecordGroup(saleModel(modelSession: fakeSession(rpc))));
      await sale.preValidate();
      expect(rpc.calls, isEmpty, reason: 'nothing modified');
      await sale.fieldSetClient('name', 'X');
      await sale.preValidate();
      expect(rpc.calls.single.params, [
        {'name': 'X', 'id': 1}
      ]);
    });

    test('resources: cached, without error dialog', () async {
      final rpc = FakeRpc({
        'sale.sale.resources': (c) =>
            {'attachment_count': 2, 'note_count': 1, 'note_unread': 0},
      });
      final sale =
          loadedSale(RecordGroup(saleModel(modelSession: fakeSession(rpc))));
      expect((await sale.getResources())!['attachment_count'], 2);
      await sale.getResources();
      expect(rpc.calls, hasLength(1));
      expect(rpc.calls.single.params, [1]);
      expect(rpc.calls.single.processException, isFalse);
      await sale.getResources(reload: true);
      expect(rpc.calls, hasLength(2));
      expect(await RecordGroup(sale.model).newRecord().getResources(), isNull);
    });

    test('binary content is read on demand', () async {
      final rpc = FakeRpc({
        'test.b.read': (c) => [
              {
                'id': 1,
                'file': TrytonBytes([1, 2])
              }
            ],
      });
      final model = TrytonModel('test.b', session: fakeSession(rpc))
        ..addFields({'file': fieldDesc('binary')});
      final r = Record(model, id: 1)..set({'file': 2}, modified: false);
      final data = await (model.fields['file'] as BinaryField).getData(r);
      expect((data as TrytonBytes).bytes, [1, 2]);
      expect(rpc.calls.single.params, [
        [1],
        ['file']
      ]);
    });
  });
}

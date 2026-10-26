import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/serialization/tryton_serializer.dart';
import 'package:tryton_flutter_client/features/model/field_definition.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/model/selection_loader.dart';

FieldDefinition fd(String name, String type, [Map<String, dynamic>? extra]) =>
    FieldDefinition.fromJson(name, {'type': type, 'string': name, ...?extra});

class _FakeRpc extends RpcClient {
  _FakeRpc() : super(baseUrl: 'http://localhost');
  final calls = <(String, List<dynamic>)>[];
  @override
  Future<dynamic> call(String database, String method, List<dynamic> params,
      {bool reAuth = true}) async {
    calls.add((method, params));
    return [
      ['a', 'A']
    ];
  }
}

void main() {
  final fields = {
    'kind': fd('kind', 'selection', {
      'selection': 'get_kinds',
      'selection_change_with': ['type', 'party', 'id'],
    }),
    'static_dyn': fd('static_dyn', 'selection', {'selection': 'get_all'}),
    'fixed': fd('fixed', 'selection', {
      'selection': [
        ['x', 'X']
      ]
    }),
    'type': fd('type', 'char'),
    'party': fd('party', 'many2one', {'relation': 'party.party'}),
    'active': fd('active', 'boolean'),
  };

  group('FieldDefinition', () {
    test('parses selection_change_with and keeps it on copyWithSelection', () {
      final kind = fields['kind']!;
      expect(kind.selectionFunction, 'get_kinds');
      expect(kind.selectionChangeWith, ['type', 'party', 'id']);
      expect(
          kind.copyWithSelection([
            ['a', 'A']
          ]).selectionChangeWith,
          ['type', 'party', 'id']);
      expect(fields['static_dyn']!.selectionChangeWith, isNull);
    });
  });

  group('ModelService.getSelectionOptions', () {
    late _FakeRpc rpc;
    late ModelService svc;
    setUp(() {
      rpc = _FakeRpc();
      svc = ModelService(
          rpc: rpc,
          getContext: () => {'language': 'de'},
          getDatabase: () => 'tryton');
    });

    test('without values: (ctx) only', () async {
      await svc.getSelectionOptions('party.party', 'get_all');
      expect(rpc.calls.single.$1, 'model.party.party.get_all');
      expect(rpc.calls.single.$2, [
        {'language': 'de'}
      ]);
    });

    test('with values: (values, ctx)', () async {
      await svc.getSelectionOptions('party.party', 'get_kinds',
          values: {'type': 'b', 'party': 7});
      expect(rpc.calls.single.$2, [
        {'type': 'b', 'party': 7},
        {'language': 'de'}
      ]);
    });
  });

  group('SelectionLoader.changeWithValues', () {
    test('dependency values like on_change args: m2o as id, no id', () {
      final v = SelectionLoader.changeWithValues(fields['kind']!,
          {'type': 'b', 'party': [7, 'Jan'], 'id': 3, 'other': 1}, fields);
      expect(v, {'type': 'b', 'party': 7});
    });

    test('missing / false values become null (boolean stays false)', () {
      final withBool = fd('k', 'selection', {
        'selection': 'm',
        'selection_change_with': ['type', 'party', 'active'],
      });
      expect(
          SelectionLoader.changeWithValues(
              withBool, {'type': false, 'active': false}, fields),
          {'type': null, 'party': null, 'active': false});
    });

    test('no selection_change_with → null (call without values)', () {
      expect(
          SelectionLoader.changeWithValues(
              fields['static_dyn']!, {'type': 'b'}, fields),
          isNull);
    });

    test('dependsOn', () {
      expect(SelectionLoader.dependsOn(fields['kind']!, 'type'), isTrue);
      expect(SelectionLoader.dependsOn(fields['kind']!, 'active'), isFalse);
      expect(SelectionLoader.dependsOn(fields['static_dyn']!, 'type'), isFalse);
      expect(SelectionLoader.dependsOn(fields['fixed']!, 'type'), isFalse);
    });
  });

  group('SelectionLoader.load', () {
    late List<(String, Map<String, dynamic>?)> fetches;
    late SelectionLoader loader;
    var fail = false;

    setUp(() {
      fetches = [];
      fail = false;
      loader = SelectionLoader((method, values) async {
        fetches.add((method, values));
        if (fail) throw Exception('boom');
        return [
          [values?['type'] ?? 'all', 'Label ${values?['type']}']
        ];
      });
    });

    test('with change_with: values are passed, reload on change', () async {
      final a = await loader.load(fields['kind']!, {'type': 'a'}, fields);
      final b = await loader.load(fields['kind']!, {'type': 'b'}, fields);
      expect(a.single.first, 'a');
      expect(b.single.first, 'b');
      expect(fetches.map((f) => f.$1), ['get_kinds', 'get_kinds']);
      expect(fetches.map((f) => f.$2), [
        {'type': 'a', 'party': null},
        {'type': 'b', 'party': null},
      ]);
    });

    test('cache per value combination', () async {
      await loader.load(fields['kind']!, {'type': 'a'}, fields);
      await loader.load(fields['kind']!, {'type': 'b'}, fields);
      await loader.load(fields['kind']!, {'type': 'a', 'other': 9}, fields);
      await loader.load(fields['kind']!, {'type': 'b'}, fields);
      expect(fetches, hasLength(2));
    });

    test('m2o [id, name] and plain id share one cache entry', () async {
      await loader.load(fields['kind']!, {'party': [7, 'Jan']}, fields);
      await loader.load(fields['kind']!, {'party': 7}, fields);
      expect(fetches, hasLength(1));
    });

    test('Tryton types in values (date, Decimal) are cacheable', () async {
      final f = fd('k', 'selection', {
        'selection': 'm',
        'selection_change_with': ['d', 'n'],
      });
      final rec = {
        'd': const TrytonDate(2026, 10, 26),
        'n': const TrytonDecimal('1.50')
      };
      await loader.load(f, rec, fields);
      await loader.load(f, Map.of(rec), fields);
      expect(fetches, hasLength(1));
    });

    test('without change_with: called without values, loaded once', () async {
      await loader.load(fields['static_dyn']!, {'type': 'a'}, fields);
      await loader.load(fields['static_dyn']!, {'type': 'b'}, fields);
      expect(fetches, hasLength(1));
      expect(fetches.single.$1, 'get_all');
      expect(fetches.single.$2, isNull);
    });

    test('static selection list: no server call', () async {
      expect(await loader.load(fields['fixed']!, {}, fields), [
        ['x', 'X']
      ]);
      expect(fetches, isEmpty);
    });

    test('concurrent loads of the same key share one request', () async {
      await Future.wait([
        loader.load(fields['kind']!, {'type': 'a'}, fields),
        loader.load(fields['kind']!, {'type': 'a'}, fields),
      ]);
      expect(fetches, hasLength(1));
    });

    test('errors return [] and are not cached', () async {
      fail = true;
      expect(await loader.load(fields['kind']!, {'type': 'a'}, fields),
          isEmpty);
      fail = false;
      expect(await loader.load(fields['kind']!, {'type': 'a'}, fields),
          isNotEmpty);
      expect(fetches, hasLength(2));
    });
  });
}

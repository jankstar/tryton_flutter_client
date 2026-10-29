import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/model/metadata_service.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';

import '../views/form_harness.dart';

/// MetadataService (spec 4) with a fake RPC.
void main() {
  final models = [for (var i = 0; i < 250; i++) 'm$i'];

  ({FakeFormRpc rpc, MetadataService metadata}) setUpService(
      [Map<String, Object? Function(List<dynamic>)> extra = const {}]) {
    final rpc = FakeFormRpc({
      'model.ir.model.list_models': (_) => models,
      'model.ir.model.access.get_access': (p) => {
            for (final m in p[0] as List)
              m: {
                'read': 1,
                'write': m == 'm120' ? 0 : 1,
                'create': m == 'm120' ? 0 : 1,
                'delete': 0,
              }
          },
      ...extra,
    });
    final svc = ModelService(
        rpc: rpc, getContext: () => const {}, getDatabase: () => 'test');
    return (rpc: rpc, metadata: MetadataService(svc));
  }

  test('access: batch of 100 models around the model, 0/1 as bool', () async {
    final (:rpc, :metadata) = setUpService();
    expect(metadata.accessOf('m120'), isNull);
    final access = await metadata.access('m120');
    expect(rpc.named('model.ir.model.list_models'), hasLength(1));
    final batch = rpc.named('model.ir.model.access.get_access').single.params[0]
        as List;
    expect(batch, hasLength(100));
    expect(batch.first, 'm70');
    expect(batch.last, 'm169');
    expect((access.read, access.write, access.create, access.delete),
        (true, false, false, false));

    // Neighbours are known now: no further call.
    expect(metadata.accessOf('m100')!.write, isTrue);
    await metadata.access('m150');
    expect(rpc.named('model.ir.model.access.get_access'), hasLength(1));

    // At the start of the list the batch is shorter.
    await metadata.access('m5');
    final second = rpc.named('model.ir.model.access.get_access').last.params[0]
        as List;
    expect(second.first, 'm0');
    expect(second, hasLength(55));
  });

  test('access: error → read only; unknown model reloads the list',
      () async {
    final (:rpc, :metadata) = setUpService({
      'model.ir.model.access.get_access': (_) => throw StateError('denied'),
    });
    final access = await metadata.access('m3');
    expect((access.read, access.write, access.create, access.delete),
        (true, false, false, false));

    await metadata.access('not.listed').catchError((_) => access);
    expect(rpc.named('model.ir.model.list_models'), hasLength(2),
        reason: 'list loaded again for an unknown model');
  });

  test('history, names, notification and searches; clear', () async {
    final (:rpc, :metadata) = setUpService({
      'model.ir.model.list_history': (_) => ['party.party'],
      'model.ir.model.get_names': (_) => {'party.party': 'Partei'},
      'model.ir.model.get_notification': (_) => {
            'sale.sale': ['party']
          },
      'model.ir.ui.view_search.get': (_) => {
            'party.party': [
              [1, 'Mine', '[]', true]
            ]
          },
    });
    await metadata.load();
    expect(metadata.hasHistory('party.party'), isTrue);
    expect(metadata.hasHistory('sale.sale'), isFalse);
    expect(metadata.notificationFields, {
      'sale.sale': ['party']
    });
    expect(metadata.searches('party.party'), hasLength(1));
    expect(await metadata.name('party.party'), 'Partei');
    await metadata.name('sale.sale');
    expect(rpc.named('model.ir.model.get_names'), hasLength(1),
        reason: 'names loaded once');
    metadata.clearNames();
    await metadata.name('party.party');
    expect(rpc.named('model.ir.model.get_names'), hasLength(2),
        reason: 'reloaded after a language change');

    await metadata.access('m1');
    metadata.clear();
    expect(metadata.accessOf('m1'), isNull);
    expect(metadata.hasHistory('party.party'), isFalse);
    expect(metadata.notificationFields, isNull);
  });
}

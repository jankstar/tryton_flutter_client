import '../../core/model/model.dart';
import 'concurrency.dart';
import 'model_service.dart';

/// [ModelRpc] of the data layer over the [ModelService] (session context
/// merged, `processException` passed on).
class ModelServiceRpc implements ModelRpc {
  final ModelService service;
  const ModelServiceRpc(this.service);

  @override
  Future<dynamic> execute(String model, String method, List<dynamic> params,
          {Map<String, dynamic>? context, bool processException = true}) =>
      service.execute<dynamic>(model, method, params,
          context: context, processException: processException);
}

/// [ConcurrencyRunner] with the A1 dialog flow (`runWithConcurrencyCheck`):
/// [ask] the user, [onCompare] opens the server version of
/// `model`/`id`, [onMessage] for several records.
ConcurrencyRunner concurrencyRunner({
  required Future<ConcurrencyChoice> Function() ask,
  required Future<void> Function(String model, int id) onCompare,
  required Future<void> Function() onMessage,
}) =>
    (model, ids, action) => runWithConcurrencyCheck(
          idCount: ids.length,
          action: action,
          ask: ask,
          onCompare: () => onCompare(model, ids.first),
          onMessage: onMessage,
        );

/// A [ModelSession] on the [ModelService] (session context of the
/// service).
ModelSession modelSessionFor(ModelService service,
        {ConcurrencyRunner? concurrencyRunner}) =>
    ModelSession(
      rpc: ModelServiceRpc(service),
      context: service.sessionContext,
      concurrencyRunner: concurrencyRunner,
    );

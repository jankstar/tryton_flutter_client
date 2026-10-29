import '../../core/model/model.dart';
import '../../core/rpc/error_processing.dart';
import 'concurrency.dart';
import 'model_service.dart';

/// [ModelRpc] of the data layer over the [ModelService] (session context
/// merged). With `processException` an error goes through [processor]
/// (e.g. the `ErrorHandler` of a form: dialog, then `HandledRpcError`),
/// otherwise through the service's own `errorProcessor`.
class ModelServiceRpc implements ModelRpc {
  final ModelService service;
  final RpcErrorProcessor? processor;
  const ModelServiceRpc(this.service, {this.processor});

  @override
  Future<dynamic> execute(String model, String method, List<dynamic> params,
      {Map<String, dynamic>? context, bool processException = true}) {
    final p = processor;
    if (processException && p != null) {
      return p.process(() => service.execute<dynamic>(model, method, params,
          context: context, processException: false));
    }
    return service.execute<dynamic>(model, method, params,
        context: context, processException: processException);
  }
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
        {ConcurrencyRunner? concurrencyRunner,
        RpcErrorProcessor? processor}) =>
    ModelSession(
      rpc: ModelServiceRpc(service, processor: processor),
      context: service.sessionContext,
      concurrencyRunner: concurrencyRunner,
      // Metadata of the session (spec 4): access rights, notification
      // fields.
      accessOf: service.metadata?.accessOf,
      loadAccess: service.metadata?.ensureAccess,
      notificationFields: service.metadata?.notificationFields,
    );

import 'package:tryton_flutter_client/core/model/model.dart';

/// One recorded `model.<model>.<method>` call.
class RpcCall {
  final String model;
  final String method;
  final List<dynamic> params;
  final Map<String, dynamic> context;
  final bool processException;

  RpcCall(this.model, this.method, this.params, this.context,
      this.processException);

  String get name => '$model.$method';

  @override
  String toString() => '$name$params';
}

/// [ModelRpc] fake: records the calls and answers with [handlers] (key
/// `'model.method'` or `'method'`). Unknown calls fail the test.
class FakeRpc implements ModelRpc {
  final List<RpcCall> calls = [];
  final Map<String, Object? Function(RpcCall call)> handlers;

  FakeRpc([Map<String, Object? Function(RpcCall call)>? handlers])
      : handlers = handlers ?? {};

  /// Calls of [name] (`'model.method'`).
  List<RpcCall> named(String name) =>
      [for (final c in calls) if (c.name == name) c];

  List<String> get names => [for (final c in calls) c.name];

  @override
  Future<dynamic> execute(String model, String method, List<dynamic> params,
      {Map<String, dynamic>? context, bool processException = true}) async {
    final call =
        RpcCall(model, method, params, {...?context}, processException);
    calls.add(call);
    final handler = handlers['$model.$method'] ?? handlers[method];
    if (handler == null) {
      throw StateError('unexpected call ${call.name}');
    }
    final result = handler(call);
    return result is Future ? await result : result;
  }
}

/// A session on [rpc] without notification fields (no
/// `ir.model.get_notification` call).
ModelSession fakeSession(FakeRpc rpc,
        {Map<String, dynamic> context = const {'language': 'de'},
        int limit = 1000}) =>
    ModelSession(
      rpc: rpc,
      context: () => context,
      notificationFields: const {},
      limit: limit,
    );

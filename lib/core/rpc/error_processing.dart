/// Central processing of RPC errors (SAO `process_exception`).
///
/// A processor shows the error to the user (dialogs) and may repeat the
/// call (UserWarning → `res.user.warning.skip`). If the call still fails
/// it throws a [HandledRpcError] so the caller knows the user has already
/// seen the message.
abstract interface class RpcErrorProcessor {
  Future<T> process<T>(Future<T> Function() call);
}

/// An error that a [RpcErrorProcessor] has already shown; [error] is the
/// original exception. Error handlers must not show it again.
class HandledRpcError implements Exception {
  final Object error;
  const HandledRpcError(this.error);

  @override
  String toString() => 'HandledRpcError($error)';
}

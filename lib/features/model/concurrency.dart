import '../../core/rpc/rpc_exceptions.dart';

/// User's answer to the concurrency dialog (spec 01-rpc-session.md 2.6).
enum ConcurrencyChoice { cancel, compare, writeAnyway }

/// Runs a `write`/`delete` with `_timestamp` and resolves a
/// [ConcurrencyException] like SAO's `Sao.rpc` + `ConcurrencyDialog`:
///
/// * exactly one record ([idCount] == 1): [ask] the user –
///   * [ConcurrencyChoice.writeAnyway] → repeat [action] without timestamp,
///   * [ConcurrencyChoice.compare] → [onCompare] (open server version), abort,
///   * [ConcurrencyChoice.cancel] → abort;
/// * otherwise: [onMessage] ("Concurrency Exception") and abort.
///
/// [action] receives `withTimestamp`. Returns true if the call succeeded.
Future<bool> runWithConcurrencyCheck({
  required int idCount,
  required Future<void> Function(bool withTimestamp) action,
  required Future<ConcurrencyChoice> Function() ask,
  required Future<void> Function() onCompare,
  required Future<void> Function() onMessage,
}) async {
  try {
    await action(true);
    return true;
  } on ConcurrencyException {
    if (idCount != 1) {
      await onMessage();
      return false;
    }
    switch (await ask()) {
      case ConcurrencyChoice.writeAnyway:
        await action(false);
        return true;
      case ConcurrencyChoice.compare:
        await onCompare();
        return false;
      case ConcurrencyChoice.cancel:
        return false;
    }
  }
}

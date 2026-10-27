import '../../core/rpc/rpc_exceptions.dart';

/// Answer to the UserWarning dialog (spec 2.6).
enum WarningChoice { cancel, ok, always }

/// Shows the dialogs of the central error handling. Implemented with real
/// dialogs in `error_dialogs.dart`, faked in tests.
abstract class ErrorPresenter {
  /// UserError: warning with title = message, text = description.
  Future<void> userError(String message, String description);

  /// UserWarning: "Always ignore" / "OK" / "Cancel".
  Future<WarningChoice> userWarning(String message, String description);

  /// Any other server exception: "Application Error" with expandable
  /// details (traceback).
  Future<void> applicationError(String title, String details);

  /// HTTP error with [code], or network error when [code] is null.
  Future<void> httpError(int? code, String text);

  /// ConcurrencyException that was not resolved by the caller (A1).
  Future<void> concurrency();
}

/// Central error handling for RPC calls from the UI (spec 2.6, task B6).
///
/// [run] executes an action; errors are shown via [presenter]. A
/// [UserWarning] asks the user; on OK/Always `res.user.warning.skip(name,
/// always)` is called and the action is repeated.
class ErrorHandler {
  final ErrorPresenter presenter;

  /// Calls `model.res.user.warning.skip(name, always, ctx)`.
  final Future<void> Function(String name, bool always) skipWarning;

  const ErrorHandler({required this.presenter, required this.skipWarning});

  /// Runs [action]. Returns true on success, false when it failed (the error
  /// was shown) or the user cancelled a warning.
  Future<bool> run(Future<void> Function() action) async {
    while (true) {
      try {
        await action();
        return true;
      } on UserWarning catch (w) {
        final choice = await presenter.userWarning(w.message, w.description);
        if (choice == WarningChoice.cancel) return false;
        try {
          await skipWarning(w.name, choice == WarningChoice.always);
        } catch (e) {
          await show(e);
          return false;
        }
        // Repeat the original call.
      } catch (e) {
        await show(e);
        return false;
      }
    }
  }

  /// Shows the dialog matching [error].
  Future<void> show(Object error) {
    return switch (error) {
      UserError(:final message, :final description) =>
        presenter.userError(message, description),
      UserWarning(:final message, :final description) =>
        presenter.userError(message, description),
      ConcurrencyException() => presenter.concurrency(),
      LoginException(:final message) => presenter.userError(message, ''),
      RpcHttpException(:final statusCode) =>
        presenter.httpError(statusCode, httpReason(statusCode)),
      RpcNetworkException(:final message) => presenter.httpError(null, message),
      // [str(exception), traceback]
      RpcServerException(:final errorType, :final message) =>
        presenter.applicationError(errorType, message),
      TrytonException(:final message) =>
        presenter.applicationError(message, error.toString()),
      _ => presenter.applicationError(error.toString(), ''),
    };
  }

  /// Short one-line text, e.g. for an error placeholder in a page.
  static String describe(Object error) => switch (error) {
        UserError(:final message) => message,
        RpcHttpException(:final statusCode) =>
          '[$statusCode] ${httpReason(statusCode)}'.trim(),
        RpcServerException(:final errorType) => errorType,
        TrytonException(:final message) => message,
        _ => error.toString(),
      };

  /// HTTP reason phrase for the common status codes.
  static String httpReason(int code) => switch (code) {
        400 => 'Bad Request',
        401 => 'Unauthorized',
        403 => 'Forbidden',
        404 => 'Not Found',
        429 => 'Too Many Requests',
        500 => 'Internal Server Error',
        502 => 'Bad Gateway',
        503 => 'Service Unavailable',
        504 => 'Gateway Timeout',
        _ => '',
      };
}

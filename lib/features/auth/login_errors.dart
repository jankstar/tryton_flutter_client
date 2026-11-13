import '../../core/rpc/rpc_exceptions.dart';
import '../../l10n/app_localizations.dart';

// Messages of a failed login or password reset in the language of the
// login screen (Python `common.Login`, SAO `Session.do_login`) instead of
// the exception text.

/// The error code of a failed login or password reset for
/// [localizeLoginError] (Python `common.Login`, SAO `Session.do_login`):
/// `login_failed` (401: wrong user name or password), `forbidden` (403,
/// e.g. no password authentication for the reset),
/// `too_many_requests` (429), `database_not_found` (404),
/// `http_error:<code>:<text>`, `network_error:<text>`; other errors their
/// text.
String loginErrorCode(Object error) {
  if (error is RpcHttpException) {
    return switch (error.statusCode) {
      401 => 'login_failed',
      403 => 'forbidden',
      429 => 'too_many_requests',
      404 => 'database_not_found',
      _ => 'http_error:${error.statusCode}:${error.message}',
    };
  }
  if (error is RpcNetworkException) return 'network_error:${error.message}';
  if (error is TrytonException) return error.message;
  return error.toString();
}

/// The message of the error [code] ([loginErrorCode], also
/// `version_mismatch:<server>:<client>`).
String localizeLoginError(String code, AppLocalizations l) {
  final parts = code.split(':');
  switch (parts.first) {
    case 'login_failed':
      return l.loginFailed;
    case 'forbidden':
      return l.serverForbidden;
    case 'too_many_requests':
      return l.tooManyRequests;
    case 'database_not_found':
      return l.databaseNotFound;
    case 'version_mismatch' when parts.length == 3:
      return l.versionMismatch(parts[1], parts[2]);
    case 'http_error' when parts.length >= 3 && int.tryParse(parts[1]) != null:
      return l.httpError(int.parse(parts[1]), parts.sublist(2).join(':'));
    case 'network_error':
      return l.networkError(parts.sublist(1).join(':'));
  }
  return code;
}

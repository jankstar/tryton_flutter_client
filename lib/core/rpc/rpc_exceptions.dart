/// Base class for all Tryton RPC errors
abstract class TrytonException implements Exception {
  final String message;
  const TrytonException(this.message);
  @override
  String toString() => '$runtimeType: $message';
}

class UserError extends TrytonException {
  final String description;
  /// Domain the record violated (`error[1][2][0]`), or null.
  final List<dynamic>? domain;
  /// Field definitions for [domain] (`error[1][2][1]`), needed by the
  /// DomainParser (C4) to render the domain as text.
  final Map<String, dynamic>? domainFields;
  const UserError(super.message,
      {this.description = '', this.domain, this.domainFields});
}

class UserWarning extends TrytonException {
  final String name;
  final String description;
  const UserWarning(this.name, super.message, {this.description = ''});
}

/// Optimistic locking conflict: the record was modified on the server since
/// it was read (`_timestamp` mismatch). The payload is a plain string, e.g.
/// `["ConcurrencyException", "Records were modified in the meanwhile"]`.
class ConcurrencyException extends TrytonException {
  const ConcurrencyException(
      [super.message = 'Records were modified in the meanwhile']);
}

/// Server expects additional login parameters (MFA, password reset)
class LoginException extends TrytonException {
  final String fieldName;
  final String fieldType;
  const LoginException(this.fieldName, super.message, {this.fieldType = 'char'});
}

/// HTTP 5xx or network error after all retries
class RpcNetworkException extends TrytonException {
  const RpcNetworkException(super.message);
}

/// HTTP status other than 200 (e.g. 403 with an HTML body for a method
/// that is not exposed, or 503 after all retries).
class RpcHttpException extends RpcNetworkException {
  final int statusCode;
  const RpcHttpException(this.statusCode, super.message);
}

/// HTTP 200, but the body is not a JSON-RPC response.
class RpcProtocolException extends TrytonException {
  const RpcProtocolException(super.message);
}

/// Server version does not match the client's supported version
class VersionMismatchException extends TrytonException {
  final String serverVersion;
  final String clientVersion;
  const VersionMismatchException(this.serverVersion, this.clientVersion)
      : super(
            'Server version $serverVersion is not compatible with client version $clientVersion');
}

/// Unknown error type from the server
class RpcServerException extends TrytonException {
  final String errorType;
  const RpcServerException(this.errorType, super.message);
}

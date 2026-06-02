/// Base class for all Tryton RPC errors
abstract class TrytonException implements Exception {
  final String message;
  const TrytonException(this.message);
  @override
  String toString() => '$runtimeType: $message';
}

class UserError extends TrytonException {
  final String description;
  final Map<String, dynamic>? domain;
  const UserError(super.message, {this.description = '', this.domain});
}

class UserWarning extends TrytonException {
  final String name;
  final String description;
  const UserWarning(this.name, super.message, {this.description = ''});
}

/// Optimistic locking conflict – client must retry without _timestamp
class ConcurrencyException extends TrytonException {
  const ConcurrencyException() : super('Concurrent modification detected');
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

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../serialization/tryton_serializer.dart';
import 'reauth_service.dart';
import 'rpc_exceptions.dart';

/// Credentials of a logged-in session: `common.db.login` returns
/// `[user_id, token, bus_url_host]` (spec 2.5.1).
class SessionAuth {
  final String login;
  final int userId;
  final String token;
  const SessionAuth(this.login, this.userId, this.token);

  /// `Authorization: Session base64(login:user_id:token)` (spec 2.5.2).
  String get header =>
      'Session ${base64.encode(utf8.encode('$login:$userId:$token'))}';
}

class RpcClient {
  final Dio _dio;
  String _baseUrl;
  int _requestId = 0;

  /// Session sent as `Authorization` header on every request; null = none.
  SessionAuth? auth;

  /// Waits before a 503 retry; replaceable in tests.
  final Future<void> Function(Duration) _sleep;

  /// HTTP 503: at most this many attempts in total (like SAO).
  static const max503Attempts = 5;

  RpcClient({
    required String baseUrl,
    @visibleForTesting Dio? dio,
    @visibleForTesting Future<void> Function(Duration)? sleep,
  })  : _baseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
        _sleep = sleep ?? Future.delayed,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 60),
              headers: {'Content-Type': 'application/json'},
            ));

  Options get _options => Options(
        responseType: ResponseType.plain,
        headers: {
          'Content-Type': 'application/json',
          if (auth != null) 'Authorization': auth!.header,
        },
      );

  String get baseUrl => _baseUrl;

  set baseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url : '$url/';
  }

  /// Sends a request to `{database}/rpc/` (JSON-RPC 1.0 style: `id`,
  /// `method`, `params` only).
  ///
  /// HTTP 503 is retried up to [max503Attempts] attempts in total, waiting
  /// [retryDelay]; HTTP 401 triggers one re-login and retry unless [reAuth]
  /// is false (login itself, session check on start, logout).
  Future<dynamic> call(
    String database,
    String method,
    List<dynamic> params, {
    bool reAuth = true,
  }) async {
    final id = ++_requestId;
    final url = '$_baseUrl${Uri.encodeComponent(database)}/rpc/';

    final body = jsonEncode({
      'id': id,
      'method': method,
      'params': TrytonSerializer.encodeList(params),
    });

    var attempts503 = 0;
    var reAuthed = false;
    while (true) {
      try {
        final response = await _dio.post<String>(
          url,
          data: body,
          options: _options,
        );
        return _handleResponse(response);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 503 && ++attempts503 < max503Attempts) {
          await _sleep(retryDelay(
              e.response?.headers.value('retry-after'), attempts503));
          continue;
        }
        if (status == 401 && reAuth && !reAuthed) {
          reAuthed = true;
          // Session expired – like SAO's Session.renew:
          // ask the UI to show the re-login dialog and wait.
          try {
            await ReAuthService.requestReAuth();
            // Re-auth successful → retry the request once
            continue;
          } catch (_) {
            throw const RpcHttpException(
                401, 'Authentication required (401) – please log in again.');
          }
        }
        throw _networkError(e);
      }
    }
  }

  /// Wait time before retry number [retry] (1-based) after HTTP 503:
  /// `Retry-After` in seconds, otherwise [retry] seconds; at most 10 s.
  @visibleForTesting
  static Duration retryDelay(String? retryAfter, int retry) {
    final seconds = int.tryParse(retryAfter?.trim() ?? '') ?? retry;
    return Duration(seconds: seconds.clamp(0, 10));
  }

  /// Calls `common.server.version` at the server level (no database needed).
  /// Mirrors SAO's `Sao.Session.server_version()` which posts to `rpc/`.
  Future<String> serverVersion() async {
    final result = await _callServer('common.server.version');
    return result?.toString() ?? '';
  }

  /// Calls `common.db.list` at `/rpc/` – the method only exists there, not
  /// under `<db>/rpc/` (that answers 401). HTTP 403 means the list is
  /// disabled on the server (`[database] list = False`) → empty list, the
  /// login screen then shows a free-text field.
  Future<List<String>> listDatabases() async {
    try {
      final result = await _callServer('common.db.list');
      return result is List ? result.map((e) => e.toString()).toList() : [];
    } on RpcHttpException catch (e) {
      if (e.statusCode == 403) return [];
      rethrow;
    }
  }

  /// POST to the database-independent endpoint `/rpc/` (spec 2.1).
  Future<dynamic> _callServer(String method) async {
    final url = '${_baseUrl}rpc/';
    final body = jsonEncode({
      'id': ++_requestId,
      'method': method,
      'params': [],
    });
    try {
      final response = await _dio.post<String>(
        url,
        data: body,
        options: _options,
      );
      return _handleResponse(response);
    } on DioException catch (e) {
      throw _networkError(e);
    }
  }

  /// HTTP status → [RpcHttpException]; connection problems →
  /// [RpcNetworkException].
  static RpcNetworkException _networkError(DioException e) {
    final status = e.response?.statusCode;
    return status != null
        ? RpcHttpException(status, _friendlyError(e))
        : RpcNetworkException(_friendlyError(e));
  }

  /// Converts a DioException to a short, user-readable message.
  static String _friendlyError(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) {
      switch (status) {
        case 401: return 'Authentication required (401) – please log in again.';
        case 403: return 'Access denied (403).';
        case 404: return 'Server endpoint not found (404) – check the URL.';
        case 500: return 'Server error (500).';
        case 503: return 'Server unavailable (503) – please try again later.';
        default:  return 'HTTP error $status.';
      }
    }
    // Connection-level errors (timeout, no route, etc.)
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timed out – check the server URL.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Cannot connect to server – check the URL and network.';
    }
    return e.message ?? 'Network error.';
  }

  dynamic _handleResponse(Response<String> response) {
    // Some endpoints (e.g. logout) return null or an empty body.
    final body = response.data;
    if (body == null || body.isEmpty) return null;

    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      // Not JSON, e.g. an HTML error page. Never return null silently.
      final status = response.statusCode ?? 0;
      if (status != 200) {
        throw RpcHttpException(status, 'HTTP error $status.');
      }
      throw const RpcProtocolException('Invalid response: not JSON.');
    }
    // Tryton wraps results in {id, result, error}.
    // Some endpoints return bare null / true / false.
    if (decoded is! Map<String, dynamic>) return decoded;

    final data = decoded;
    final error = data['error'];
    if (error != null) {
      _throwRpcError(error);
    }
    return TrytonSerializer.decode(data['result']);
  }

  Never _throwRpcError(dynamic error) => throw exceptionFromError(error);

  /// Maps the `error` member of a response to a [TrytonException].
  @visibleForTesting
  static TrytonException exceptionFromError(dynamic error) {
    // error is a list: [type, payload]
    if (error is! List || error.isEmpty) {
      return RpcServerException('unknown', error.toString());
    }
    final type = error[0] as String;
    final payload = error.length > 1 ? error[1] : null;

    switch (type) {
      case 'UserError':
        final parts = payload is List ? payload : [payload, '', null];
        // domain is `[domain, fields]` or null.
        final domainInfo = parts.length > 2 ? parts[2] : null;
        final hasDomain = domainInfo is List && domainInfo.isNotEmpty;
        return UserError(
          parts[0]?.toString() ?? '',
          description: parts.length > 1 ? parts[1]?.toString() ?? '' : '',
          domain: hasDomain && domainInfo[0] is List
              ? List<dynamic>.from(domainInfo[0] as List)
              : null,
          domainFields: hasDomain &&
                  domainInfo.length > 1 &&
                  domainInfo[1] is Map
              ? Map<String, dynamic>.from(domainInfo[1] as Map)
              : null,
        );
      case 'UserWarning':
        final parts = payload is List ? payload : [payload, payload, ''];
        return UserWarning(
          parts[0]?.toString() ?? '',
          parts[1]?.toString() ?? '',
          description: parts.length > 2 ? parts[2]?.toString() ?? '' : '',
        );
      case 'ConcurrencyException':
        return payload is String && payload.isNotEmpty
            ? ConcurrencyException(payload)
            : const ConcurrencyException();
      case 'LoginException':
        final parts = payload is List ? payload : [payload, payload, 'char'];
        return LoginException(
          parts[0]?.toString() ?? '',
          parts[1]?.toString() ?? '',
          fieldType: parts.length > 2 ? parts[2]?.toString() ?? 'char' : 'char',
        );
      default:
        return RpcServerException(type, payload?.toString() ?? '');
    }
  }

}

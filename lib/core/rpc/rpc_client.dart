import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../serialization/tryton_serializer.dart';
import 'reauth_service.dart';
import 'rpc_exceptions.dart';

class RpcClient {
  final Dio _dio;
  final CookieJar _cookieJar;
  String _baseUrl;
  int _requestId = 0;

  RpcClient({required String baseUrl})
      : _baseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
        _cookieJar = CookieJar(),
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          headers: {'Content-Type': 'application/json'},
        )) {
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  String get baseUrl => _baseUrl;

  set baseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url : '$url/';
  }

  /// Sends a JSON-RPC 2.0 request to `{database}/rpc/`
  Future<dynamic> call(
    String database,
    String method,
    List<dynamic> params, {
    int maxRetries = 5,
  }) async {
    final id = ++_requestId;
    final url = '$_baseUrl$database/rpc/';

    final body = jsonEncode({
      'id': id,
      'method': method,
      'params': TrytonSerializer.encodeList(params),
    });

    // Allow one extra pass for re-auth retry (attempt == maxRetries + 1)
    for (var attempt = 0; attempt <= maxRetries + 1; attempt++) {
      try {
        final response = await _dio.post<String>(
          url,
          data: body,
          options: Options(responseType: ResponseType.plain),
        );
        return _handleResponse(response);
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status == 503 && attempt < maxRetries) {
          final retryAfter = _parseRetryAfter(e.response?.headers);
          await Future.delayed(retryAfter);
          continue;
        }
        if (status == 401 && attempt == 0) {
          // Session expired – like SAO's Session.renew:
          // ask the UI to show the re-login dialog and wait.
          try {
            await ReAuthService.requestReAuth();
            // Re-auth successful → retry the request once
            continue;
          } catch (_) {
            throw RpcNetworkException(
                'Authentication required (401) – please log in again.');
          }
        }
        throw RpcNetworkException(_friendlyError(e));
      }
    }
    throw const RpcNetworkException('Max retries exceeded');
  }

  /// Calls `common.server.version` at the server level (no database needed).
  /// Mirrors SAO's `Sao.Session.server_version()` which posts to `rpc/`.
  Future<String> serverVersion() async {
    final url = '${_baseUrl}rpc/';
    final body = jsonEncode({
      'id': ++_requestId,
      'method': 'common.server.version',
      'params': [],
    });
    try {
      final response = await _dio.post<String>(
        url,
        data: body,
        options: Options(responseType: ResponseType.plain),
      );
      final result = _handleResponse(response);
      return result?.toString() ?? '';
    } on DioException catch (e) {
      throw RpcNetworkException(_friendlyError(e));
    }
  }

  /// POST to `{database}/session/{endpoint}` (login, logout)
  Future<dynamic> sessionPost(
    String database,
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final url = '$_baseUrl$database/session/$endpoint';
    try {
      final response = await _dio.post<String>(
        url,
        data: jsonEncode(body),
        options: Options(responseType: ResponseType.plain),
      );
      return _handleResponse(response);
    } on DioException catch (e) {
      throw RpcNetworkException(_friendlyError(e));
    }
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

    // Some Tryton endpoints (e.g. res.user avatar) return binary data
    // as the raw HTTP body instead of a JSON-RPC response.
    // Detect this by checking whether the body looks like JSON.
    if (body.isNotEmpty && body[0] != '{' && body[0] != '[' &&
        body[0] != '"' && body[0] != 'n' && body[0] != 't' && body[0] != 'f') {
      // Not JSON (likely binary/base64 image data) – return null safely
      return null;
    }

    final decoded = jsonDecode(body);
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

  Never _throwRpcError(dynamic error) {
    // error is a list: [type, payload]
    if (error is! List || error.isEmpty) {
      throw RpcServerException('unknown', error.toString());
    }
    final type = error[0] as String;
    final payload = error.length > 1 ? error[1] : null;

    switch (type) {
      case 'UserError':
        final parts = payload is List ? payload : [payload, '', null];
        throw UserError(
          parts[0]?.toString() ?? '',
          description: parts.length > 1 ? parts[1]?.toString() ?? '' : '',
          domain: parts.length > 2 && parts[2] is Map
              ? Map<String, dynamic>.from(parts[2] as Map)
              : null,
        );
      case 'UserWarning':
        final parts = payload is List ? payload : [payload, payload, ''];
        throw UserWarning(
          parts[0]?.toString() ?? '',
          parts[1]?.toString() ?? '',
          description: parts.length > 2 ? parts[2]?.toString() ?? '' : '',
        );
      case 'ConcurrencyException':
        throw const ConcurrencyException();
      case 'LoginException':
        final parts = payload is List ? payload : [payload, payload, 'char'];
        throw LoginException(
          parts[0]?.toString() ?? '',
          parts[1]?.toString() ?? '',
          fieldType: parts.length > 2 ? parts[2]?.toString() ?? 'char' : 'char',
        );
      default:
        throw RpcServerException(type, payload?.toString() ?? '');
    }
  }

  Duration _parseRetryAfter(Headers? headers) {
    final value = headers?.value('retry-after');
    if (value != null) {
      final seconds = int.tryParse(value);
      if (seconds != null) return Duration(seconds: seconds.clamp(1, 60));
    }
    return const Duration(seconds: 10);
  }

  Future<void> clearCookies() => _cookieJar.deleteAll();
}

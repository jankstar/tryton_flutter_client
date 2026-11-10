import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../serialization/tryton_serializer.dart';
import 'rpc_client.dart';

/// Called with the `message` of a bus answer.
typedef BusCallback = void Function(Map<String, dynamic> message);

/// Long polling of the Tryton bus (spec 2.10, Python `tryton/bus.py`, SAO
/// `bus.js`): `POST <bus_url_host>/<db>/bus` with `{last_message,
/// channels}` and the session header, answered after a message or the
/// server timeout; `last_message` is kept and the next poll starts at
/// once. Errors back off 1, 2, 4, … s (at most [timeout]); HTTP 501 (bus
/// not supported) stops; redirects are followed. A new channel aborts the
/// running request and polls again with the new list; [stop] (logout,
/// other session) ends it.
class BusService {
  /// Own HTTP client: its receive timeout exceeds the server's polling
  /// timeout (`client.bus_timeout` = 10 min).
  final Dio _dio;
  final Future<void> Function(Duration) _sleep;
  final Duration timeout;

  BusService({
    @visibleForTesting Dio? dio,
    @visibleForTesting Future<void> Function(Duration)? sleep,
    this.timeout = const Duration(minutes: 10),
  })  : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: timeout,
              sendTimeout: const Duration(seconds: 30),
            )),
        _sleep = sleep ?? Future.delayed;

  final Map<String, List<BusCallback>> _channels = {};

  String? _url;
  SessionAuth? _auth;

  /// Id of the last message received (sent with the next poll).
  dynamic lastMessage;

  /// Generation of the polling loop: a new loop (new channel, other
  /// session) makes older ones end.
  int _generation = 0;
  CancelToken? _cancel;

  /// Polling runs.
  bool get running => _url != null;

  /// The server answered 501 (no bus).
  bool unsupported = false;

  /// Polls sent (diagnosis, tests).
  int requests = 0;

  /// Last error of a poll (cleared by an answer).
  Object? lastError;

  /// Channels currently polled.
  List<String> get channels => [..._channels.keys];

  /// Starts polling for [database] of the session [auth] when [host]
  /// (`bus_url_host`, ends with `/`) is set; a running poll of another
  /// session is dropped.
  void start(
      {required String? host,
      required String database,
      required SessionAuth auth}) {
    stop();
    if (host == null || host.isEmpty) return;
    final base = Uri.parse(host.endsWith('/') ? host : '$host/');
    _url = base.resolve('${Uri.encodeComponent(database)}/bus').toString();
    _auth = auth;
    lastMessage = null;
    unsupported = false;
    _restart();
  }

  /// A new token of the same session (re-login after HTTP 401): a
  /// running poll continues with it.
  void updateAuth(SessionAuth auth) {
    if (_url == null) return;
    _auth = auth;
    _restart();
  }

  /// Stops polling (logout, session change); the channels stay
  /// registered.
  void stop() {
    _generation++;
    _cancel?.cancel('stopped');
    _cancel = null;
    _url = null;
    _auth = null;
  }

  /// Registers [callback] for [channel]; a new channel restarts the poll.
  void register(String channel, BusCallback callback) {
    final restart = !_channels.containsKey(channel);
    _channels.putIfAbsent(channel, () => []).add(callback);
    if (restart && running) _restart();
  }

  void unregister(String channel, BusCallback callback) {
    final list = _channels[channel];
    if (list == null) return;
    list.remove(callback);
    if (list.isEmpty) _channels.remove(channel);
  }

  /// Removes all channels (logout).
  void clear() => _channels.clear();

  void _restart() {
    _generation++;
    _cancel?.cancel('channels changed');
    _cancel = null;
    unawaited(_loop(_generation));
  }

  Future<void> _loop(int generation) async {
    var wait = 1;
    var url = _url;
    while (generation == _generation && url != null && !unsupported) {
      final cancel = _cancel = CancelToken();
      requests++;
      try {
        final response = await _dio.post<String>(
          url,
          data: jsonEncode({
            'last_message': lastMessage,
            'channels': channels,
          }),
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (s) => s != null && s >= 200 && s < 300,
            headers: {
              'Content-Type': 'application/json',
              if (_auth != null) 'Authorization': _auth!.header,
            },
          ),
        );
        wait = 1;
        lastError = null;
        if (generation != _generation) return;
        _handle(response.data);
      } on DioException catch (e) {
        if (generation != _generation || CancelToken.isCancel(e)) return;
        lastError = e;
        final status = e.response?.statusCode;
        if (e.type == DioExceptionType.receiveTimeout) {
          // no message within the timeout: poll again at once
          wait = 1;
          continue;
        }
        if (status != null &&
            const {301, 302, 303, 307, 308}.contains(status)) {
          final location = e.response?.headers.value('location');
          if (location != null) {
            url = Uri.parse(url).resolve(location).toString();
            continue;
          }
        }
        if (status == 501) {
          // bus not supported by the server
          unsupported = true;
          return;
        }
        await _backoff(wait, generation);
        wait *= 2;
      } catch (_) {
        if (generation != _generation) return;
        await _backoff(wait, generation);
        wait *= 2;
      }
    }
  }

  Future<void> _backoff(int seconds, int generation) async {
    final delay = Duration(seconds: seconds);
    await _sleep(delay < timeout ? delay : timeout);
  }

  /// `{channel, message}`: remembers `message_id`, calls the callbacks.
  void _handle(String? body) {
    if (body == null || body.isEmpty) return;
    final data = TrytonSerializer.decode(jsonDecode(body));
    if (data is! Map) return;
    final message = data['message'];
    if (message is! Map) return;
    lastMessage = message['message_id'];
    final channel = '${data['channel']}';
    for (final callback in [...?_channels[channel]]) {
      try {
        callback(Map<String, dynamic>.from(message));
      } catch (e) {
        debugPrint('bus callback of $channel failed: $e');
      }
    }
  }
}

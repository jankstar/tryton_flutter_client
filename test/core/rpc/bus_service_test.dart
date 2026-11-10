import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/bus_service.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';

/// A poll seen by the fake server; [answer] completes it.
class _Poll {
  final RequestOptions options;
  final Map<String, dynamic> body;
  final Completer<ResponseBody> completer = Completer();
  _Poll(this.options, this.body);

  void answer(int status, Object? json, {Map<String, List<String>>? headers}) =>
      completer.complete(ResponseBody.fromString(
          json is String ? json : jsonEncode(json), status,
          headers: headers ?? {'content-type': ['application/json']}));

  void fail(DioExceptionType type) => completer.completeError(
      DioException(requestOptions: options, type: type));
}

/// Fake HTTP: every request becomes a pending [_Poll]; a cancelled one
/// fails like Dio.
class _FakeBus implements HttpClientAdapter {
  final polls = <_Poll>[];
  final _added = StreamController<_Poll>.broadcast();

  Future<_Poll> next() => polls.length > _seen ? Future.value(polls[_seen++]) : _added.stream.first.then((p) { _seen++; return p; });
  int _seen = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    final poll = _Poll(options, jsonDecode(options.data as String) as Map<String, dynamic>);
    polls.add(poll);
    _added.add(poll);
    cancelFuture?.then((_) {
      if (!poll.completer.isCompleted) poll.fail(DioExceptionType.cancel);
    });
    return poll.completer.future;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _FakeBus server;
  late List<Duration> sleeps;
  late BusService bus;
  const auth = SessionAuth('admin', 1, 'tok');

  setUp(() {
    server = _FakeBus();
    sleeps = [];
    bus = BusService(
        dio: Dio()..httpClientAdapter = server,
        sleep: (d) async => sleeps.add(d),
        timeout: const Duration(seconds: 600));
  });
  tearDown(() => bus.stop());

  Future<void> idle() => Future<void>.delayed(Duration.zero);

  test('URL join, header, channels; message → callback, last_message',
      () async {
    final got = <Map<String, dynamic>>[];
    bus.register('notification:1', got.add);
    bus.start(host: 'http://127.0.0.1:8000/', database: 'tryton', auth: auth);
    final first = await server.next();
    expect(first.options.uri.toString(), 'http://127.0.0.1:8000/tryton/bus');
    expect(first.options.headers['Authorization'], auth.header);
    expect(first.body, {
      'last_message': null,
      'channels': ['notification:1']
    });
    first.answer(200, {
      'channel': 'notification:1',
      'message': {'type': 'user-notification', 'count': 8, 'message_id': 'm1'}
    });
    final second = await server.next();
    expect(got.single['count'], 8);
    expect(second.body['last_message'], 'm1', reason: 'last_message kept');
    // a timeout of the server: message null, polled again
    second.answer(200, {'message': null, 'channel': null});
    final third = await server.next();
    expect(third.body['last_message'], 'm1');
    expect(sleeps, isEmpty);
  });

  test('client timeout polls again at once; errors back off 1, 2, 4 s',
      () async {
    bus.register('client:x', (_) {});
    bus.start(host: 'http://h/', database: 'db', auth: auth);
    (await server.next()).fail(DioExceptionType.receiveTimeout);
    (await server.next()).answer(500, 'boom');
    (await server.next()).fail(DioExceptionType.connectionError);
    (await server.next()).answer(502, 'bad gateway');
    final fifth = await server.next();
    expect(sleeps, const [Duration(seconds: 1), Duration(seconds: 2), Duration(seconds: 4)]);
    // an answer resets the backoff
    fifth.answer(200, {'message': null});
    (await server.next()).answer(500, 'x');
    await server.next();
    expect(sleeps.last, const Duration(seconds: 1));
  });

  test('a new channel aborts the running poll and polls again', () async {
    bus.register('client:x', (_) {});
    bus.start(host: 'http://h/', database: 'db', auth: auth);
    final first = await server.next();
    bus.register('notification:5', (_) {});
    final second = await server.next();
    await idle();
    expect(first.completer.isCompleted, isTrue, reason: 'cancelled');
    expect(second.body['channels'], ['client:x', 'notification:5']);
    // the same channel again: no restart
    bus.register('notification:5', (_) {});
    await idle();
    expect(server.polls, hasLength(2));
    expect(sleeps, isEmpty, reason: 'a cancel is no error');
  });

  test('501 stops; stop (logout) ends the poll; no host: no polling',
      () async {
    bus.register('client:x', (_) {});
    bus.start(host: 'http://h/', database: 'db', auth: auth);
    (await server.next()).answer(501, 'Not Implemented');
    await idle();
    await idle();
    expect(bus.unsupported, isTrue);
    expect(server.polls, hasLength(1));

    bus.start(host: 'http://h/', database: 'db', auth: auth);
    final poll = await server.next();
    bus.stop();
    await idle();
    expect(poll.completer.isCompleted, isTrue);
    await idle();
    expect(server.polls, hasLength(2), reason: 'stopped');
    expect(bus.running, isFalse);

    bus.start(host: null, database: 'db', auth: auth);
    await idle();
    expect(server.polls, hasLength(2));
    expect(bus.running, isFalse);
  });

  test('redirect is followed', () async {
    bus.register('client:x', (_) {});
    bus.start(host: 'http://h/', database: 'db', auth: auth);
    (await server.next()).answer(307, '', headers: {
      'location': ['http://other/db/bus']
    });
    final next = await server.next();
    expect(next.options.uri.toString(), 'http://other/db/bus');
  });

  test('a new token after a re-login: the poll continues with it; not '
      'running → nothing', () async {
    bus.updateAuth(const SessionAuth('admin', 1, 'other'));
    await idle();
    expect(server.polls, isEmpty, reason: 'not started');

    bus.register('notification:1', (_) {});
    bus.start(host: 'http://127.0.0.1:8000/', database: 'tryton', auth: auth);
    await server.next();
    const renewed = SessionAuth('admin', 1, 'tok2');
    bus.updateAuth(renewed);
    final poll = await server.next();
    expect(poll.options.headers['Authorization'], renewed.header);
  });
}

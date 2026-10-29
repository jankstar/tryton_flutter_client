import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_cache.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';

/// Answers with an incrementing result and the given cache header.
class _Adapter implements HttpClientAdapter {
  final Map<String, String> cacheHeaders;
  int requests = 0;
  _Adapter(this.cacheHeaders);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests++;
    final method = jsonDecode(options.data as String)['method'] as String;
    final seconds = cacheHeaders[method];
    return ResponseBody.fromString(
        jsonEncode({'id': 1, 'result': requests}), 200,
        headers: {
          'content-type': ['application/json'],
          if (seconds != null) 'x-tryton-cache': [seconds],
        });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late DateTime now;
  late RpcCache cache;

  setUp(() {
    now = DateTime(2026, 10, 29, 12);
    cache = RpcCache(now: () => now);
  });

  group('RpcCache', () {
    test('entries expire', () {
      cache.set('m', 'k', 10, 'body');
      expect(cache.cached('m'), isTrue);
      expect(cache.get('m', 'k'), 'body');
      now = now.add(const Duration(seconds: 9));
      expect(cache.get('m', 'k'), 'body');
      now = now.add(const Duration(seconds: 1));
      expect(cache.get('m', 'k'), isNull);
      expect(cache.length, 0);
      // the method stays known as cacheable
      expect(cache.cached('m'), isTrue);
    });

    test('clear by prefix, clear all', () {
      cache.set('model.party.party.view_toolbar_get', 'a', 60, '1');
      cache.set('model.party.address.view_toolbar_get', 'a', 60, '2');
      cache.set('model.ir.ui.view_tree_state.get', 'a', 60, '3');
      cache.clear('model.party.party.');
      expect(cache.cached('model.party.party.view_toolbar_get'), isFalse);
      expect(cache.get('model.party.address.view_toolbar_get', 'a'), '2');
      cache.clear('model.ir.ui.view_tree_state.get');
      expect(cache.get('model.ir.ui.view_tree_state.get', 'a'), isNull);
      expect(cache.length, 1);
      cache.clear();
      expect(cache.length, 0);
      expect(cache.cached('model.party.address.view_toolbar_get'), isFalse);
    });

    test('the oldest entry goes first when full', () {
      cache = RpcCache(maxSize: 2, now: () => now);
      cache.set('a', '1', 60, 'a1');
      cache.set('b', '1', 60, 'b1');
      cache.set('a', '2', 60, 'a2');
      expect(cache.get('a', '1'), isNull);
      expect(cache.get('b', '1'), 'b1');
      expect(cache.get('a', '2'), 'a2');
    });
  });

  group('RpcClient with cache', () {
    (RpcClient, _Adapter) client(Map<String, String> headers) {
      final adapter = _Adapter(headers);
      return (
        RpcClient(
            baseUrl: 'http://localhost:8000',
            dio: Dio()..httpClientAdapter = adapter,
            cache: RpcCache(now: () => now)),
        adapter
      );
    }

    test('X-Tryton-Cache results are reused per (method, params)',
        () async {
      final (rpc, adapter) = client({'model.ir.ui.menu.read': '60'});
      expect(await rpc.call('tryton', 'model.ir.ui.menu.read', [1, {}]), 1);
      expect(await rpc.call('tryton', 'model.ir.ui.menu.read', [1, {}]), 1);
      expect(adapter.requests, 1);
      // other parameters, other database: own entries
      expect(await rpc.call('tryton', 'model.ir.ui.menu.read', [2, {}]), 2);
      expect(await rpc.call('other', 'model.ir.ui.menu.read', [1, {}]), 3);
      expect(adapter.requests, 3);
      // expired: asked again
      now = now.add(const Duration(seconds: 61));
      expect(await rpc.call('tryton', 'model.ir.ui.menu.read', [1, {}]), 4);
    });

    test('methods without the header are never cached', () async {
      final (rpc, adapter) = client({});
      await rpc.call('tryton', 'model.party.party.read', [1, {}]);
      await rpc.call('tryton', 'model.party.party.read', [1, {}]);
      expect(adapter.requests, 2);
      expect(rpc.cache.length, 0);
    });

    test('cleared cache asks the server again', () async {
      final (rpc, adapter) = client({'m': '60'});
      await rpc.call('tryton', 'm', []);
      rpc.cache.clear(); // e.g. logout
      expect(await rpc.call('tryton', 'm', []), 2);
      expect(adapter.requests, 2);
    });
  });
}

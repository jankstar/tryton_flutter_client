@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/rpc/server_address.dart';

/// The test server (plain HTTP on 8000) entered without scheme: HTTPS
/// fails, HTTP is taken (read only, no login).
void main() {
  test('localhost:8000 → http://localhost:8000', () async {
    HttpOverrides.global = null;
    var known = <String, String>{};
    final rpc = RpcClient(baseUrl: 'http://localhost');
    final url = await ServerResolver(
            load: () async => known, save: (k) async => known = k)
        .resolve('localhost:8000', (url) async {
      rpc.baseUrl = url;
      await rpc.serverVersion();
    });
    expect(url, 'http://localhost:8000');
    expect(known, {'localhost:8000': 'http'});
  });
}

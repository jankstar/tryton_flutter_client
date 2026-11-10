@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/shared/utils/export_url.dart';

/// URL export (spec 11.9) against the test server: the URL fetched with
/// the session header by GET gives CSV (read only).
///
///     TRYTON_PASSWORD=… flutter test --run-skipped -t integration \\
///       test/integration/export_url_integration_test.dart
void main() {
  test('the export URL gives the CSV of the parties', () async {
    final password = Platform.environment['TRYTON_PASSWORD'];
    if (password == null) {
      markTestSkipped('TRYTON_PASSWORD not set');
      return;
    }
    HttpOverrides.global = null;
    const base = 'http://127.0.0.1:8000/';
    final rpc = RpcClient(baseUrl: base);
    final result = await rpc.call('tryton', 'common.db.login', [
      'admin',
      {'password': password},
      'de'
    ], reAuth: false) as List;
    final auth = SessionAuth('admin', result[0] as int, result[1] as String);
    rpc.auth = auth;
    try {
      final url = exportUrl(
        baseUrl: base,
        database: 'tryton',
        model: 'party.party',
        domain: [
          ['name', 'ilike', '%a%']
        ],
        limit: 5,
        page: 0,
        order: [
          ['name', 'ASC']
        ],
        context: {'language': 'de'},
        fields: ['name', 'code'],
        encoding: 'utf_8',
        delimiter: ';',
        quote: '"',
      );
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Authorization', auth.header);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      expect(response.statusCode, 200, reason: body);
      expect(response.headers.contentType?.mimeType, 'text/csv');
      final lines = const LineSplitter().convert(body);
      expect(lines.first, contains(';'), reason: 'header with ; delimiter');
      expect(lines.length, inInclusiveRange(2, 6), reason: 'header + ≤ 5 rows');
    } finally {
      await rpc.call('tryton', 'common.db.logout', [], reAuth: false);
    }
  });
}

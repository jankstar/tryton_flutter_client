import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/actions/deep_links.dart';

/// tryton:// links of the operating system (spec 12.7, E7).
void main() {
  test('the start link and later links; other schemes ignored; the start '
      'link delivered twice counts once', () async {
    final stream = StreamController<Uri>();
    final received = <String>[];
    final links = DeepLinks(
      links: stream.stream,
      initial: () async => Uri.parse('tryton://srv:8000/db/model/party.party/1'),
    );
    await links.start(received.add);
    // the platform repeats the start link on the stream
    stream.add(Uri.parse('tryton://srv:8000/db/model/party.party/1'));
    stream.add(Uri.parse('https://example.com/'));
    stream.add(Uri.parse('tryton://srv:8000/db/model/sale.sale/7'));
    await Future<void>.delayed(Duration.zero);
    expect(received, [
      'tryton://srv:8000/db/model/party.party/1',
      'tryton://srv:8000/db/model/sale.sale/7',
    ]);
    links.dispose();
    await stream.close();
  });

  test('no plugin (tests, unsupported platform): no error', () async {
    final links = DeepLinks(
      links: Stream<Uri>.error(Exception('no plugin')),
      initial: () async => throw Exception('no plugin'),
    );
    await links.start((_) => fail('no link expected'));
    links.dispose();
  });
}

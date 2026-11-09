import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/bus_service.dart';
import 'package:tryton_flutter_client/core/session/session.dart';
import 'package:tryton_flutter_client/core/session/session_store.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/notifications/notifications.dart';
import 'package:tryton_flutter_client/features/views/chat_panel.dart';

import 'form_harness.dart';

class _NoStore implements SessionStore {
  @override
  Future<StoredSession?> read([String? key]) async => null;
  @override
  Future<void> write(StoredSession session) async {}
  @override
  Future<void> delete([String? key]) async {}
}

/// Bus without polling: the registered channels and a way to deliver a
/// message.
class _FakeBus extends BusService {
  final registered = <String, List<BusCallback>>{};

  @override
  void register(String channel, BusCallback callback) =>
      registered.putIfAbsent(channel, () => []).add(callback);

  @override
  void unregister(String channel, BusCallback callback) {
    registered[channel]?.remove(callback);
    if (registered[channel]?.isEmpty ?? false) registered.remove(channel);
  }

  void deliver(String channel, Map<String, dynamic> message) {
    for (final c in [...?registered[channel]]) {
      c(message);
    }
  }
}

/// Chat of a record (spec 14.2, Python `tryton/chat.py`, H2).
void main() {
  /// `ir.chat.channel` of a server with [messages].
  FakeFormRpc server(List<Map<String, dynamic>> messages,
          {List<Map<String, dynamic>> followers = const []}) =>
      FakeFormRpc({
        'model.ir.chat.channel.get': (_) => [...messages],
        'model.ir.chat.channel.post': (p) {
          messages.add({
            'id': messages.length + 1,
            'author': 'Admin',
            'content': p[1],
            'audience': p[2],
          });
          return messages.length;
        },
        'model.ir.chat.channel.get_followers': (_) => followers,
        'model.ir.chat.channel.search_followers': (_) => [
              {'type': 'user', 'key': 'jan', 'name': 'Jan'},
            ],
        'model.ir.chat.channel.subscribe': (_) => null,
        'model.ir.chat.channel.unsubscribe': (_) => null,
      });

  Future<_FakeBus> pump(WidgetTester tester, FakeFormRpc rpc,
      {String resource = 'party.party,1'}) async {
    final bus = _FakeBus();
    final session = TrytonSession(rpcClient: rpc, store: _NoStore())
      ..login = 'admin';
    await pumpApp(
      tester,
      rpc,
      Scaffold(body: ChatPanel(resource: resource)),
      settle: false,
      overrides: [
        busServiceProvider.overrideWithValue(bus),
        sessionProvider.overrideWithValue(session),
      ],
    );
    await pumpFrames(tester, 5);
    return bus;
  }

  testWidgets('loads the messages, registers chat:<model>,<id>; sending '
      'posts the text with the audience', (tester) async {
    final messages = <Map<String, dynamic>>[
      {
        'id': 1,
        'author': 'Jan',
        'content': 'Hello',
        'audience': 'public',
        'timestamp': DateTime.utc(2026, 11, 9, 10),
      },
    ];
    final rpc = server(messages);
    final bus = await pump(tester, rpc);
    expect(rpc.named('model.ir.chat.channel.get').first.params, ['party.party,1']);
    expect(find.text('Hello'), findsOneWidget);
    expect(bus.registered.keys, ['chat:party.party,1']);

    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'Internal note');
    await tester.tap(find.byKey(const ValueKey('chat-internal')));
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await pumpFrames(tester, 5);
    expect(rpc.named('model.ir.chat.channel.post').single.params,
        ['party.party,1', 'Internal note', 'internal']);
    // without a running bus the messages are read again (Python `_submit`)
    expect(find.text('Internal note'), findsOneWidget);
    expect(find.text('internal'), findsOneWidget, reason: 'audience tag');
  });

  testWidgets('an incoming bus message reloads the chat; closing '
      'unregisters the channel', (tester) async {
    final messages = <Map<String, dynamic>>[];
    final rpc = server(messages);
    final bus = await pump(tester, rpc);
    expect(find.text('No messages yet.'), findsOneWidget);

    messages.add({'id': 7, 'author': 'Jan', 'content': 'From elsewhere', 'audience': 'public'});
    bus.deliver('chat:party.party,1', {'type': 'message', 'message': messages.last});
    await pumpFrames(tester, 5);
    expect(find.text('From elsewhere'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    expect(bus.registered, isEmpty, reason: 'unregistered on close');
  });

  testWidgets('followers: subscribe oneself, add a follower', (tester) async {
    final rpc = server([], followers: [
      {'type': 'email', 'key': 'x@example.com', 'name': 'X'},
    ]);
    await pump(tester, rpc);
    await tester.tap(find.byKey(const ValueKey('chat-followers')));
    await pumpFrames(tester, 5);
    expect(find.text('X'), findsOneWidget, reason: 'other follower');
    await tester.tap(find.byKey(const ValueKey('chat-toggle-subscribe')));
    await pumpFrames(tester, 5);
    expect(rpc.named('model.ir.chat.channel.subscribe').single.params,
        ['party.party,1'], reason: 'oneself');

    await tester.enterText(find.byKey(const ValueKey('chat-add-follower')), 'ja');
    await pumpFrames(tester, 5);
    await tester.tap(find.text('Jan'));
    await pumpFrames(tester, 5);
    expect(rpc.named('model.ir.chat.channel.subscribe').last.params,
        ['party.party,1', 'jan']);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/bus_service.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/session/session.dart';
import 'package:tryton_flutter_client/core/session/session_store.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/notifications/notifications.dart';
import 'package:tryton_flutter_client/features/shell/tab_manager.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

import '../views/form_harness.dart';

class _NoStore implements SessionStore {
  @override
  Future<StoredSession?> read([String? key]) async => null;
  @override
  Future<void> write(StoredSession session) async {}
  @override
  Future<void> delete([String? key]) async {}
}

/// Bus answering once with [message], then hanging.
class _OneMessageBus implements HttpClientAdapter {
  final Map<String, dynamic> message;
  final requests = <Map<String, dynamic>>[];
  _OneMessageBus(this.message);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    requests.add(jsonDecode(options.data as String) as Map<String, dynamic>);
    if (requests.length == 1) {
      return Future.value(ResponseBody.fromString(jsonEncode(message), 200,
          headers: {'content-type': ['application/json']}));
    }
    final c = Completer<ResponseBody>();
    cancelFuture?.then((_) => c.completeError(
        DioException(requestOptions: options, type: DioExceptionType.cancel)));
    return c.future;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final notifications = [
    {
      'id': 15,
      'label': 'Task due',
      'description': 'due 15.01.2026',
      'icon': 'tryton-notification',
      'model': 'real_estate.task',
      'records': [7],
      'action': null,
      'unread': true,
    },
    {
      'id': 12,
      'label': 'Run report',
      'description': '',
      'icon': null,
      'model': null,
      'records': [],
      'action': null,
      'unread': false,
    },
  ];

  Future<ProviderContainer> pump(WidgetTester tester, FakeFormRpc rpc,
      {BusService? bus}) async {
    rpc.auth = const SessionAuth('admin', 1, 'tok');
    final session = TrytonSession(rpcClient: rpc, store: _NoStore())
      ..database = 'test'
      ..userId = 1
      ..login = 'admin'
      ..busUrlHost = 'http://127.0.0.1:8000/';
    final svc = ModelService(
        rpc: rpc, getContext: () => const {}, getDatabase: () => 'test');
    final container = ProviderContainer(overrides: [
      rpcClientProvider.overrideWithValue(rpc),
      sessionProvider.overrideWithValue(session),
      modelServiceProvider.overrideWithValue(svc),
      if (bus != null) busServiceProvider.overrideWithValue(bus),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        scaffoldMessengerKey: rootMessengerKey,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            appBar: AppBar(actions: const [NotificationButton()]),
            body: const SizedBox()),
      ),
    ));
    return container;
  }

  testWidgets('badge from get_count, list from get, open → tab + mark_read',
      (tester) async {
    final rpc = FakeFormRpc({
      'model.res.notification.get_count': (_) => 2,
      'model.res.notification.get': (_) => notifications,
      'model.res.notification.mark_read': (_) => null,
      'model.ir.model.get_names': (_) => {'real_estate.task': 'Task'},
    });
    final container = await pump(tester, rpc);
    await container.read(notificationCenterProvider).refreshCount();
    await tester.pump();
    expect(find.text('2'), findsOneWidget, reason: 'badge');

    await tester.tap(find.byKey(const ValueKey('notification-button')));
    await tester.pumpAndSettle();
    expect(find.text('Task due'), findsOneWidget);
    expect(find.text('due 15.01.2026'), findsOneWidget);
    expect(find.text('Run report'), findsOneWidget);
    expect(find.text('All Notifications...'), findsOneWidget);
    expect(find.text('2'), findsNothing, reason: 'indicator cleared (Python)');

    await tester.tap(find.text('Task due'));
    await tester.pumpAndSettle();
    final tab = container.read(tabsProvider).tabs.single;
    expect(tab.attributes.model, 'real_estate.task');
    expect(tab.attributes.resId, 7, reason: 'one record: form');
    expect(tab.attributes.mode, ['form', 'tree']);
    expect(tab.attributes.domain, [
      ['id', 'in', [7]]
    ]);
    expect(rpc.named('model.res.notification.mark_read').single.params, [
      [15]
    ]);

    await tester.tap(find.byKey(const ValueKey('notification-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Notifications...'));
    await tester.pumpAndSettle();
    final all = container.read(tabsProvider).tabs.last;
    expect(all.attributes.model, 'res.notification');
    expect(all.attributes.domain, [
      ['user', '=', 1]
    ]);
  });

  testWidgets('bus: user-notification updates the badge and shows the text; '
      'stop ends the polling', (tester) async {
    final adapter = _OneMessageBus({
      'channel': 'notification:1',
      'message': {
        'type': 'user-notification',
        'count': 9,
        'content': ['New task\nPlease check'],
        'message_id': 'm1',
      }
    });
    final bus = BusService(dio: Dio()..httpClientAdapter = adapter);
    final rpc = FakeFormRpc({'model.res.notification.get_count': (_) => 8});
    final container = await pump(tester, rpc, bus: bus);
    await tester.runAsync(() async {
      await container.read(notificationCenterProvider).start();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final session = container.read(sessionProvider);
    expect(adapter.requests.first['channels'],
        unorderedEquals(['notification:1', 'client:${session.clientId}']));
    expect(container.read(notificationCountProvider), 9);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('New task\nPlease check'), findsOneWidget,
        reason: 'in-app message');
    expect(adapter.requests.length, 2, reason: 'polling again with m1');
    expect(adapter.requests.last['last_message'], 'm1');

    container.read(notificationCenterProvider).stop();
    expect(bus.running, isFalse);
    expect(container.read(notificationCountProvider), 0);
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}

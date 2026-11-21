import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_activity.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';
import 'package:tryton_flutter_client/shared/widgets/rpc_wait_overlay.dart';

/// Wait indicator of long server calls (spec T1, Python `RPCProgress`).
void main() {
  late RpcActivityMonitor monitor;
  var taps = 0;

  Future<void> pump(WidgetTester tester) async {
    monitor = RpcActivityMonitor();
    taps = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          RpcWaitOverlay(monitor: monitor, child: child!),
      home: Scaffold(
        body: Center(
          child: ElevatedButton(
              onPressed: () => taps++, child: const Text('Form')),
        ),
      ),
    ));
  }

  Finder overlay() => find.byKey(const ValueKey('rpc-wait'));

  testWidgets('appears after 3 s with the elapsed time and blocks input',
      (tester) async {
    await pump(tester);
    final call = monitor.start('model.x.write', CancelToken());
    await tester.pump(const Duration(milliseconds: 2900));
    expect(overlay(), findsNothing, reason: 'short calls show nothing');
    await tester.pump(const Duration(milliseconds: 200));
    expect(overlay(), findsOneWidget);
    expect(find.text('Waiting for the server… 0:03'), findsOneWidget);
    await tester.pump(const Duration(seconds: 62));
    expect(find.text('Waiting for the server… 1:05'), findsOneWidget);

    await tester.tap(find.text('Form'), warnIfMissed: false);
    expect(taps, 0, reason: 'the barrier takes the click');

    monitor.end(call);
    await tester.pump();
    expect(overlay(), findsNothing);
    await tester.tap(find.text('Form'));
    expect(taps, 1);
  });

  testWidgets('Stop waiting cancels the request', (tester) async {
    await pump(tester);
    final cancel = CancelToken();
    final call =
        monitor.start('wizard.ir.module.activate_upgrade.execute', cancel);
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.byKey(const ValueKey('rpc-wait-stop')));
    await tester.pump();
    expect(cancel.isCancelled, isTrue);
    expect(call.abandoned, isTrue);
    expect(overlay(), findsNothing);
  });

  testWidgets('background calls never show it', (tester) async {
    await pump(tester);
    monitor.start('model.x.search_count', CancelToken(), background: true);
    await tester.pump(const Duration(seconds: 10));
    expect(overlay(), findsNothing);
  });
}

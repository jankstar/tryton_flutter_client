import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/error_processing.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_client.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';
import 'package:tryton_flutter_client/shared/errors/error_dialogs.dart';
import 'package:tryton_flutter_client/shared/errors/error_handler.dart';

class _FakePresenter implements ErrorPresenter {
  final log = <String>[];
  final warningAnswers = <WarningChoice>[];

  @override
  Future<void> userError(String message, String description) async =>
      log.add('userError:$message|$description');
  @override
  Future<WarningChoice> userWarning(String message, String description) async {
    log.add('warning:$message|$description');
    return warningAnswers.removeAt(0);
  }

  @override
  Future<void> applicationError(String title, String details) async =>
      log.add('app:$title|$details');
  @override
  Future<void> httpError(int? code, String text) async =>
      log.add('http:$code|$text');
  @override
  Future<void> concurrency() async => log.add('concurrency');
}

class _FakeRpc extends RpcClient {
  _FakeRpc() : super(baseUrl: 'http://localhost');
  final calls = <(String, List<dynamic>)>[];
  @override
  Future<dynamic> call(String database, String method, List<dynamic> params,
      {bool reAuth = true}) async {
    calls.add((method, params));
    return null;
  }
}

class _ThrowingRpc extends RpcClient {
  _ThrowingRpc() : super(baseUrl: 'http://localhost');
  @override
  Future<dynamic> call(String database, String method, List<dynamic> params,
          {bool reAuth = true}) async =>
      throw const UserError('Fehler');
}

const _warning = UserWarning('party_check_vat', 'VAT number missing',
    description: 'Save anyway?');

void main() {
  late _FakePresenter presenter;
  late List<(String, bool)> skips;
  late ErrorHandler handler;

  setUp(() {
    presenter = _FakePresenter();
    skips = [];
    handler = ErrorHandler(
      presenter: presenter,
      skipWarning: (name, always) async => skips.add((name, always)),
    );
  });

  /// Action that throws [_warning] [times] times, then succeeds.
  (Future<void> Function(), List<int>) warnThenSucceed(int times) {
    final attempts = <int>[];
    return (
      () async {
        attempts.add(attempts.length + 1);
        if (attempts.length <= times) throw _warning;
      },
      attempts
    );
  }

  group('process (RpcErrorProcessor, ModelService processException)', () {
    test('success returns the value without dialog', () async {
      expect(await handler.process(() async => 42), 42);
      expect(presenter.log, isEmpty);
    });

    test('error: shown once, rethrown as HandledRpcError', () async {
      await expectLater(
          handler.process<void>(() async => throw const UserError('Nein')),
          throwsA(isA<HandledRpcError>()
              .having((e) => e.error, 'error', isA<UserError>())));
      expect(presenter.log, ['userError:Nein|']);
      // run/show do not show it a second time.
      expect(
          await handler.run(() async {
            await handler.process<void>(
                () async => throw const UserError('Zwei'));
          }),
          isFalse);
      expect(presenter.log, ['userError:Nein|', 'userError:Zwei|']);
      await handler.show(const HandledRpcError(UserError('Drei')));
      expect(presenter.log, hasLength(2));
    });

    test('UserWarning: skip and repeat; cancel → HandledRpcError', () async {
      presenter.warningAnswers.add(WarningChoice.ok);
      var n = 0;
      expect(
          await handler.process(() async {
            if (n++ == 0) throw _warning;
            return 'ok';
          }),
          'ok');
      expect(skips, [('party_check_vat', false)]);
      presenter.warningAnswers.add(WarningChoice.cancel);
      await expectLater(handler.process<void>(() async => throw _warning),
          throwsA(isA<HandledRpcError>()));
    });

    test('ModelService.execute: processException true/false', () async {
      final rpc = _ThrowingRpc();
      final svc = ModelService(
          rpc: rpc, getContext: () => {}, getDatabase: () => 'db');
      // Without processor the error reaches the caller unchanged.
      await expectLater(svc.execute<dynamic>('x', 'm', []),
          throwsA(isA<UserError>()));
      svc.errorProcessor = handler;
      await expectLater(svc.execute<dynamic>('x', 'm', []),
          throwsA(isA<HandledRpcError>()));
      expect(presenter.log, ['userError:Fehler|']);
      // processException: false → no dialog, original error.
      await expectLater(
          svc.execute<dynamic>('x', 'm', [], processException: false),
          throwsA(isA<UserError>()));
      expect(presenter.log, hasLength(1));
    });
  });

  group('UserWarning: skip and repeat the original call', () {
    test('OK → skip(name, false), call repeated, success', () async {
      presenter.warningAnswers.add(WarningChoice.ok);
      final (action, attempts) = warnThenSucceed(1);
      expect(await handler.run(action), isTrue);
      expect(attempts, [1, 2]);
      expect(skips, [('party_check_vat', false)]);
      expect(presenter.log, ['warning:VAT number missing|Save anyway?']);
    });

    test('Always ignore → skip(name, true), call repeated', () async {
      presenter.warningAnswers.add(WarningChoice.always);
      final (action, attempts) = warnThenSucceed(1);
      expect(await handler.run(action), isTrue);
      expect(attempts, [1, 2]);
      expect(skips, [('party_check_vat', true)]);
    });

    test('Cancel → no skip, not repeated, false', () async {
      presenter.warningAnswers.add(WarningChoice.cancel);
      final (action, attempts) = warnThenSucceed(1);
      expect(await handler.run(action), isFalse);
      expect(attempts, [1]);
      expect(skips, isEmpty);
    });

    test('several warnings in a row are asked one after another', () async {
      presenter.warningAnswers
          .addAll([WarningChoice.ok, WarningChoice.always]);
      final (action, attempts) = warnThenSucceed(2);
      expect(await handler.run(action), isTrue);
      expect(attempts, [1, 2, 3]);
      expect(skips, [('party_check_vat', false), ('party_check_vat', true)]);
    });

    test('error in the repeated call is shown', () async {
      presenter.warningAnswers.add(WarningChoice.ok);
      var n = 0;
      final ok = await handler.run(() async {
        if (n++ == 0) throw _warning;
        throw const UserError('Invalid', description: 'Code missing');
      });
      expect(ok, isFalse);
      expect(presenter.log.last, 'userError:Invalid|Code missing');
    });

    test('failing skip call is shown, call not repeated', () async {
      presenter.warningAnswers.add(WarningChoice.ok);
      final failing = ErrorHandler(
        presenter: presenter,
        skipWarning: (_, _) async =>
            throw const RpcHttpException(403, 'Access denied (403).'),
      );
      final (action, attempts) = warnThenSucceed(1);
      expect(await failing.run(action), isFalse);
      expect(attempts, [1]);
      expect(presenter.log.last, 'http:403|Forbidden');
    });

    test('skipUserWarning calls model.res.user.warning.skip(name, always, ctx)',
        () async {
      final rpc = _FakeRpc();
      final svc = ModelService(
          rpc: rpc,
          getContext: () => {'language': 'de'},
          getDatabase: () => 'tryton');
      await skipUserWarning(svc, 'party_check_vat', true);
      expect(rpc.calls.single.$1, 'model.res.user.warning.skip');
      expect(rpc.calls.single.$2, [
        'party_check_vat',
        true,
        {'language': 'de'}
      ]);
    });
  });

  group('error → dialog mapping', () {
    Future<String> shown(Object error) async {
      expect(await handler.run(() async => throw error), isFalse);
      return presenter.log.single;
    }

    test('success shows nothing', () async {
      expect(await handler.run(() async {}), isTrue);
      expect(presenter.log, isEmpty);
    });
    test('UserError: title = message, text = description', () async {
      expect(await shown(const UserError('Msg', description: 'Desc')),
          'userError:Msg|Desc');
    });
    test('RpcServerException: application error with traceback', () async {
      expect(
          await shown(const RpcServerException(
              'division by zero', 'Traceback (most recent call last): …')),
          'app:division by zero|Traceback (most recent call last): …');
    });
    test('RpcHttpException: code + reason', () async {
      expect(await shown(const RpcHttpException(503, 'x')),
          'http:503|Service Unavailable');
      presenter.log.clear();
      expect(await shown(const RpcHttpException(418, 'x')), 'http:418|');
    });
    test('RpcNetworkException: no code', () async {
      expect(await shown(const RpcNetworkException('Connection timed out')),
          'http:null|Connection timed out');
    });
    test('ConcurrencyException: unchanged simple message (A1)', () async {
      expect(await shown(const ConcurrencyException()), 'concurrency');
    });
    test('RpcProtocolException / other errors: application error', () async {
      expect(await shown(const RpcProtocolException('not JSON')),
          startsWith('app:not JSON|'));
      presenter.log.clear();
      expect(await shown(StateError('bad')), startsWith('app:Bad state: bad'));
    });
  });

  test('describe gives a short text for page placeholders', () {
    expect(ErrorHandler.describe(const UserError('Msg')), 'Msg');
    expect(ErrorHandler.describe(const RpcHttpException(404, 'x')),
        '[404] Not Found');
    expect(ErrorHandler.describe(const RpcServerException('boom', 'tb')),
        'boom');
  });

  group('DialogErrorPresenter', () {
    Future<DialogErrorPresenter> pump(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      return DialogErrorPresenter(ctx);
    }

    testWidgets('UserWarning dialog: Immer ignorieren / OK / Abbrechen',
        (tester) async {
      final p = await pump(tester);
      for (final (label, expected) in [
        ('Immer ignorieren', WarningChoice.always),
        ('OK', WarningChoice.ok),
        ('Abbrechen', WarningChoice.cancel),
      ]) {
        final f = p.userWarning('Warnung', 'Text');
        await tester.pumpAndSettle();
        expect(find.text('Warnung'), findsOneWidget);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(await f, expected);
      }
    });

    testWidgets('application error with expandable traceback',
        (tester) async {
      final p = await pump(tester);
      p.applicationError('boom', 'Traceback line 1');
      await tester.pumpAndSettle();
      expect(find.text('Anwendungsfehler'), findsOneWidget);
      expect(find.text('boom'), findsOneWidget);
      expect(find.text('Traceback line 1'), findsNothing);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Traceback line 1'), findsOneWidget);
    });

    testWidgets('HTTP error text', (tester) async {
      final p = await pump(tester);
      p.httpError(503, 'Service Unavailable');
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Fehler: „[503] Service Unavailable“. Bitte später erneut versuchen.'),
          findsOneWidget);
    });
  });
}

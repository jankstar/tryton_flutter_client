import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/rpc/rpc_exceptions.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';
import 'package:tryton_flutter_client/shared/dialogs/tryton_dialogs.dart';
import 'package:tryton_flutter_client/shared/errors/error_dialogs.dart';
import 'package:tryton_flutter_client/shared/errors/error_handler.dart';

/// The standard dialogs (spec 11.3, Python `common.*`).
void main() {
  /// A button that runs [onTap] with its context.
  Future<BuildContext> pump(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (c) {
        context = c;
        return const Scaffold();
      }),
    ));
    return context;
  }

  testWidgets('UserWarning: OK skips the warning and repeats the call, '
      'Always ignore with always=true, Cancel stops', (tester) async {
    final context = await pump(tester);
    final skipped = <(String, bool)>[];
    var calls = 0;
    final handler = ErrorHandler(
      presenter: DialogErrorPresenter(context),
      skipWarning: (name, always) async => skipped.add((name, always)),
    );
    // the server warns once, the repeated call succeeds
    Future<void> action() async {
      calls++;
      if (calls == 1) throw const UserWarning('w1', 'Check it', description: 'More');
    }

    final run = handler.run(action);
    await tester.pumpAndSettle();
    expect(find.text('Check it'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dialog-ok')));
    await tester.pumpAndSettle();
    expect(await run, isTrue);
    expect(calls, 2, reason: 'repeated after OK');
    expect(skipped, [('w1', false)]);

    calls = 0;
    final always = handler.run(action);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dialog-always')));
    await tester.pumpAndSettle();
    expect(await always, isTrue);
    expect(skipped.last, ('w1', true));

    calls = 0;
    final cancelled = handler.run(action);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dialog-cancel')));
    await tester.pumpAndSettle();
    expect(await cancelled, isFalse);
    expect(calls, 1, reason: 'not repeated');
  });

  testWidgets('Sur3: Yes / No / Cancel; closing is not possible by tapping '
      'outside', (tester) async {
    final context = await pump(tester);
    for (final (key, expected) in [
      ('dialog-yes', Sur3Choice.yes),
      ('dialog-no', Sur3Choice.no),
      ('dialog-cancel', Sur3Choice.cancel),
    ]) {
      final answer = showSur3(context, 'This record has been modified');
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('This record has been modified'), findsOneWidget,
          reason: 'barrier not dismissible');
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pumpAndSettle();
      expect(await answer, expected);
    }
  });

  testWidgets('Selection: none → null, one option directly, several or '
      'alwaysAsk → the dialog (double click = OK)', (tester) async {
    final context = await pump(tester);
    expect(await showSelection<int>(context, null, {}), isNull);
    final one = await showSelection(context, null, {'Only': 1});
    expect(one?.value, 1);
    expect(find.byType(AlertDialog), findsNothing, reason: 'no dialog');

    final asked = showSelection(context, 'Template', {'Only': 1}, alwaysAsk: true);
    await tester.pumpAndSettle();
    expect(find.text('Template'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('dialog-ok'))).onPressed,
        isNull, reason: 'nothing chosen');
    await tester.tap(find.text('Only'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('dialog-ok')));
    await tester.pumpAndSettle();
    expect((await asked)?.value, 1);

    // sorted by label; a double click takes the entry
    final several = showSelection(context, null, {'b': 2, 'a': 1});
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('a')).dy,
        lessThan(tester.getTopLeft(find.text('b')).dy));
    await tester.tap(find.text('b'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('b'));
    await tester.pumpAndSettle();
    expect((await several)?.value, 2);
  });

  testWidgets('unique: the same kind of dialog is not opened twice',
      (tester) async {
    final context = await pump(tester);
    final first = showSur(context, 'First?');
    await tester.pumpAndSettle();
    expect(await showSur(context, 'Second?'), isFalse, reason: 'at once');
    await tester.pumpAndSettle();
    expect(find.text('Second?'), findsNothing);
    expect(openDialogKinds, contains('sur'));
    // another kind may open on top
    final ask = showAsk(context, 'Password?', password: true);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('dialog-ask'))).obscureText,
        isTrue);
    await tester.enterText(find.byKey(const ValueKey('dialog-ask')), 'secret');
    await tester.tap(find.descendant(
        of: find.ancestor(of: find.text('Password?'), matching: find.byType(AlertDialog)),
        matching: find.byKey(const ValueKey('dialog-ok'))));
    await tester.pumpAndSettle();
    expect(await ask, 'secret');
    await tester.tap(find.byKey(const ValueKey('dialog-ok')));
    await tester.pumpAndSettle();
    expect(await first, isTrue);
    expect(openDialogKinds, isEmpty);
  });

  testWidgets('Error: details expandable, „Report Bug“, Close', (tester) async {
    final context = await pump(tester);
    final shown = showApplicationError(context, 'KeyError: x', 'Traceback …');
    await tester.pumpAndSettle();
    expect(find.text('Application Error'), findsOneWidget);
    expect(find.text('KeyError: x'), findsOneWidget);
    expect(find.byKey(const ValueKey('dialog-report-bug')), findsOneWidget);
    expect(find.text('Traceback …'), findsNothing, reason: 'collapsed');
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Traceback …'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dialog-close')));
    await tester.pumpAndSettle();
    await shown;
  });
}

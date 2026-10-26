import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/model/concurrency.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';
import 'package:tryton_flutter_client/shared/widgets/concurrency_dialog.dart';

void main() {
  /// Opens the dialog and returns a getter for the chosen result.
  Future<ConcurrencyChoice? Function()> openDialog(WidgetTester tester) async {
    ConcurrencyChoice? result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showConcurrencyDialog(context),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('Cancel is the default action (Enter)', (tester) async {
    final result = await openDialog(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(result(), ConcurrencyChoice.cancel);
  });

  testWidgets('Escape counts as Cancel', (tester) async {
    final result = await openDialog(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(result(), ConcurrencyChoice.cancel);
  });

  testWidgets('Write Anyway must be chosen explicitly', (tester) async {
    final result = await openDialog(tester);
    await tester.tap(find.text('Write Anyway'));
    await tester.pumpAndSettle();
    expect(result(), ConcurrencyChoice.writeAnyway);
  });
}

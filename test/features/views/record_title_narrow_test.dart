import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/views/record_menu.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

/// The title with the record menu in a very narrow space (window made
/// narrow): no overflow.
void main() {
  testWidgets('18 px for title and arrow: no overflow', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 17.9,
            child: RecordTitleMenu(
                actions: const {}, title: const Text('Party, a long title')),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}

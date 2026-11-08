import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/model/field_definition.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';
import 'package:tryton_flutter_client/shared/widgets/field_widget.dart';

Future<void> pumpField(WidgetTester tester, FieldWidget w) =>
    tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: w),
      ),
    ));

FieldDefinition fd(String type) =>
    FieldDefinition.fromJson('f', {'type': type, 'string': 'Feld'});

void main() {
  testWidgets('char without widget is still a text input', (tester) async {
    await pumpField(tester, FieldWidget(field: fd('char'), value: 'x'));
    expect(find.byType(TextField), findsOneWidget);
  });
}

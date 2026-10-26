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
  for (final (type, widget) in [
    ('binary', null),
    ('dict', null),
    ('reference', null),
    ('multiselection', null),
    ('timedelta', null),
    ('time', null),
    ('binary', 'image'),
    ('binary', 'document'),
    ('text', 'richtext'),
    ('text', 'html'),
    ('char', 'color'),
    ('char', 'pyson'),
  ]) {
    testWidgets('$type/${widget ?? '-'} → read-only placeholder',
        (tester) async {
      String? changed;
      await pumpField(
        tester,
        FieldWidget(
          field: fd(type),
          value: {'some': 'value'},
          widgetOverride: widget,
          onChanged: (v) => changed = '$v',
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('Feld'), findsOneWidget);
      expect(find.textContaining('Wird noch nicht unterstützt'), findsOneWidget);
      expect(find.textContaining('f: ${widget ?? type}'), findsOneWidget);
      await tester.tap(find.textContaining('Wird noch nicht'));
      expect(changed, isNull);
    });
  }

  testWidgets('char without widget is still a text input', (tester) async {
    await pumpField(tester, FieldWidget(field: fd('char'), value: 'x'));
    expect(find.byType(TextField), findsOneWidget);
  });
}

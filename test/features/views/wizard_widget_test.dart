import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/core/wizard/wizard.dart';
import 'package:tryton_flutter_client/features/views/wizard_widget.dart';
import 'package:tryton_flutter_client/l10n/app_localizations.dart';

import '../../core/model/fake_rpc.dart';

/// Wizard dialog (spec 13): view with buttons, Escape = end-state button.
void main() {
  testWidgets('dialog shows the view; Escape runs the end state', (tester) async {
    final calls = <String>[];
    TrytonWizard wizard() => TrytonWizard(
          action: 'test.wiz',
          name: 'Check',
          session: fakeSession(FakeRpc()),
          rpc: (method, params, {context}) async {
            calls.add(method.split('.').last);
            return switch (method.split('.').last) {
              'create' => [1, 'start', 'end'],
              'execute' => {
                  'view': {
                    'fields_view': {
                      'model': 'test.wiz.start',
                      'type': 'form',
                      'arch': '<form><label name="name"/><field name="name"/></form>',
                      'fields': {
                        'name': {'type': 'char', 'string': 'Name'}
                      },
                    },
                    'buttons': [
                      {'state': 'end', 'string': 'Cancel'},
                      {'state': 'go', 'string': 'Go', 'default': true},
                    ],
                    'defaults': {'name': 'X'},
                    'values': <String, dynamic>{},
                    'state': 'start',
                  }
                },
              _ => null,
            };
          },
        );

    late TrytonWizard w;
    var finished = false;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              w = wizard();
              await runWizardDialog(context, w);
              finished = true;
            },
            child: const Text('Start'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(find.text('Check'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Go'), findsOneWidget,
        reason: 'default button is primary');
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget,
        reason: 'end-state button is a link');
    expect(find.text('X'), findsOneWidget, reason: 'defaults');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(calls, ['create', 'execute', 'delete']);
    expect(find.text('Check'), findsNothing, reason: 'dialog closed');
    expect(finished, isTrue);
    expect(w.done, isTrue);
  });

  testWidgets('unused grid columns collapse: group in <form col="10">',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Like real_estate.billing_unit.start: groups without colspan.
    final w = TrytonWizard(
      action: 'test.wiz',
      name: 'Run',
      session: fakeSession(FakeRpc()),
      rpc: (method, params, {context}) async => switch (method.split('.').last) {
        'create' => [1, 'start', 'end'],
        'execute' => {
            'view': {
              'fields_view': {
                'model': 'test.wiz.start',
                'type': 'form',
                'arch': '<form col="10"><group col="4" id="g" string="Selected">'
                    '<label name="company"/><field name="company" colspan="1"/>'
                    '</group><newline/><group col="4" id="g2" string="Run">'
                    '<label name="date"/><field name="date"/></group></form>',
                'fields': {
                  'company': {'type': 'char', 'string': 'Company'},
                  'date': {'type': 'date', 'string': 'Date'},
                },
              },
              'buttons': [
                {'state': 'end', 'string': 'Cancel'}
              ],
              'state': 'start',
            }
          },
        _ => null,
      },
    );
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => runWizardDialog(context, w),
            child: const Text('Start'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    final dialog = tester.getSize(find
        .descendant(of: find.byType(Dialog), matching: find.byType(Material))
        .first);
    for (final e in find.byType(InputDecorator).evaluate()) {
      expect((e.renderObject as RenderBox).size.width,
          greaterThan(dialog.width * 0.8),
          reason: 'not 1/10 of the width');
    }
  });
}

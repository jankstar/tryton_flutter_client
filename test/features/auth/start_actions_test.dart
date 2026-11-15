import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/app.dart';
import 'package:tryton_flutter_client/core/session/session.dart';
import 'package:tryton_flutter_client/core/session/session_store.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';
import 'package:tryton_flutter_client/features/shell/app_shell.dart';
import 'package:tryton_flutter_client/features/shell/shell_context.dart';
import 'package:tryton_flutter_client/features/views/wizard_widget.dart';

import '../views/form_harness.dart';

class _NoStore implements SessionStore {
  @override
  Future<StoredSession?> read([String? key]) async => null;
  @override
  Future<void> write(StoredSession session) async {}
  @override
  Future<void> delete([String? key]) async {}
}

/// A stored session that is valid (restart with a saved token).
class _RestoredSession extends TrytonSession {
  _RestoredSession(FakeFormRpc rpc) : super(rpcClient: rpc, store: _NoStore());
  @override
  Future<bool> restore([String? key]) async => true;
}

Map<String, dynamic> _view(String state, String model, String text,
        List<Map<String, dynamic>> buttons) =>
    {
      'view': {
        'fields_view': {
          'model': model,
          'type': 'form',
          'arch': '<form><label string="$text"/></form>',
          'fields': <String, dynamic>{},
        },
        'buttons': buttons,
        'defaults': <String, dynamic>{},
        'values': <String, dynamic>{},
        'state': state,
      }
    };

/// Start actions of the preferences (spec 3.2 step 4): the module
/// configuration of a new database starts after the restored session's
/// shell is built, its step „Configure Company“ opens on top, and the
/// end reloads the menu.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('restored session: config wizard after the shell, next step, '
      'menu reloaded', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final events = <String>[];
    late FakeFormRpc rpc;
    rpc = FakeFormRpc({
      'model.res.user.get_preferences': (p) {
        if (p.firstOrNull == false) events.add('get_preferences');
        return {
          'actions': [5],
          'language': 'en',
        };
      },
      'model.ir.action.get_action_value': (p) {
        events.add('get_action_value ${p.first}');
        expect(shellContext.value?.mounted, isTrue,
            reason: 'the shell is built before the start action');
        return {
          'id': 5,
          'type': 'ir.action.wizard',
          'name': 'Module Configuration',
          'wiz_name': 'ir.module.config_wizard',
          'window': true,
        };
      },
      'wizard.ir.module.config_wizard.create': (_) => [1, 'start', 'end'],
      'wizard.ir.module.config_wizard.execute': (p) {
        final state = p[2];
        events.add('config execute $state');
        if (state == 'start') {
          return _view('first', 'ir.module.config_wizard.first', 'Welcome', [
            {'state': 'end', 'string': 'Cancel'},
            {'state': 'action', 'string': 'OK', 'default': true},
          ]);
        }
        return {
          ..._view('other', 'ir.module.config_wizard.other', 'Next step', [
            {'state': 'end', 'string': 'Cancel'},
            {'state': 'action', 'string': 'Next', 'default': true},
          ]),
          'actions': [
            [
              {
                'id': 9,
                'type': 'ir.action.wizard',
                'name': 'Configure Company',
                'wiz_name': 'company.company.config',
                'window': true,
              },
              <String, dynamic>{}
            ]
          ],
        };
      },
      'wizard.ir.module.config_wizard.delete': (_) {
        events.add('config delete');
        return 'reload menu';
      },
      'wizard.company.company.config.create': (_) => [2, 'start', 'end'],
      'wizard.company.company.config.execute': (p) {
        events.add('company execute ${p[2]}');
        // the wizard keys of the module configuration are removed
        final context = rpc.calls.last.context;
        expect(context['active_model'], isNull);
        expect(context['active_ids'], isEmpty);
        return _view('start', 'company.company.config.start', 'Company', [
          {'state': 'end', 'string': 'Cancel'},
        ]);
      },
      'wizard.company.company.config.delete': (_) {
        events.add('company delete');
        return 'reload context';
      },
    });
    final svc = ModelService(
        rpc: rpc, getContext: () => {'language': 'en'}, getDatabase: () => 'test');
    await tester.pumpWidget(ProviderScope(
      overrides: [
        rpcClientProvider.overrideWithValue(rpc),
        modelServiceProvider.overrideWithValue(svc),
        sessionProvider.overrideWithValue(_RestoredSession(rpc)),
      ],
      child: const TrytonFlutterClientApp(),
    ));
    await pumpFrames(tester, 40);
    expect(tester.takeException(), isNull);

    expect(find.byType(AppShell), findsOneWidget);
    expect(events.take(3), [
      'get_preferences',
      'get_action_value 5',
      'config execute start',
    ]);
    expect(find.text('Welcome'), findsOneWidget,
        reason: 'window wizard: a tab of the shell');

    await tester.tap(find.text('OK'));
    await pumpFrames(tester, 40);
    expect(events, contains('company execute start'));
    expect(find.byType(WizardWidget, skipOffstage: false), findsNWidgets(2),
        reason: 'the next step opens on top, the configuration stays');
    expect(find.text('Company'), findsOneWidget);

    // end of „Configure Company“, then of the configuration
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await pumpFrames(tester, 40);
    expect(events, contains('company delete'));
    expect(find.text('Next step'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await pumpFrames(tester, 40);
    expect(find.byType(WizardWidget, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);

    expect(events.where((e) => e.startsWith('get_action_value')).length, 1,
        reason: 'the start action ran exactly once');
    // „reload context“ and „reload menu“ load the preferences again – the
    // reload runs no start action
    expect(events.where((e) => e == 'get_preferences').length, 3);
    expect(events.indexOf('config delete'),
        greaterThan(events.indexOf('company delete')));
  });
}

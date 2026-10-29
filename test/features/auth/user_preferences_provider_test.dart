import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/auth/user_preferences_provider.dart';
import 'package:tryton_flutter_client/features/model/model_service.dart';

import '../views/form_harness.dart';

/// The user chip shows the user of the current login, not the one before
/// (the session object stays the same across logins).
void main() {
  test('logout and login as another user loads the new name', () async {
    final rpc = FakeFormRpc({
      'model.res.user.read': (p) => [
            {
              'id': (p[0] as List).first,
              'name': (p[0] as List).first == 1 ? 'Administrator' : 'Jan',
            }
          ],
    });
    final container = ProviderContainer(overrides: [
      rpcClientProvider.overrideWithValue(rpc),
      modelServiceProvider.overrideWith((ref) => ModelService(
          rpc: rpc, getContext: () => const {}, getDatabase: () => 'test')),
    ]);
    addTearDown(container.dispose);
    final session = container.read(sessionProvider);
    final auth = container.read(authProvider.notifier);
    final sub = container.listen(userPreferencesProvider, (_, _) {});
    addTearDown(sub.close);

    void loginAs(int userId) {
      session.userId = userId;
      // ignore: invalid_use_of_protected_member
      auth.state = const AuthState(status: AuthStatus.authenticated);
    }

    loginAs(1);
    expect((await container.read(userPreferencesProvider.future))?.name,
        'Administrator');

    // Logout as in the app: session cleared, state unauthenticated.
    session.userId = null;
    // ignore: invalid_use_of_protected_member
    auth.state = const AuthState();
    expect(await container.read(userPreferencesProvider.future), isNull);

    loginAs(7);
    expect((await container.read(userPreferencesProvider.future))?.name, 'Jan');
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tryton_flutter_client/features/auth/auth_provider.dart';
import 'package:tryton_flutter_client/features/auth/user_preferences_provider.dart';

import '../views/form_harness.dart';

/// The user chip comes from `get_preferences(false)` of the current login
/// (B10): another user after logout/login shows the new status bar.
void main() {
  test('status bar and avatar of the preferences, cleared at logout', () {
    final rpc = FakeFormRpc({})..baseUrl = 'http://127.0.0.1:8000';
    final container = ProviderContainer(overrides: [
      rpcClientProvider.overrideWithValue(rpc),
    ]);
    addTearDown(container.dispose);
    final prefs = container.read(preferencesProvider.notifier);

    prefs.state = {
      'status_bar': 'Administrator [EUR]',
      'avatar_url': 'avatar/dHJ5dG9u/57c4',
    };
    final admin = container.read(userPreferencesProvider)!;
    expect(admin.statusBar, 'Administrator [EUR]');
    expect(admin.name, 'Administrator');
    expect(admin.initials, 'A');
    // Relative to the server root (GET), not to <db>/ (405).
    expect(admin.avatarUrl, 'http://127.0.0.1:8000/avatar/dHJ5dG9u/57c4');

    prefs.state = null; // logout
    expect(container.read(userPreferencesProvider), isNull);

    prefs.state = {'status_bar': 'Jan Kramer'};
    expect(container.read(userPreferencesProvider)!.initials, 'JK');
    expect(container.read(userPreferencesProvider)!.avatarUrl, isNull);
  });
}

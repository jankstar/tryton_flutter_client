import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tryton_flutter_client/core/theme/app_theme.dart';
import 'package:tryton_flutter_client/core/theme/theme_provider.dart';

/// The app theme: Polar Fox at the first start, then the chosen one.
void main() {
  Future<AppTheme> themeAtStart() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(themeProvider);
    await Future<void>.delayed(Duration.zero);
    return container.read(themeProvider);
  }

  test('first start: Polar Fox', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await themeAtStart(), AppTheme.polarFox);
  });

  test('a chosen theme is kept', () async {
    SharedPreferences.setMockInitialValues({themePrefKey: 'blackMamba'});
    expect(await themeAtStart(), AppTheme.blackMamba);
  });
}

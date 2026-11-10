import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

const themePrefKey = 'tryton_app_theme';

/// Theme of the first start (nothing chosen yet).
const defaultAppTheme = AppTheme.polarFox;

/// The app theme: the chosen one (`tryton_app_theme`), else
/// [defaultAppTheme].
class ThemeNotifier extends StateNotifier<AppTheme> {
  ThemeNotifier() : super(defaultAppTheme) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(themePrefKey);
    if (raw == null) return;
    final match = AppTheme.values.where((t) => t.name == raw).firstOrNull;
    if (match != null) state = match;
  }

  Future<void> setTheme(AppTheme theme) async {
    state = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(themePrefKey, theme.name);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, AppTheme>(
  (_) => ThemeNotifier(),
);

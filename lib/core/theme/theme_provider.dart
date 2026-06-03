import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

const _kThemeKey = 'tryton_app_theme';

class ThemeNotifier extends StateNotifier<AppTheme> {
  ThemeNotifier() : super(AppTheme.blackMamba) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kThemeKey);
    if (raw == null) return;
    final match = AppTheme.values.where((t) => t.name == raw).firstOrNull;
    if (match != null) state = match;
  }

  Future<void> setTheme(AppTheme theme) async {
    state = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, theme.name);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, AppTheme>(
  (_) => ThemeNotifier(),
);

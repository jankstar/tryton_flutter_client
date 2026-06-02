import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';

// ─── Supported locales ────────────────────────────────────────────────────────

const supportedLocales = [
  Locale('en'),
  Locale('de'),
  Locale('fr'),
  Locale('es'),
  Locale('pt'),
  Locale('pl'),
  Locale('da'),
  Locale('nl'),
  Locale('sv'),
  Locale('fi'),
  Locale('ru'),
];

/// Human-readable names for the supported locales.
const localeNames = {
  'en': 'English',
  'de': 'Deutsch',
  'fr': 'Français',
  'es': 'Español',
  'pt': 'Português',
  'pl': 'Polski',
  'da': 'Dansk',
  'nl': 'Nederlands',
  'sv': 'Svenska',
  'fi': 'Suomi',
  'ru': 'Русский',
};

const _prefKey = 'app_locale';

// ─── Provider ─────────────────────────────────────────────────────────────────

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en')) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKey);
    if (code != null) {
      final match = supportedLocales.where((l) => l.languageCode == code).firstOrNull;
      if (match != null && mounted) state = match;
    }
  }

  /// Persist locale – called after login when the server language is applied.
  Future<void> setLocale(Locale locale) async {
    if (!mounted) return;
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, locale.languageCode);
  }

  /// Apply a Tryton language code (e.g. "de_DE", "en_US", "fr") to the app
  /// locale and persist it. Falls back to 'en' if unsupported.
  Future<void> applyServerLanguage(String? trytonCode) async {
    if (trytonCode == null || trytonCode.isEmpty) return;
    // Tryton uses "de_DE" / "en_US" – extract the language part.
    final langCode = trytonCode.split('_').first.toLowerCase();
    final match = supportedLocales
        .where((l) => l.languageCode == langCode)
        .firstOrNull;
    await setLocale(match ?? const Locale('en'));
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>(
  (ref) => LocaleNotifier(),
);

// ─── BuildContext extension ───────────────────────────────────────────────────

extension L10nExt on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

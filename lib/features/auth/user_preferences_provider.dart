import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

/// The user chip of the preferences (spec 3.2 step 6, SAO `user_menu`):
/// `status_bar` (name, company, currency) and the avatar.
class UserPreferences {
  /// `status_bar`, e.g. "Administrator [EUR]".
  final String statusBar;

  /// Absolute URLs of the avatar and its badge (GET), or null.
  final String? avatarUrl;
  final String? avatarBadgeUrl;

  const UserPreferences(
      {required this.statusBar, this.avatarUrl, this.avatarBadgeUrl});

  /// Name without the bracketed part of the status bar.
  String get name {
    final i = statusBar.indexOf(' [');
    return i > 0 ? statusBar.substring(0, i) : statusBar;
  }

  /// Initials for the avatar circle (e.g. "JK" for "Jan Kramer").
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts.first.isNotEmpty && parts.last.isNotEmpty) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  /// From `get_preferences(false)`; relative avatar URLs are resolved
  /// against the server root ([serverUrl]) – they are no RPC paths, and
  /// the endpoint only answers GET (POST/`<db>/…` give 405).
  factory UserPreferences.fromPreferences(
      Map<String, dynamic> preferences, String serverUrl) {
    String? absolute(dynamic url) {
      if (url is! String || url.isEmpty) return null;
      final uri = Uri.parse(url);
      if (uri.hasScheme) return url;
      return Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/')
          .resolve(url)
          .toString();
    }

    return UserPreferences(
      statusBar: '${preferences['status_bar'] ?? ''}',
      avatarUrl: absolute(preferences['avatar_url']),
      avatarBadgeUrl: absolute(preferences['avatar_badge_url']),
    );
  }
}

// ─── Providers ────────────────────────────────────────────────────────────────

/// `res.user.get_preferences(false)` of the session (set by the
/// SessionBootstrap, null when logged out).
final preferencesProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

/// The user chip from [preferencesProvider]; follows each login/logout.
final userPreferencesProvider = Provider<UserPreferences?>((ref) {
  final preferences = ref.watch(preferencesProvider);
  if (preferences == null) return null;
  return UserPreferences.fromPreferences(
      preferences, ref.read(rpcClientProvider).baseUrl);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/utils/number_format_utils.dart';
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

  /// Counts the loads of the preferences: part of the image URLs, so a
  /// new avatar is fetched again – the server keeps the URL (same
  /// `ir.avatar` uuid) when the image changes, and Flutter caches images
  /// by URL.
  final int revision;

  const UserPreferences(
      {required this.statusBar,
      this.avatarUrl,
      this.avatarBadgeUrl,
      this.revision = 0});

  /// [url] of an avatar image in [size] pixels for this load.
  static String imageUrl(String url, int size, int revision) =>
      '$url?s=$size&v=$revision';

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
      Map<String, dynamic> preferences, String serverUrl,
      {int revision = 0}) {
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
      revision: revision,
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
      preferences, ref.read(rpcClientProvider).baseUrl,
      revision: ++_preferencesRevision);
});

/// Number of the preferences loaded (see [UserPreferences.revision]).
int _preferencesRevision = 0;

/// Number format of `preferences.locale` (spec 15.1/15.4); null without
/// preferences – the widgets then use the app locale.
final numberLocaleProvider = Provider<NumberLocale?>((ref) =>
    NumberLocale.fromPreferences(ref.watch(preferencesProvider)?['locale']));

/// Date format (strftime) of `preferences.locale.date` (spec 15.2),
/// default `%x`.
final dateFormatProvider = Provider<String>((ref) {
  final locale = ref.watch(preferencesProvider)?['locale'];
  final date = locale is Map ? locale['date'] : null;
  return date is String && date.isNotEmpty ? date : '%x';
});

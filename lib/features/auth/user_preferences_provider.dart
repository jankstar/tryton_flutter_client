import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/model_service.dart';
import 'auth_provider.dart';

// ─── Data model ───────────────────────────────────────────────────────────────

class UserPreferences {
  final String name;
  final String? currency;

  const UserPreferences({required this.name, this.currency});

  String get statusBar =>
      currency != null ? '$name ($currency)' : name;

  /// Initials for the avatar circle (e.g. "JK" for "Jan Kramer").
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

// ─── Session-level cache (one load per login session) ────────────────────────

UserPreferences? _cachedPrefs;
int? _cachedUserId;

void clearUserPreferencesCache() {
  _cachedPrefs = null;
  _cachedUserId = null;
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final userPreferencesProvider =
    FutureProvider<UserPreferences?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (!session.isLoggedIn) {
    clearUserPreferencesCache();
    return null;
  }

  final userId = session.userId;
  if (userId == null || userId <= 0) return null;

  // Return cached value if the user hasn't changed
  if (_cachedUserId == userId && _cachedPrefs != null) {
    return _cachedPrefs;
  }

  try {
    final svc = ref.read(modelServiceProvider);

    // Load name from res.user (single clean RPC call)
    final users = await svc.read('res.user', [userId], ['name', 'rec_name']);
    final name = users.isNotEmpty
        ? (users.first['name']?.toString() ??
            users.first.recName)
        : 'User #$userId';

    // Try to get currency from the session context (set after login)
    String? currency;
    try {
      final ctxCurrency = session.context['currency'];
      if (ctxCurrency != null && ctxCurrency != false) {
        currency = ctxCurrency.toString();
      }
    } catch (_) {
      // Currency is optional
    }

    final prefs = UserPreferences(name: name, currency: currency);
    _cachedUserId = userId;
    _cachedPrefs = prefs;
    return prefs;
  } catch (_) {
    return UserPreferences(name: 'User #$userId');
  }
});

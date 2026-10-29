import 'package:flutter/widgets.dart' show TextDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/session/session.dart';
import '../actions/action_service.dart';
import '../model/metadata_service.dart';
import '../model/model_service.dart';
import 'auth_provider.dart';
import 'user_preferences_provider.dart';

/// Writing direction of the user's language (`language_direction`).
final textDirectionProvider =
    StateProvider<TextDirection>((ref) => TextDirection.ltr);

/// Start sequence after login (spec 3.2, SAO `get_preferences`):
/// 1. `reload_context`;
/// 2. `res.user.get_preferences(false)` → preferences;
/// 3. metadata caches (B12, in parallel);
/// 4. start actions of `preferences.actions` one after another;
/// 5. language, locale and writing direction; MODELNAME cleared;
/// 6. menu (`pyson_menu`) and user chip (`status_bar`, avatar) from the
///    preferences.
class SessionBootstrap {
  final TrytonSession session;
  final ModelService svc;
  final MetadataService metadata;

  /// Runs a start action (an action id).
  final Future<void> Function(int actionId) runAction;

  /// Applies language and direction (`language`, `language_direction`).
  final Future<void> Function(String? language, String? direction)
      applyLanguage;

  /// Publishes the preferences (menu and user chip are built from them).
  final void Function(Map<String, dynamic>? preferences) publish;

  SessionBootstrap({
    required this.session,
    required this.svc,
    required this.metadata,
    required this.runAction,
    required this.applyLanguage,
    required this.publish,
  });

  Future<Map<String, dynamic>> _preferences() async {
    final result = await svc.execute<dynamic>(
        'res.user', 'get_preferences', [false],
        processException: false);
    return result is Map ? Map<String, dynamic>.from(result) : {};
  }

  static Map<String, dynamic>? _locale(Map<String, dynamic> preferences) {
    final locale = preferences['locale'];
    return locale is Map ? Map<String, dynamic>.from(locale) : null;
  }

  /// The whole sequence (login, restored session).
  Future<Map<String, dynamic>> run() async {
    await session.reloadContext();
    final preferences = await _preferences();
    await metadata.load(locale: _locale(preferences) ?? const {});
    for (final id in (preferences['actions'] as List? ?? const [])) {
      if (id is! int) continue;
      try {
        await runAction(id);
      } catch (_) {
        // a failing start action does not stop the start
      }
    }
    await applyLanguage(preferences['language'] as String?,
        preferences['language_direction'] as String?);
    metadata.clearNames();
    publish(preferences);
    return preferences;
  }

  /// After a context change (`reload context`, `reload menu`, saved user
  /// preferences): context, preferences, language, menu and user chip
  /// again.
  Future<Map<String, dynamic>> reload() async {
    await session.reloadContext();
    final preferences = await _preferences();
    metadata.locale = _locale(preferences);
    await applyLanguage(preferences['language'] as String?,
        preferences['language_direction'] as String?);
    metadata.clearNames();
    publish(preferences);
    return preferences;
  }

  /// Logout: preferences (menu, user chip) and metadata are cleared.
  void clear() {
    publish(null);
    metadata.clear();
  }
}

final Provider<SessionBootstrap> sessionBootstrapProvider =
    Provider<SessionBootstrap>((ref) {
  final svc = ref.read(modelServiceProvider);
  return SessionBootstrap(
    session: ref.read(sessionProvider),
    svc: svc,
    metadata: ref.read(metadataServiceProvider),
    runAction: (id) => ref.read(actionServiceProvider).execute(id),
    applyLanguage: (language, direction) async {
      await ref.read(localeProvider.notifier).applyServerLanguage(language);
      ref.read(textDirectionProvider.notifier).state =
          direction == 'rtl' ? TextDirection.rtl : TextDirection.ltr;
    },
    publish: (preferences) =>
        ref.read(preferencesProvider.notifier).state = preferences,
  );
});

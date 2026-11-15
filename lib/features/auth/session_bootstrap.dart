import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show TextDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/tryton_icon.dart' show IconFactory;
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' show FloatField;
import '../../core/session/session.dart';
import '../actions/action_service.dart';
import '../model/metadata_service.dart';
import '../model/model_service.dart';
import '../notifications/notifications.dart' show notificationCenterProvider;
import '../shell/shell_context.dart';
import '../../shared/errors/error_dialogs.dart' show showErrorDialog;
import '../views/record_field_widgets.dart' show clearMany2OneSelectionCache;
import '../views/list_view_screen.dart' show clearListCaches;
import '../views/record_link.dart';
import 'auth_provider.dart';
import 'user_preferences_provider.dart';

/// Writing direction of the user's language (`language_direction`).
final textDirectionProvider =
    StateProvider<TextDirection>((ref) => TextDirection.ltr);

/// Start sequence after login and for a restored session (spec 3.2,
/// Python `Main.get_preferences`, SAO `get_preferences`):
/// 1. `reload_context`;
/// 2. `res.user.get_preferences(false)` → preferences;
/// 3. metadata caches (B12, in parallel);
/// 5. language, locale and writing direction; MODELNAME cleared;
/// 6. menu (`pyson_menu`) and user chip (`status_bar`, avatar) from the
///    preferences;
/// 8. bus: `notification:<user_id>`, notification counter, polling;
/// 4. (spec step 4, run last) once the shell is built the start actions of
///    `preferences.actions` one after another (Python: menu first, then
///    `Action.execute(action_id, {})`; e.g. the module configuration
///    `ir.module.config_wizard` of a new database). A failing start action
///    is logged and shown ([showError]); the following ones still run.
class SessionBootstrap {
  final TrytonSession session;
  final ModelService svc;
  final MetadataService metadata;

  /// Runs a start action (an action id) on the shell; errors reach the
  /// caller.
  final Future<void> Function(int actionId) runAction;

  /// Completes with true once the shell (menu, tabs, its Navigator) is
  /// built; false: it did not appear, the start actions are skipped.
  final Future<bool> Function() shellReady;

  /// Shows the error of a start action (error handler dialog).
  final Future<void> Function(Object error) showError;

  /// Applies language and direction (`language`, `language_direction`).
  final Future<void> Function(String? language, String? direction)
      applyLanguage;

  /// Publishes the preferences (menu and user chip are built from them).
  final void Function(Map<String, dynamic>? preferences) publish;

  /// Step 8 (bus, notifications) after the start; stopped by [clear].
  final Future<void> Function() startServices;
  final void Function() stopServices;

  /// Diagnostics (start actions, their errors).
  final void Function(String message) log;

  static Future<void> _none() async {}
  static void _noop() {}
  static Future<bool> _ready() async => true;
  static Future<void> _ignore(Object error) async {}
  static void _debugLog(String message) => debugPrint(message);

  SessionBootstrap({
    required this.session,
    required this.svc,
    required this.metadata,
    required this.runAction,
    required this.applyLanguage,
    required this.publish,
    this.shellReady = _ready,
    this.showError = _ignore,
    this.startServices = _none,
    this.stopServices = _noop,
    this.log = _debugLog,
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

  /// The whole sequence (login, restored session). Completes after the
  /// start actions (a start wizard: when it has ended).
  Future<Map<String, dynamic>> run() async {
    await session.reloadContext();
    final preferences = await _preferences();
    final actions = [
      for (final id in (preferences['actions'] as List? ?? const []))
        if (id is int) id
    ];
    log('start actions (get_preferences.actions): '
        '${preferences['actions'] ?? '[]'}');
    // metadata and the icon names of the server in parallel (Python
    // `get_preferences`: IconFactory.load_icons, MODELACCESS, …)
    IconFactory.setService(svc);
    await Future.wait([
      metadata.load(locale: _locale(preferences) ?? const {}),
      IconFactory.loadIcons(),
    ]);
    await applyLanguage(preferences['language'] as String?,
        preferences['language_direction'] as String?);
    metadata.clearNames();
    publish(preferences);
    try {
      await startServices();
    } catch (_) {
      // the bus is optional (spec 2.10 SOLL)
    }
    await _runStartActions(actions);
    return preferences;
  }

  /// Step 4 on the built shell, one action after another (SAO: a promise
  /// chain); not for [reload] (the Python client runs them only at the
  /// start).
  Future<void> _runStartActions(List<int> actions) async {
    if (actions.isEmpty) return;
    if (!await shellReady()) {
      log('start actions skipped: the shell was not built');
      return;
    }
    for (final id in actions) {
      try {
        await runAction(id);
      } catch (e, stack) {
        log('start action $id failed: $e\n$stack');
        try {
          await showError(e);
        } catch (_) {
          // the next start action still runs
        }
      }
    }
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
    clearLinkActionCache();
    clearMany2OneSelectionCache();
    publish(preferences);
    return preferences;
  }

  /// Logout: preferences (menu, user chip) and metadata are cleared.
  void clear() {
    stopServices();
    IconFactory.clear();
    IconFactory.setService(null);
    publish(null);
    metadata.clear();
    clearLinkActionCache();
    FloatField.clearCaches();
    clearMany2OneSelectionCache();
    clearListCaches();
  }
}

final Provider<SessionBootstrap> sessionBootstrapProvider =
    Provider<SessionBootstrap>((ref) {
  final svc = ref.read(modelServiceProvider);
  return SessionBootstrap(
    session: ref.read(sessionProvider),
    svc: svc,
    metadata: ref.read(metadataServiceProvider),
    // start actions on the shell: wizards as dialog or tab of the shell
    runAction: (id) {
      final context = shellContext.value;
      if (context == null || !context.mounted) {
        throw StateError('start action $id: no shell');
      }
      return ref
          .read(actionServiceProvider)
          .execute(id, ui: DialogActionUi(context));
    },
    shellReady: () async => await waitForShell() != null,
    showError: (error) async {
      final context = shellContext.value;
      if (context != null && context.mounted) {
        await showErrorDialog(context, error);
      }
    },
    applyLanguage: (language, direction) async {
      await ref.read(localeProvider.notifier).applyServerLanguage(language);
      ref.read(textDirectionProvider.notifier).state =
          direction == 'rtl' ? TextDirection.rtl : TextDirection.ltr;
    },
    publish: (preferences) =>
        ref.read(preferencesProvider.notifier).state = preferences,
    startServices: () => ref.read(notificationCenterProvider).start(),
    stopServices: () => ref.read(notificationCenterProvider).stop(),
  );
});

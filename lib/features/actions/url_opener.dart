import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/screen/screen.dart';
import '../../core/screen/tryton_url.dart';
import '../../core/session/profiles.dart';
import '../../shared/dialogs/tryton_dialogs.dart';
import '../auth/auth_provider.dart';
import '../model/model_service.dart';
import '../shell/tab_manager.dart';
import '../tabs/user_chip.dart';
import 'action_service.dart';

/// A `tryton://` URL to open after the next login (the profile was
/// switched for it, spec 12.7).
final pendingTrytonUrlProvider = StateProvider<String?>((ref) => null);

/// The URL belongs to the session open now: same database, same host and
/// (when the URL names one) port.
bool urlMatchesSession(TrytonUrl url, String baseUrl, String? database) {
  final uri = Uri.parse(baseUrl);
  return url.database == database &&
      url.host == uri.host &&
      (url.port == null || url.port == uri.port);
}

/// The profile serving [url] (host, port when given, database).
ConnectionProfile? profileFor(TrytonUrl url, List<ConnectionProfile> profiles) {
  for (final p in profiles) {
    final uri = Uri.tryParse(p.serverUrl);
    if (uri == null) continue;
    if (p.database == url.database &&
        uri.host == url.host &&
        (url.port == null || uri.port == url.port)) {
      return p;
    }
  }
  return null;
}

/// Opens a `tryton://` URL (spec 12.7, Python `Main._open_url`): `model`
/// as a tab (with an id the form first), `wizard`, `report`, `url`.
/// Malformed URLs and parameters are ignored silently. A URL of another
/// database or server proposes the matching profile: logout, the profile
/// preselected, the URL opened after the login. Returns whether the URL
/// was a tryton URL.
Future<bool> openTrytonUrl(BuildContext context, WidgetRef ref, String text,
    {ProfileStore? profileStore}) async {
  final url = TrytonUrl.parse(text);
  if (url == null) return false;
  final session = ref.read(sessionProvider);
  if (!urlMatchesSession(url, session.rpcClient.baseUrl, session.database)) {
    final store = profileStore ?? ProfileStore();
    final profile = profileFor(url, await store.load());
    if (!context.mounted) return true;
    final l = context.l10n;
    if (profile == null) {
      await showMessage(context, l.urlNoProfile(url.target));
      return true;
    }
    if (!await showSur(context, l.urlOtherProfile(url.target, profile.name))) {
      return true;
    }
    await store.setLast(profile.name);
    ref.read(pendingTrytonUrlProvider.notifier).state = text.trim();
    if (context.mounted) await signOut(context, ref);
    return true;
  }
  try {
    switch (url.type) {
      case 'model':
        final attributes = url.modelAttributes();
        if (attributes == null) return true;
        var title = url.name;
        if (title.isEmpty) {
          title = await ref
                  .read(modelServiceProvider)
                  .metadata
                  ?.name(attributes.model) ??
              attributes.model;
        }
        ref.read(tabsProvider.notifier).openTab(title: title, attributes: attributes);
      case 'wizard':
        if (url.path.isEmpty || !context.mounted) return true;
        final name = url.name;
        await ref.read(actionServiceProvider).execAction({
          'type': 'ir.action.wizard',
          'wiz_name': url.path,
          'name': name.isEmpty ? url.path : name,
          'window': url.value('window', false) == true,
        },
            data: Map<String, dynamic>.from(url.value('data', const {}) as Map),
            context: Map<String, dynamic>.from(url.value('context', const {}) as Map),
            ui: DialogActionUi(context));
      case 'report':
        if (url.path.isEmpty || !context.mounted) return true;
        await ref.read(actionServiceProvider).execAction({
          'type': 'ir.action.report',
          'report_name': url.path,
          'name': url.path,
          'direct_print': url.value('direct_print', false) == true,
        },
            data: Map<String, dynamic>.from(url.value('data', const {}) as Map),
            context: Map<String, dynamic>.from(url.value('context', const {}) as Map),
            ui: DialogActionUi(context));
      case 'url':
        final target = url.value('url', false);
        if (target is String && target.isNotEmpty) {
          final uri = Uri.tryParse(target);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
    }
  } catch (_) {
    // malformed parameters or a failing action: ignored (Python
    // „Prevent crashing the client“)
  }
  return true;
}

/// „Copy URL“ (spec 10.3, Python `Form.url_copy`): the `tryton://` URL of
/// [screen] (8.9) with the tab name [name] in the clipboard.
Future<void> copyScreenUrl(BuildContext context, WidgetRef ref,
    TrytonScreen screen, String name) async {
  final session = ref.read(sessionProvider);
  final url = screenUrl(screen,
      baseUrl: session.rpcClient.baseUrl,
      database: session.database ?? '',
      name: name);
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(context.l10n.urlCopied)));
}

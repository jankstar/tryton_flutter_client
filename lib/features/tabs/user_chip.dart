import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_provider.dart';
import '../auth/auth_provider.dart';
import '../auth/preferences_dialog.dart';
import '../auth/user_preferences_provider.dart';
import '../notifications/notifications.dart';
import '../shell/tab_manager.dart';
import '../views/record_menu.dart';
import '../shell/about_dialog.dart';
import '../actions/action_service.dart' show DialogActionUi;

// ─── User chip (top-right like SAO) ──────────────────────────────────────────

enum _UserMenuItem { preferences, help, shortcuts, about, themes, logout }

class UserChip extends ConsumerWidget {
  const UserChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The user chip of get_preferences(false) (spec 3.2 step 6).
    final prefs = ref.watch(userPreferencesProvider);
    // notification bell next to the user menu (spec 14.1)
    // narrow: the name is shortened instead of overflowing the tab bar
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const NotificationButton(),
      Flexible(child: _buildMenu(context, ref, prefs, context.l10n)),
    ]);
  }

  Widget _buildMenu(BuildContext context, WidgetRef ref,
      UserPreferences? prefs, dynamic l) {
    final userId = ref.read(sessionProvider).userId;
    return PopupMenuButton<_UserMenuItem>(
      position: PopupMenuPosition.under,
      // Override the Flutter default tooltip ("Show menu" / "Menü anzeigen")
      tooltip: prefs?.statusBar ?? l.signOut,
      onSelected: (item) async {
        switch (item) {
          case _UserMenuItem.preferences:
            // dialog of get_preferences_fields_view (spec 3.3)
            if (userId != null && userId > 0 && context.mounted) {
              await showPreferencesDialog(context, ref);
            }
          case _UserMenuItem.help:
            // the documentation of the series (Python `open_documentation`)
            if (context.mounted) {
              await DialogActionUi(context).openUrl(documentationUrl());
            }
          case _UserMenuItem.about:
            if (context.mounted) await showAboutTryton(context);
          case _UserMenuItem.shortcuts:
            if (context.mounted) await showShortcutsHelp(context);
          case _UserMenuItem.themes:
            if (context.mounted) {
              await showDialog<void>(
                context: context,
                builder: (_) => _ThemePickerDialog(ref: ref),
              );
            }
          case _UserMenuItem.logout:
            await signOut(context, ref);
        }
      },
      itemBuilder: (ctx) => [
        // ── User info header (not selectable) ──────────────────────────
        PopupMenuItem<_UserMenuItem>(
          enabled: false,
          child: _UserHeader(prefs: prefs),
        ),
        const PopupMenuDivider(),
        // ── Preferences ────────────────────────────────────────────────
        PopupMenuItem<_UserMenuItem>(
          value: _UserMenuItem.preferences,
          enabled: userId != null && userId > 0,
          child: Row(children: [
            const Icon(Icons.settings_outlined, size: 16),
            const SizedBox(width: 8),
            Text(ctx.l10n.preferences),
          ]),
        ),
        // ── Help (Python `Main` menu "Help") ───────────────────────────
        const PopupMenuDivider(),
        PopupMenuItem<_UserMenuItem>(
          enabled: false,
          height: 28,
          child: Text(ctx.l10n.help,
              style: Theme.of(ctx).textTheme.labelSmall),
        ),
        PopupMenuItem<_UserMenuItem>(
          key: const ValueKey('user-menu-documentation'),
          value: _UserMenuItem.help,
          child: Row(children: [
            const Icon(Icons.menu_book_outlined, size: 16),
            const SizedBox(width: 8),
            Text(ctx.l10n.documentation),
          ]),
        ),
        PopupMenuItem(
          key: const ValueKey('user-menu-shortcuts'),
          value: _UserMenuItem.shortcuts,
          child: Row(children: [
            const Icon(Icons.keyboard_outlined, size: 16),
            const SizedBox(width: 8),
            Text('${ctx.l10n.keyboardShortcuts}…'),
          ]),
        ),
        PopupMenuItem<_UserMenuItem>(
          key: const ValueKey('user-menu-about'),
          value: _UserMenuItem.about,
          child: Row(children: [
            const Icon(Icons.info_outline, size: 16),
            const SizedBox(width: 8),
            Text(ctx.l10n.aboutMenu),
          ]),
        ),
        const PopupMenuDivider(),
        // ── Theme ──────────────────────────────────────────────────────
        PopupMenuItem<_UserMenuItem>(
          value: _UserMenuItem.themes,
          child: Row(children: [
            const Icon(Icons.palette_outlined, size: 16),
            const SizedBox(width: 8),
            const Text('Theme'),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 16),
          ]),
        ),
        const PopupMenuDivider(),
        // ── Logout ─────────────────────────────────────────────────────
        PopupMenuItem<_UserMenuItem>(
          value: _UserMenuItem.logout,
          child: Row(children: [
            Icon(Icons.logout,
                size: 16, color: Theme.of(ctx).colorScheme.error),
            const SizedBox(width: 8),
            Text(l.signOut,
                style:
                    TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ]),
        ),
      ],
      // ── Chip button showing avatar + name + currency ──────────────────
      // very narrow: only the avatar (name and arrow need more room)
      child: LayoutBuilder(
        builder: (context, box) => Padding(
          padding: EdgeInsets.symmetric(horizontal: box.maxWidth < 76 ? 0 : 8),
          child: box.maxWidth < 76
              ? Center(widthFactor: 1, child: _Avatar(prefs: prefs, size: 28))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  _Avatar(prefs: prefs, size: 28),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      prefs?.statusBar ?? (userId != null ? '#$userId' : '…'),
                      key: const ValueKey('user-chip-name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 16),
                ]),
        ),
      ),
    );
  }
}

/// Non-interactive header inside the dropdown.
class _UserHeader extends StatelessWidget {
  final UserPreferences? prefs;
  const _UserHeader({this.prefs});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _Avatar(prefs: prefs, size: 40),
      const SizedBox(width: 12),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(prefs?.name ?? '',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
          if (prefs?.statusBar != null && prefs!.statusBar != prefs!.name)
            Text(prefs!.statusBar,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    ]);
  }
}

/// Avatar of the preferences (`avatar_url` via GET against the server
/// root, with badge), initials as fallback.
class _Avatar extends StatelessWidget {
  final UserPreferences? prefs;
  final double size;
  const _Avatar({required this.prefs, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initials = CircleAvatar(
      radius: size / 2,
      backgroundColor: cs.primary,
      child: Text(
        prefs?.initials ?? '?',
        style: TextStyle(
          fontSize: size * 0.36,
          color: cs.onPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    final url = prefs?.avatarUrl;
    final avatar = url == null
        ? initials
        : ClipOval(
            child: Image.network(
              UserPreferences.imageUrl(url, (size * 2).round(), prefs!.revision),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => initials,
            ),
          );
    final badge = prefs?.avatarBadgeUrl;
    if (badge == null) return avatar;
    return Stack(clipBehavior: Clip.none, children: [
      avatar,
      Positioned(
        right: -2,
        bottom: -2,
        child: ClipOval(
          child: Image.network(
              UserPreferences.imageUrl(badge, size.round(), prefs!.revision),
              width: size / 2,
              height: size / 2,
              errorBuilder: (_, _, _) => const SizedBox.shrink()),
        ),
      ),
    ]);
  }
}

// ─── Theme picker dialog ──────────────────────────────────────────────────────

class _ThemePickerDialog extends StatelessWidget {
  final WidgetRef ref;
  const _ThemePickerDialog({required this.ref});

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(themeProvider);
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.palette_outlined, size: 20),
        SizedBox(width: 8),
        Text('Theme wählen'),
      ]),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: AppTheme.values.map((theme) {
            final isSelected = theme == current;
            return ListTile(
              dense: true,
              leading: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: theme.seedColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        size: 14,
                        color: theme.brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                      )
                    : null,
              ),
              title: Text(
                theme.label,
                style: TextStyle(
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              trailing: Container(
                width: 40,
                height: 16,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(colors: [
                    ColorScheme.fromSeed(
                            seedColor: theme.seedColor,
                            brightness: theme.brightness)
                        .primary,
                    ColorScheme.fromSeed(
                            seedColor: theme.seedColor,
                            brightness: theme.brightness)
                        .primaryContainer,
                  ]),
                ),
              ),
              onTap: () {
                ref.read(themeProvider.notifier).setTheme(theme);
                Navigator.of(context).pop();
              },
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}

/// Logout (user menu, switching the profile for a URL): all tabs close
/// first, each with its save prompt (10.4); the bus ends before the
/// session (spec 2.5.6); then the login screen. False when a tab stayed.
Future<bool> signOut(BuildContext context, WidgetRef ref) async {
  if (!await ref.read(tabsProvider.notifier).requestCloseAll()) return false;
  ref.read(notificationCenterProvider).stop();
  await ref.read(authProvider.notifier).logout();
  ref.read(tabsProvider.notifier).clearAll();
  if (context.mounted) context.go('/login');
  return true;
}

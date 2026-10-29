import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/locale_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_provider.dart';
import '../auth/auth_provider.dart';
import '../auth/user_preferences_provider.dart';
import '../shell/tab_manager.dart';

// ─── User chip (top-right like SAO) ──────────────────────────────────────────

enum _UserMenuItem { preferences, help, themes, logout }

class UserChip extends ConsumerWidget {
  const UserChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The user chip of get_preferences(false) (spec 3.2 step 6).
    final prefs = ref.watch(userPreferencesProvider);
    return _buildMenu(context, ref, prefs, context.l10n);
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
            if (userId != null && userId > 0) {
              ref.read(tabsProvider.notifier).openTab(
                title: context.l10n.preferences,
                model: 'res.user',
                initialDomain: [['id', '=', userId]],
              );
            }
          case _UserMenuItem.help:
            final uri = Uri.parse('https://docs.tryton.org/');
            if (await canLaunchUrl(uri)) launchUrl(uri);
          case _UserMenuItem.themes:
            if (context.mounted) {
              await showDialog<void>(
                context: context,
                builder: (_) => _ThemePickerDialog(ref: ref),
              );
            }
          case _UserMenuItem.logout:
            // All tabs close first, each with its save prompt (10.4).
            if (!await ref.read(tabsProvider.notifier).requestCloseAll()) {
              return;
            }
            await ref.read(authProvider.notifier).logout();
            ref.read(tabsProvider.notifier).clearAll();
            if (context.mounted) context.go('/login');
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
        // ── Help ───────────────────────────────────────────────────────
        PopupMenuItem<_UserMenuItem>(
          value: _UserMenuItem.help,
          child: Row(children: [
            const Icon(Icons.help_outline, size: 16),
            const SizedBox(width: 8),
            Text(ctx.l10n.help),
          ]),
        ),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _Avatar(prefs: prefs, size: 28),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                prefs?.statusBar ?? (userId != null ? '#$userId' : '…'),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 16),
        ]),
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
              '$url?s=${(size * 2).round()}',
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
          child: Image.network('$badge?s=${(size).round()}',
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

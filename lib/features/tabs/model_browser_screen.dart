import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/pyson/pyson_evaluator.dart';
import '../auth/auth_provider.dart';
import '../auth/user_preferences_provider.dart';
import '../model/model_service.dart';
import '../../core/l10n/locale_provider.dart';

// ─── Data model ──────────────────────────────────────────────────────────────

class MenuItem {
  final int id;
  final String name;
  final int? parentId;
  final String? action; // e.g. "ir.action.act_window,42"
  final int sequence;
  final String? iconName; // Tryton icon name, e.g. "tryton-sale"
  List<MenuItem> children = [];

  MenuItem({
    required this.id,
    required this.name,
    this.parentId,
    this.action,
    required this.sequence,
    this.iconName,
  });

  bool get hasAction => action != null && action!.isNotEmpty;

  /// Load model name from an act_window action – resolved separately.
  bool get isActWindow =>
      action?.startsWith('ir.action.act_window') ?? false;
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final menuProvider =
    FutureProvider.autoDispose<List<MenuItem>>((ref) async {
  final svc = ref.read(modelServiceProvider);

  // 1. Load menu entries – `icon` returns the ir.ui.icon ID (integer)
  final records = await svc.searchRead(
    'ir.ui.menu',
    domain: [['active', '=', true]],
    fields: ['name', 'parent', 'action', 'sequence', 'icon'],
    offset: 0,
    limit: 500,
    order: [['sequence', 'ASC']],
  );

  // 2. Collect icon names – 'icon' is a char field containing the name directly
  //    e.g. "tryton-settings", "tryton-sale" – not a Many2One ID!
  final iconNames = <String>{};
  for (final r in records) {
    final raw = r['icon'];
    if (raw is String && raw.isNotEmpty) iconNames.add(raw);
  }

  // 3. Load SVG data for all used icons at once
  if (iconNames.isNotEmpty) {
    await _preloadIconSvgs(svc, iconNames);
  }

  // 4. Build MenuItems
  final items = records.map((r) {
    final parent = r['parent'];
    final int? parentId = parent is int ? parent : null;

    // action is a reference field → ["ir.action.act_window", 42]
    final actionRaw = r['action'];
    final String? action;
    if (actionRaw is List && actionRaw.length >= 2) {
      action = '${actionRaw[0]},${actionRaw[1]}';
    } else if (actionRaw is String && actionRaw.isNotEmpty) {
      action = actionRaw;
    } else {
      action = null;
    }

    // Icon name taken directly from the char field
    final iconRaw = r['icon'];
    final String? iconName =
        (iconRaw is String && iconRaw.isNotEmpty) ? iconRaw : null;

    return MenuItem(
      id: r.id,
      name: r['name']?.toString() ?? '',
      parentId: parentId,
      action: action,
      sequence: r['sequence'] as int? ?? 0,
      iconName: iconName,
    );
  }).toList();

  // Build tree
  final byId = {for (final i in items) i.id: i};
  final roots = <MenuItem>[];
  for (final item in items) {
    if (item.parentId == null || !byId.containsKey(item.parentId)) {
      roots.add(item);
    } else {
      byId[item.parentId]!.children.add(item);
    }
  }

  // Sort children
  void sort(List<MenuItem> list) {
    list.sort((a, b) => a.sequence.compareTo(b.sequence));
    for (final child in list) { sort(child.children); }
  }
  sort(roots);

  return roots;
});

/// Loads SVG data for all provided icon names via search_read and
/// stores them in the global cache.
Future<void> _preloadIconSvgs(ModelService svc, Set<String> names) async {
  final missing = names.where((n) => !isIconCached(n)).toList();
  if (missing.isEmpty) return;

  try {
    final records = await svc.searchRead(
      'ir.ui.icon',
      domain: [['name', 'in', missing]],
      fields: ['name', 'icon'],
      limit: null,
    );

    final found = <String>{};
    for (final r in records) {
      final name = r['name']?.toString() ?? '';
      final svg = r['icon']?.toString();
      if (name.isNotEmpty) {
        found.add(name);
        cacheIconSvg(name, svg);
      }
    }

    // Icons not in ir.ui.icon → Material fallback
    for (final n in missing.toSet().difference(found)) {
      cacheIconSvg(n, null);
    }
  } catch (_) {
    for (final n in missing) { cacheIconSvg(n, null); }
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class ModelBrowserScreen extends ConsumerWidget {
  const ModelBrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(menuProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: context.l10n.reloadMenu,
            onPressed: () => ref.invalidate(menuProvider),
          ),
          // ── User chip (right side like SAO) ────────────────────────────
          const _UserChip(),
          const SizedBox(width: 8),
        ],
      ),
      body: menuAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 8),
            Text(e.toString()),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => ref.invalidate(menuProvider),
              child: Text(context.l10n.retry),
            ),
          ]),
        ),
        data: (roots) => _MenuTree(roots: roots),
      ),
    );
  }
}

// ─── Menu tree ────────────────────────────────────────────────────────────────

class _MenuTree extends ConsumerWidget {
  final List<MenuItem> roots;
  const _MenuTree({required this.roots});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (roots.isEmpty) {
      return Center(child: Text(context.l10n.noMenuEntriesFound));
    }
    return ListView.builder(
      itemCount: roots.length,
      itemBuilder: (ctx, i) => _MenuNode(item: roots[i], depth: 0),
    );
  }
}

class _MenuNode extends ConsumerStatefulWidget {
  final MenuItem item;
  final int depth;
  const _MenuNode({required this.item, required this.depth});

  @override
  ConsumerState<_MenuNode> createState() => _MenuNodeState();
}

class _MenuNodeState extends ConsumerState<_MenuNode> {
  bool _expanded = false;

  bool get hasChildren => widget.item.children.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final indent = widget.depth * 16.0;
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ─── Menu row ─────────────────────────────────────────────────────
        InkWell(
          // Click on icon or text → trigger action (like SAO original)
          onTap: item.hasAction ? () => _openAction(context, item) : null,
          child: Padding(
            padding: EdgeInsets.only(left: 8 + indent, right: 8),
            child: Row(
              children: [
                // ① Expand/collapse button – only when children exist
                //    Separate widget, NOT part of the action click
                SizedBox(
                  width: 28,
                  height: 40,
                  child: hasChildren
                      ? IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                          icon: Icon(
                            _expanded
                                ? Icons.arrow_drop_down
                                : Icons.arrow_right,
                            size: 20,
                            color: primary.withAlpha(180),
                          ),
                          tooltip: _expanded ? context.l10n.collapse : context.l10n.expand,
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                        )
                      : const SizedBox.shrink(),
                ),

                // ② Tryton icon of the menu entry
                _buildIcon(item, size: 18, color: primary.withAlpha(200)),
                const SizedBox(width: 8),

                // ③ Label
                Expanded(
                  child: Text(
                    item.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: widget.depth == 0 && hasChildren
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: item.hasAction ? onSurface : onSurface.withAlpha(120),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ─── Children (when expanded) ─────────────────────────────────────
        if (_expanded && hasChildren)
          for (final child in widget.item.children)
            _MenuNode(item: child, depth: widget.depth + 1),

        if (_expanded && widget.depth == 0)
          const Divider(height: 1),
      ],
    );
  }

  /// Renders the icon of the menu entry (same for leaves and groups).
  Widget _buildIcon(MenuItem item, {double size = 18, Color? color}) {
    if (item.iconName != null) {
      return TrytonIcon(
        iconName: item.iconName,
        size: size,
        color: color,
        fallback: Icons.widgets_outlined,
      );
    }
    // No icon defined → neutral symbol
    return Icon(
      item.children.isNotEmpty
          ? Icons.folder_outlined
          : Icons.circle,
      size: item.children.isNotEmpty ? size : size * 0.4,
      color: color?.withAlpha(80),
    );
  }

  Future<void> _openAction(BuildContext context, MenuItem item) async {
    if (!item.isActWindow) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action "${item.action}" is not yet supported.')),
      );
      return;
    }

    final parts = item.action!.split(',');
    if (parts.length < 2) return;
    final actionId = int.tryParse(parts[1]);
    if (actionId == null) return;

    try {
      final svc = ref.read(modelServiceProvider);
      final session = ref.read(sessionProvider);

      // Load act_window – including pyson_domain and pyson_context
      // (like SAO: exec_action reads all these fields)
      final actions = await svc.read(
        'ir.action.act_window',
        [actionId],
        ['name', 'res_model', 'pyson_domain', 'pyson_context',
         'context_model', 'context_domain'],
      );
      if (actions.isEmpty || !context.mounted) return;

      final action = actions.first;
      final model = action['res_model']?.toString() ?? '';
      final name = action['name']?.toString() ?? item.name;
      if (model.isEmpty) return;

      // Build evaluation context (like SAO: session.context + active_*)
      final evalCtx = <String, dynamic>{
        ...session.context,
        '_user': session.userId,
        'active_model': null,
        'active_id': null,
        'active_ids': <int>[],
      };

      // Evaluate pyson_context and merge into evalCtx
      final pysonCtx = action['pyson_context']?.toString();
      if (pysonCtx != null && pysonCtx.isNotEmpty && pysonCtx != '{}') {
        try {
          final ctxDecoded = _safeDecode(pysonCtx);
          if (ctxDecoded != null) {
            final ctxEvaluated = PYSONEvaluator(evalCtx).eval(ctxDecoded);
            if (ctxEvaluated is Map) {
              evalCtx.addAll(ctxEvaluated.cast<String, dynamic>());
            }
          }
        } catch (_) {}
      }
      evalCtx['context'] = evalCtx;

      // Evaluate pyson_domain → concrete domain list
      final domain = evaluateActionDomain(
        action['pyson_domain']?.toString(),
        evalCtx,
      );

      // Navigate to ListViewScreen – domain + context_model as URL parameters
      final titleEnc = Uri.encodeComponent(name);
      final params = <String>['title=$titleEnc', 'action_id=$actionId'];
      if (domain.isNotEmpty) {
        params.add('domain=${Uri.encodeComponent(jsonEncode(domain))}');
      }
      final contextModel = action['context_model']?.toString();
      if (contextModel != null && contextModel.isNotEmpty) {
        params.add('context_model=${Uri.encodeComponent(contextModel)}');
      }
      final contextDomain = action['context_domain']?.toString();
      if (contextDomain != null && contextDomain.isNotEmpty) {
        params.add('context_domain=${Uri.encodeComponent(contextDomain)}');
      }
      context.push('/models/$model?${params.join('&')}');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }
}

dynamic _safeDecode(String s) {
  try { return jsonDecode(s); } catch (_) { return null; }
}

// ─── User chip (top-right like SAO) ──────────────────────────────────────────

enum _UserMenuItem { preferences, help, logout }

class _UserChip extends ConsumerWidget {
  const _UserChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(userPreferencesProvider);
    final l = context.l10n;

    return prefsAsync.when(
      loading: () => const SizedBox(
        width: 32, height: 32,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (err, st) => _buildMenu(context, ref, null, l),
      data: (prefs) => _buildMenu(context, ref, prefs, l),
    );
  }

  Widget _buildMenu(BuildContext context, WidgetRef ref,
      UserPreferences? prefs, dynamic l) {
    final userId = ref.read(sessionProvider).userId;
    return PopupMenuButton<_UserMenuItem>(
      position: PopupMenuPosition.under,
      // Override the Flutter default tooltip ("Show menu" / "Menü anzeigen")
      tooltip: prefs?.name ?? l.signOut,
      onSelected: (item) async {
        switch (item) {
          case _UserMenuItem.preferences:
            // Open the current user's form in DynamicFormScreen
            if (userId != null && userId > 0) {
              context.push('/models/res.user/$userId?title=${context.l10n.preferences}');
            }
          case _UserMenuItem.help:
            final uri = Uri.parse('https://docs.tryton.org/');
            if (await canLaunchUrl(uri)) launchUrl(uri);
          case _UserMenuItem.logout:
            await ref.read(authProvider.notifier).logout();
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
                prefs?.name ?? (userId != null ? '#$userId' : '…'),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
              if (prefs?.currency != null)
                Text(
                  prefs!.currency!,
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.outline),
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

/// Circular avatar – shows network image or initials fallback.
/// Avatar circle showing user initials.
/// Avatar image loading is skipped (Tryton 8.x avatar endpoint returns 405).
class _Avatar extends StatelessWidget {
  final UserPreferences? prefs;
  final double size;
  const _Avatar({required this.prefs, required this.size});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: primary,
      child: Text(
        prefs?.initials ?? '?',
        style: TextStyle(
          fontSize: size * 0.36,
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

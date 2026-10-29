import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/icons/tryton_icon.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/model/model.dart' hide TextField;
import '../../core/pyson/pyson_evaluator.dart';
import '../../core/screen/screen.dart';
import '../actions/action_service.dart';
import '../auth/auth_provider.dart';
import '../auth/user_preferences_provider.dart';
import '../model/model_rpc.dart';
import '../model/model_service.dart';
import '../shell/tab_manager.dart';

// ─── Menu screen (spec 10.1) ──────────────────────────────────────────────────

/// Screen attributes of the menu action of the preferences (`pyson_menu`,
/// SAO `Sao.menu`): tree views of the action, PYSON domain/context/order
/// with the session context, no limit.
ScreenAttributes? menuAttributes(
    Map<String, dynamic> preferences, Map<String, dynamic> sessionContext) {
  final raw = preferences['pyson_menu'];
  if (raw is! String || raw.isEmpty) return null;
  final decoded = PYSONEvaluator(const {}).eval(jsonDecode(raw));
  if (decoded is! Map) return null;
  final action = Map<String, dynamic>.from(decoded);
  final views = action['views'];
  final viewId = action['view_id'];
  final viewIds = <int?>[
    if (views is List && views.isNotEmpty)
      for (final v in views) ((v as List)[0] as int?)
    else if (viewId is List && viewId.isNotEmpty)
      viewId.first as int?,
  ];
  dynamic decode(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return PYSONEvaluator({...sessionContext, 'context': sessionContext})
        .eval(jsonDecode(value));
  }

  final context = decode(action['pyson_context']);
  final domain = decode(action['pyson_domain']);
  final order = decode(action['pyson_order']);
  return ScreenAttributes(
    '${action['res_model'] ?? 'ir.ui.menu'}',
    mode: const ['tree'],
    viewIds: viewIds,
    domain: domain is List ? domain : const [],
    context: context is Map ? context.cast<String, dynamic>() : const {},
    order: order is List ? order : null,
    limit: null,
  );
}

/// The menu screen of the current preferences (null when logged out).
final menuScreenProvider = FutureProvider<TrytonScreen?>((ref) async {
  final preferences = ref.watch(preferencesProvider);
  if (preferences == null) return null;
  final svc = ref.read(modelServiceProvider);
  final attributes =
      menuAttributes(preferences, ref.read(sessionProvider).context);
  if (attributes == null) return null;
  final screen = TrytonScreen(attributes, session: modelSessionFor(svc));
  ref.onDispose(screen.dispose);
  await screen.switchView();
  await screen.searchFilter();
  return screen;
});

/// Favorites of the menu (`<menu model>.favorite.get()` → `[[id, name,
/// icon], …]`).
final menuFavoritesProvider = FutureProvider<List<List<dynamic>>>((ref) async {
  final screen = await ref.watch(menuScreenProvider.future);
  if (screen == null) return const [];
  try {
    final result = await ref
        .read(modelServiceProvider)
        .execute<dynamic>('${screen.model.name}.favorite', 'get', [],
            processException: false);
    return [
      for (final f in (result as List? ?? const []))
        if (f is List && f.length >= 2) f
    ];
  } catch (_) {
    return const [];
  }
});

/// Loads the SVGs of [names] (ir.ui.icon) into the icon cache.
Future<void> preloadIconSvgs(ModelService svc, Set<String> names) async {
  final missing = names.where((n) => !isIconCached(n)).toList();
  if (missing.isEmpty) return;
  try {
    final records = await svc.searchRead(
      'ir.ui.icon',
      domain: [
        ['name', 'in', missing]
      ],
      fields: ['name', 'icon'],
      limit: null,
    );
    final found = <String>{};
    for (final r in records) {
      final name = r['name']?.toString() ?? '';
      if (name.isNotEmpty) {
        found.add(name);
        cacheIconSvg(name, r['icon']?.toString());
      }
    }
    for (final n in missing.toSet().difference(found)) {
      cacheIconSvg(n, null);
    }
  } catch (_) {
    for (final n in missing) {
      cacheIconSvg(n, null);
    }
  }
}

/// Menu activation (SAO `main_menu_row_activate`): keyword `tree_open` of
/// the entry, without ids (no name suffix) and without warning.
Future<void> openMenuEntry(
    BuildContext context, WidgetRef ref, String model, int id) async {
  try {
    await ref.read(actionServiceProvider).execKeyword(
          'tree_open',
          {'model': model, 'id': id},
          warning: false,
          ui: DialogActionUi(context),
        );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

// ─── Sidebar ──────────────────────────────────────────────────────────────────

/// Menu in the shell's sidebar (spec 10.1): favorites, the menu tree of
/// `pyson_menu` (children of `field_childs` loaded when expanded, star for
/// favorites, expanded entries remembered locally) and the global search.
class MenuSidebar extends ConsumerStatefulWidget {
  const MenuSidebar({super.key});

  @override
  ConsumerState<MenuSidebar> createState() => _MenuSidebarState();
}

class _MenuSidebarState extends ConsumerState<MenuSidebar> {
  /// Expanded menu entries (tree state, kept in shared preferences).
  Set<int> _expanded = {};
  String? _stateKey;
  final Set<Record> _loading = {};
  bool _favoritesOpen = true;

  String _key() {
    final session = ref.read(sessionProvider);
    return 'menu_tree_state:${session.login}@${session.database}';
  }

  Future<void> _loadTreeState() async {
    final key = _key();
    if (key == _stateKey) return;
    _stateKey = key;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(key) ?? const [];
      if (mounted) {
        setState(() => _expanded = {for (final i in ids) ?int.tryParse(i)});
      }
    } catch (_) {}
  }

  Future<void> _saveTreeState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key(), [for (final i in _expanded) '$i']);
    } catch (_) {}
  }

  void _toggle(Record record) {
    setState(() {
      if (!_expanded.remove(record.id)) _expanded.add(record.id);
    });
    _saveTreeState();
  }

  /// Row values with the neighbours in one read; icons into the cache.
  void _ensureLoaded(Record record) {
    if (record.isLoaded('name') || _loading.contains(record)) return;
    _loading.add(record);
    record.load('name', processException: false).then((_) async {
      final icons = <String>{
        for (final r in record.group)
          if (r.values['icon'] case final String icon when icon.isNotEmpty)
            icon
      };
      await preloadIconSvgs(ref.read(modelServiceProvider), icons);
    }).catchError((Object _) {}).whenComplete(() {
      _loading.remove(record);
      if (mounted) setState(() {});
    });
  }

  Future<void> _toggleFavorite(TrytonScreen screen, Record record) async {
    final favorite = record.values['favorite'] == true;
    try {
      await ref.read(modelServiceProvider).execute<dynamic>(
          '${screen.model.name}.favorite', favorite ? 'unset' : 'set', [record.id]);
      record.set({'favorite': !favorite}, modified: false, validate: false);
      ref.invalidate(menuFavoritesProvider);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = context.l10n;
    final menu = ref.watch(menuScreenProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: cs.surfaceContainerHighest,
          child: Row(children: [
            Expanded(
              child: Text(l.appTitle,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              key: const ValueKey('global-search'),
              icon: const Icon(Icons.search, size: 16),
              tooltip: '${l.globalSearch} (Ctrl+K)',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => showGlobalSearch(context, ref),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 16),
              tooltip: l.reloadMenu,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => ref.invalidate(menuScreenProvider),
            ),
          ]),
        ),
        Divider(height: 1, thickness: 1, color: cs.outlineVariant),
        Expanded(
          child: menu.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 32, color: Colors.red),
                const SizedBox(height: 6),
                Text('$e',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(menuScreenProvider),
                  child: Text(l.retry),
                ),
              ]),
            ),
            data: (screen) {
              if (screen == null) {
                return Center(child: Text(l.noMenuEntriesFound));
              }
              _loadTreeState();
              return _buildMenu(screen);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMenu(TrytonScreen screen) {
    final rows = <Widget>[_buildFavorites(screen)];
    final childs = screen.currentView?.fieldChilds;
    void add(Iterable<Record> records, int depth) {
      for (final record in records) {
        _ensureLoaded(record);
        rows.add(_row(screen, record, depth, childs));
        final children = childs != null && record.isLoaded(childs)
            ? record.fieldGetClient(childs)
            : null;
        if (_expanded.contains(record.id) && children is RecordGroup) {
          add(children, depth + 1);
        }
      }
    }

    add(screen.group, 0);
    if (screen.group.isEmpty) {
      rows.add(Padding(
        padding: const EdgeInsets.all(16),
        child: Text(context.l10n.noMenuEntriesFound),
      ));
    }
    return ListView(children: rows);
  }

  Widget _buildFavorites(TrytonScreen screen) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final favorites = ref.watch(menuFavoritesProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('menu-favorites'),
          onTap: () => setState(() => _favoritesOpen = !_favoritesOpen),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Row(children: [
              Icon(_favoritesOpen ? Icons.arrow_drop_down : Icons.arrow_right,
                  size: 20, color: cs.primary),
              const Icon(Icons.star, size: 16, color: Colors.amber),
              const SizedBox(width: 6),
              Text(l.favorites,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        if (_favoritesOpen)
          if (favorites.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 0, 8, 6),
              child: Text(l.noFavorites,
                  style: TextStyle(fontSize: 11, color: cs.outline)),
            )
          else
            for (final f in favorites)
              InkWell(
                onTap: () =>
                    openMenuEntry(context, ref, screen.model.name, f[0] as int),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(36, 6, 8, 6),
                  child: Row(children: [
                    TrytonIcon(
                        iconName: f.length > 2 ? '${f[2]}' : null,
                        size: 16,
                        color: cs.primary,
                        fallback: Icons.circle),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${f[1]}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ]),
                ),
              ),
        Divider(height: 1, color: cs.outlineVariant),
      ],
    );
  }

  Widget _row(TrytonScreen screen, Record record, int depth, String? childs) {
    final cs = Theme.of(context).colorScheme;
    final l = context.l10n;
    final loaded = record.isLoaded('name');
    final name = loaded ? '${record.values['name'] ?? ''}' : '';
    final icon = record.values['icon'];
    final children = childs != null && record.isLoaded(childs)
        ? record.fieldGetClient(childs)
        : null;
    final hasChildren = children is RecordGroup && children.isNotEmpty;
    final expanded = _expanded.contains(record.id);
    final favorite = record.values['favorite'];
    return InkWell(
      key: ValueKey('menu-${record.id}'),
      // Activation: tree_open; a parent also opens.
      onTap: () {
        if (hasChildren && !expanded) _toggle(record);
        openMenuEntry(context, ref, screen.model.name, record.id);
      },
      child: Padding(
        padding: EdgeInsets.only(left: 8 + depth * 16.0, right: 4),
        child: Row(children: [
          SizedBox(
            width: 28,
            height: 36,
            child: hasChildren
                ? IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: Icon(
                        expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                        size: 20,
                        color: cs.primary.withAlpha(180)),
                    tooltip: expanded ? l.collapse : l.expand,
                    onPressed: () => _toggle(record),
                  )
                : null,
          ),
          if (icon is String && icon.isNotEmpty)
            TrytonIcon(
                iconName: icon,
                size: 18,
                color: cs.primary.withAlpha(200),
                fallback: Icons.widgets_outlined)
          else
            Icon(hasChildren ? Icons.folder_outlined : Icons.circle,
                size: hasChildren ? 18 : 7, color: cs.primary.withAlpha(80)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: depth == 0 && hasChildren
                        ? FontWeight.w600
                        : FontWeight.normal)),
          ),
          // Favorite star (field `favorite`; null = not possible)
          if (favorite is bool)
            IconButton(
              key: ValueKey('menu-star-${record.id}'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(favorite ? Icons.star : Icons.star_border,
                  size: 16, color: favorite ? Colors.amber : cs.outline),
              tooltip: favorite ? l.removeFromFavorites : l.addToFavorites,
              onPressed: () => _toggleFavorite(screen, record),
            ),
        ]),
      ),
    );
  }
}

// ─── Global search (spec 10.1) ────────────────────────────────────────────────

/// Global search (Ctrl/Cmd+K): `ir.model.global_search(text, limit, menu
/// model)` → `[[score, model, model_name, id, rec_name, icon], …]`; menu
/// entries open with `tree_open`, other records as a form tab.
Future<void> showGlobalSearch(BuildContext context, WidgetRef ref) async {
  final menuModel =
      ref.read(menuScreenProvider).value?.model.name ?? 'ir.ui.menu';
  final chosen = await showDialog<List<dynamic>>(
    context: context,
    builder: (_) => _GlobalSearchDialog(menuModel: menuModel),
  );
  if (chosen == null || !context.mounted) return;
  final model = '${chosen[1]}';
  final id = chosen[3] as int;
  if (model == menuModel) {
    await openMenuEntry(context, ref, model, id);
  } else {
    ref.read(tabsProvider.notifier).openTab(
          title: '${chosen[2]}',
          attributes:
              ScreenAttributes(model, mode: const ['form', 'tree'], resId: id),
        );
  }
}

class _GlobalSearchDialog extends ConsumerStatefulWidget {
  final String menuModel;
  const _GlobalSearchDialog({required this.menuModel});

  @override
  ConsumerState<_GlobalSearchDialog> createState() =>
      _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<_GlobalSearchDialog> {
  Timer? _debounce;
  List<List<dynamic>> _results = const [];
  bool _busy = false;

  /// Results shown at most (SAO `Sao.config.limit` is far larger).
  static const _limit = 50;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(text));
  }

  Future<void> _search(String text) async {
    if (text.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await ref.read(modelServiceProvider).execute<dynamic>(
          'ir.model', 'global_search', [text, _limit, widget.menuModel],
          processException: false);
      if (!mounted) return;
      setState(() => _results = [
            for (final r in (result as List? ?? const []))
              if (r is List && r.length >= 5) r
          ]);
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l.globalSearch),
      content: SizedBox(
        width: 520,
        height: 400,
        child: Column(children: [
          TextField(
            key: const ValueKey('global-search-text'),
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l.search,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: _changed,
            onSubmitted: (_) {
              if (_results.isNotEmpty) Navigator.pop(context, _results.first);
            },
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(children: [
              for (final r in _results)
                ListTile(
                  dense: true,
                  leading: TrytonIcon(
                      iconName: r.length > 5 ? '${r[5]}' : null,
                      size: 18,
                      color: cs.primary,
                      fallback: Icons.circle),
                  title: Text('${r[4]}'),
                  subtitle: Text('${r[2]}'),
                  onTap: () => Navigator.pop(context, r),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
      ],
    );
  }
}

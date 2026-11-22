import 'dart:math' as math;

import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/locale_provider.dart';
import '../tabs/menu_sidebar.dart';
import '../tabs/user_chip.dart';
import '../auth/preferences_dialog.dart';
import '../views/record_menu.dart';
import '../../core/screen/screen.dart';
import '../views/board_view.dart';
import '../views/screen_widget.dart';
import '../views/wizard_widget.dart';
import '../actions/url_opener.dart';
import 'menu_width.dart';
import 'shell_context.dart';
import 'tab_manager.dart';
import '../../core/theme/tryton_colors.dart';
import 'tab_strip.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _sidebarOpen = true;

  /// Narrow window (< [menuToggleWidth]): the menu is shown instead of the
  /// tabs (the menu button switches); without an open tab only the menu.
  bool _narrowMenu = false;

  /// Narrow window without a tab: only the menu (no empty page).
  bool get _onlyMenu => _narrow && ref.read(tabsProvider).tabs.isEmpty;

  /// The menu keeps its state (expanded entries) when the layout switches
  /// between narrow and wide.
  final _menuKey = GlobalKey();

  bool get _narrow => MediaQuery.sizeOf(context).width < menuToggleWidth;

  /// The menu button: narrow – menu or tabs; wide – menu beside the tabs
  /// shown or hidden.
  void _toggleMenu() => setState(() {
        if (_narrow) {
          _narrowMenu = !_narrowMenu;
        } else {
          _sidebarOpen = !_sidebarOpen;
        }
      });

  /// The menu is shown: beside the tabs (wide) or instead of them (narrow).
  bool get _menuShown => _narrow ? (_narrowMenu || _onlyMenu) : _sidebarOpen;

  @override
  void initState() {
    super.initState();
    // a tryton:// URL waiting for this login (profile switched, E7)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // the shell is built: the start actions may run (spec 3.2 step 4)
      if (mounted) shellContext.value = context;
      final url = ref.read(pendingTrytonUrlProvider);
      if (url == null || !mounted) return;
      ref.read(pendingTrytonUrlProvider.notifier).state = null;
      openTrytonUrl(context, ref, url);
    });
  }

  @override
  void dispose() {
    if (identical(shellContext.value, context)) shellContext.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabsState = ref.watch(tabsProvider);
    final cs = Theme.of(context).colorScheme;
    // narrow window: a tab opened or activated from the menu, the
    // favorites or the global search is shown at once (like on a phone)
    ref.listen<TabsState>(tabsProvider, (previous, next) {
      if (!_narrow || !_narrowMenu || next.tabs.isEmpty) return;
      if (previous == null ||
          next.activeIndex != previous.activeIndex ||
          next.tabs.length != previous.tabs.length) {
        setState(() => _narrowMenu = false);
      }
    });
    // a tryton:// link of the operating system while logged in (E7)
    ref.listen<String?>(pendingTrytonUrlProvider, (_, url) {
      if (url == null) return;
      ref.read(pendingTrytonUrlProvider.notifier).state = null;
      openTrytonUrl(context, ref, url);
    });
    // the menu at most so wide that the tabs keep 360 px
    final maxMenu = (MediaQuery.sizeOf(context).width - 360)
        .clamp(MenuWidthNotifier.minWidth, MenuWidthNotifier.maxWidth);
    final sidebarWidth =
        ref.watch(menuWidthProvider).clamp(MenuWidthNotifier.minWidth, maxMenu);

    // Keyboard (desktop): Ctrl/Cmd+K global search, Ctrl+Tab /
    // Ctrl+Shift+Tab and Ctrl+PageDown/PageUp next/previous tab (10.1/10.2);
    // the record shortcuts go to the active tab when the focus is outside
    // its screen, F1 / Ctrl+F1 help, Ctrl+M menu, Ctrl+, preferences,
    // Ctrl+Q quit (Anhang B; Cmd on macOS, where the app menu quits).
    final tabs = ref.read(tabsProvider.notifier);
    return CallbackShortcuts(
      bindings: {
        ...recordShellBindings(),
        const SingleActivator(LogicalKeyboardKey.f1): () =>
            showShortcutsHelp(context),
        primaryShortcut(LogicalKeyboardKey.f1): () =>
            showShortcutsHelp(context),
        primaryShortcut(LogicalKeyboardKey.keyM): () {
          if (!_onlyMenu) _toggleMenu();
        },
        primaryShortcut(LogicalKeyboardKey.comma): () =>
            showPreferencesDialog(context, ref),
        if (defaultTargetPlatform != TargetPlatform.macOS)
          primaryShortcut(LogicalKeyboardKey.keyQ): _quit,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            showGlobalSearch(context, ref),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            showGlobalSearch(context, ref),
        const SingleActivator(LogicalKeyboardKey.tab, control: true):
            tabs.nextTab,
        const SingleActivator(LogicalKeyboardKey.tab,
            control: true, shift: true): tabs.previousTab,
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true):
            tabs.nextTab,
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true):
            tabs.previousTab,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      body: _narrow
          ? _narrowBody(tabsState, cs)
          : Row(
        children: [
          // ── Sidebar (opening/closing animated) ─────────────────────────
          MenuSlot(
            open: _sidebarOpen,
            width: sidebarWidth,
            child: MenuSidebar(key: _menuKey),
          ),
          // the divider: drag for the width of the menu (kept like the
          // language), double click for the default
          if (_sidebarOpen)
            MenuResizeHandle(
              maxWidth: maxMenu,
            ),
          // ── Main content area ──────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTabBar(tabsState),
                Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                Expanded(child: _tabsArea(tabsState)),
              ],
            ),
          ),
        ],
      ),
    ), // Scaffold
      ), // Focus
    ); // CallbackShortcuts
  }

  /// The content of the active tab (all tabs stay alive), else the welcome.
  /// The tabs see their own size as the window size (`MediaQuery`): beside
  /// the menu a form decides one column / side labels by the width it
  /// really has (< 600 px: narrow layout) – with the window's width a
  /// 450 px tab kept the columns and squeezed groups (labels broken
  /// inside a word, overflowing check boxes). Dialogs open over the whole
  /// window (root navigator) and keep its size.
  Widget _tabsArea(TabsState tabsState) => LayoutBuilder(
        builder: (context, box) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(size: Size(box.maxWidth, box.maxHeight)),
          child: tabsState.tabs.isEmpty
              ? _buildWelcome()
              : IndexedStack(
                  index: tabsState.activeIndex < 0 ? 0 : tabsState.activeIndex,
                  children: tabsState.tabs
                      .map((tab) => _buildTabContent(tab))
                      .toList(),
                ),
        ),
      );

  /// Narrow window (< [menuToggleWidth], like on a phone): the tab bar on
  /// top over the full width, below either the menu or the tabs, each in
  /// the full width; both stay alive (no state is lost when switching).
  Widget _narrowBody(TabsState tabsState, ColorScheme cs) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabBar(tabsState),
          Divider(height: 1, thickness: 1, color: cs.outlineVariant),
          Expanded(
            child: IndexedStack(
              key: const ValueKey('narrow-body'),
              // without a tab only the menu (no empty page)
              index: _narrowMenu || tabsState.tabs.isEmpty ? 0 : 1,
              children: [
                MenuSidebar(key: _menuKey),
                _tabsArea(tabsState),
              ],
            ),
          ),
        ],
      );

  /// Quit (Ctrl+Q): all tabs close first, each with its save prompt.
  Future<void> _quit() async {
    if (!await ref.read(tabsProvider.notifier).requestCloseAll()) return;
    await ServicesBinding.instance.exitApplication(AppExitType.required);
  }

  Widget _buildTabBar(TabsState state) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      // the user chip takes at most half of the bar
      return _tabBar(state, cs, math.max(0, (box.maxWidth - 44) / 2));
    });
  }

  Widget _tabBar(TabsState state, ColorScheme cs, double chipMaxWidth) {
    final foreground = TrytonColors.of(context).tabBarForeground;
    return Container(
      height: 40,
      color: TrytonColors.of(context).tabBarBackground,
      child: _onBar(foreground, Row(
        children: [
          // Sidebar toggle
          SizedBox(
            width: 40,
            child: IconButton(
              icon: Icon(
                _menuShown ? Icons.menu_open : Icons.menu,
                size: 18,
              ),
              key: const ValueKey('menu-toggle'),
              padding: EdgeInsets.zero,
              tooltip: _menuShown ? 'Menü ausblenden' : 'Menü einblenden',
              // narrow without a tab: nothing to switch to
              onPressed: _onlyMenu ? null : _toggleMenu,
            ),
          ),
          // Tab chips: wheel scrolling, active tab in view, "all tabs"
          Expanded(
            child: TabStrip(
              tabs: state.tabs,
              activeIndex: state.activeIndex,
              onActivate: (i) => ref.read(tabsProvider.notifier).activateTab(i),
              // A modified form in the tab asks first (10.4).
              onClose: (i) => ref
                  .read(tabsProvider.notifier)
                  .requestCloseTab(state.tabs[i].id),
            ),
          ),
          // at the right edge; at most half of the bar, else shortened
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: chipMaxWidth),
            child: const UserChip(),
          ),
          const SizedBox(width: 4),
        ],
      )),
    );
  }

  /// Icons and texts of the tab bar in the theme's colour (Blue Ocean:
  /// white on the dark band); unchanged without one.
  static Widget _onBar(Color? foreground, Widget child) => foreground == null
      ? child
      : IconTheme.merge(
          data: IconThemeData(color: foreground),
          child: DefaultTextStyle.merge(
              style: TextStyle(color: foreground), child: child));

  Widget _buildTabContent(AppTab tab) {
    return TabScope(
      tabId: tab.id,
      child: Navigator(
      key: tab.navigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => tab.wizard != null
            ? WizardWidget(wizard: tab.wizard!)
            : tab.isBoard
                ? BoardView(
                    attributes: tab.attributes,
                    title: tab.title,
                    onClose: () =>
                        ref.read(tabsProvider.notifier).requestCloseTab(tab.id),
                  )
            : ScreenWidget(
          tabRoot: true,
          attributes: tab.attributes,
          title: tab.title,
          onClose: () async {
            await ref.read(tabsProvider.notifier).requestCloseTab(tab.id);
          },
        ),
      ),
    ),
    );
  }

  Widget _buildWelcome() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.tab_outlined, size: 64, color: cs.outline),
        const SizedBox(height: 12),
        Text(
          context.l10n.selectMenuEntry,
          style: Theme.of(context)
              .textTheme
              .bodyLarge
              ?.copyWith(color: cs.outline),
        ),
      ]),
    );
  }
}

// ─── Tab chip ─────────────────────────────────────────────────────────────────

// ─── Formular öffnen (z. B. Many2One „Öffnen“, „Anhang hinzufügen“) ─────────
// Eigener Screen mit nur der Form-View in einer neuen Route des Tabs;
// recordId < 0 legt einen neuen Datensatz an (nach dem Speichern wird die
// Route mit dessen id geschlossen).

Future<void> pushFormScreen(
  BuildContext context, {
  required String model,
  required int recordId,
  required String title,
  List<dynamic> screenDomain = const [],
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (ctx) => ScreenWidget(
      attributes: ScreenAttributes(
        model,
        mode: const ['form'],
        domain: screenDomain,
        resId: recordId < 0 ? null : recordId,
      ),
      title: title,
      onClose: () => Navigator.of(ctx).maybePop(),
      closeOnSaveNew: recordId < 0,
    ),
  ));
}

/// Board tabs (`board` view, E33) are not supported yet.

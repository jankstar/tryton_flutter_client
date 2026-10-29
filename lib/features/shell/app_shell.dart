import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/services.dart';

import '../../core/l10n/locale_provider.dart';
import '../tabs/menu_sidebar.dart';
import '../tabs/user_chip.dart';
import '../../core/screen/screen.dart';
import '../views/screen_widget.dart';
import '../views/wizard_widget.dart';
import 'tab_manager.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _sidebarOpen = true;
  static const _sidebarWidth = 250.0;

  @override
  Widget build(BuildContext context) {
    final tabsState = ref.watch(tabsProvider);
    final cs = Theme.of(context).colorScheme;

    // Keyboard (desktop): Ctrl/Cmd+K global search, Ctrl+Tab /
    // Ctrl+Shift+Tab and Ctrl+PageDown/PageUp next/previous tab (10.1/10.2).
    final tabs = ref.read(tabsProvider.notifier);
    return CallbackShortcuts(
      bindings: {
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
      body: Row(
        children: [
          // ── Sidebar (animated) ─────────────────────────────────────────
          ClipRect(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              width: _sidebarOpen ? _sidebarWidth : 0,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: _sidebarWidth,
                child: SizedBox(
                  width: _sidebarWidth,
                  child: const MenuSidebar(),
                ),
              ),
            ),
          ),
          if (_sidebarOpen)
            VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant),
          // ── Main content area ──────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTabBar(tabsState),
                Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                Expanded(
                  child: tabsState.tabs.isEmpty
                      ? _buildWelcome()
                      : IndexedStack(
                          index: tabsState.activeIndex < 0
                              ? 0
                              : tabsState.activeIndex,
                          children: tabsState.tabs
                              .map((tab) => _buildTabContent(tab))
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    ), // Scaffold
      ), // Focus
    ); // CallbackShortcuts
  }

  Widget _buildTabBar(TabsState state) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      color: cs.surfaceContainerHighest,
      child: Row(
        children: [
          // Sidebar toggle
          SizedBox(
            width: 40,
            child: IconButton(
              icon: Icon(
                _sidebarOpen ? Icons.menu_open : Icons.menu,
                size: 18,
              ),
              padding: EdgeInsets.zero,
              tooltip: _sidebarOpen ? 'Menü ausblenden' : 'Menü einblenden',
              onPressed: () => setState(() => _sidebarOpen = !_sidebarOpen),
            ),
          ),
          // Tab chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  for (int i = 0; i < state.tabs.length; i++)
                    _TabChip(
                      tab: state.tabs[i],
                      isActive: i == state.activeIndex,
                      onTap: () =>
                          ref.read(tabsProvider.notifier).activateTab(i),
                      // A modified form in the tab asks first (10.4).
                      onClose: () => ref
                          .read(tabsProvider.notifier)
                          .requestCloseTab(state.tabs[i].id),
                    ),
                ],
              ),
            ),
          ),
          const UserChip(),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildTabContent(AppTab tab) {
    return TabScope(
      tabId: tab.id,
      child: Navigator(
      key: tab.navigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => tab.wizard != null
            ? WizardWidget(wizard: tab.wizard!)
            : tab.isBoard
                ? _BoardPlaceholder(title: tab.title)
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

class _TabChip extends StatelessWidget {
  final AppTab tab;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TabChip({
    required this.tab,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InputChip(
        // Keyword actions of the menu carry the menu path ("A / B / C"):
        // the chip shows the last part, the tooltip the full name.
        tooltip: tab.title,
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            tab.title.split(' / ').last,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        selected: isActive,
        onSelected: (_) => onTap(),
        onDeleted: onClose,
        deleteIcon: const Icon(Icons.close, size: 13),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
        selectedColor: cs.primaryContainer,
        checkmarkColor: cs.onPrimaryContainer,
        showCheckmark: false,
      ),
    );
  }
}

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
class _BoardPlaceholder extends StatelessWidget {
  final String title;
  const _BoardPlaceholder({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHighest,
        scrolledUnderElevation: 0,
        title: Text(title),
      ),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.dashboard_outlined, size: 56, color: cs.outline),
          const SizedBox(height: 12),
          Text(context.l10n.boardNotSupported),
        ]),
      ),
    );
  }
}

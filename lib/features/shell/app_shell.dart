import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tabs/model_browser_screen.dart' show ModelBrowserSidebar, UserChip;
import '../../core/screen/screen.dart';
import '../views/screen_widget.dart';
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

    return Scaffold(
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
                  child: const ModelBrowserSidebar(),
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
    );
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
        builder: (_) => ScreenWidget(
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
          'Wähle einen Menüeintrag',
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

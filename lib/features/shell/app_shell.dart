import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tabs/model_browser_screen.dart';
import '../views/dynamic_form_screen.dart';
import '../views/list_view_screen.dart';
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
                      onClose: () => ref
                          .read(tabsProvider.notifier)
                          .closeTab(state.tabs[i].id),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(AppTab tab) {
    return Navigator(
      key: tab.navigatorKey,
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => ListViewScreen(
          model: tab.model,
          title: tab.title,
          initialDomain: tab.initialDomain,
          contextModel: tab.contextModel,
          contextDomain: tab.contextDomain,
          actionId: tab.actionId,
          onClose: () =>
              ref.read(tabsProvider.notifier).closeTab(tab.id),
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
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            tab.title,
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

// ─── DynamicFormScreen öffnen (von ListViewScreen aus) ───────────────────────
// Hilfsfunktion damit list_view_screen.dart und dynamic_form_screen.dart
// keine zirkulären Importe bekommen.

Future<void> pushFormScreen(
  BuildContext context, {
  required String model,
  required int recordId,
  required String title,
  required List<dynamic> screenDomain,
  bool replace = false,
}) {
  final route = MaterialPageRoute<void>(
    builder: (_) => DynamicFormScreen(
      model: model,
      recordId: recordId,
      title: title,
      screenDomain: screenDomain,
    ),
  );
  if (replace) {
    return Navigator.of(context).pushReplacement(route);
  } else {
    return Navigator.of(context).push(route);
  }
}

Future<void> pushListScreen(
  BuildContext context, {
  required String model,
  required String title,
  List<dynamic> initialDomain = const [],
  int? actionId,
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ListViewScreen(
      model: model,
      title: title,
      initialDomain: initialDomain,
      actionId: actionId,
    ),
  ));
}

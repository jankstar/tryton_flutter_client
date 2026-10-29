import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/screen/screen.dart';
import '../../core/wizard/wizard.dart';

/// One open tab in the app shell – a screen of a model (spec 8.1), opened
/// from a menu action, a toolbar action or a form.
class AppTab {
  final String id;
  final String title;

  /// Attributes of the tab's screen (model, views, domain, tabs, …).
  final ScreenAttributes attributes;

  /// A wizard shown in this tab (`window` wizards) instead of a screen.
  final TrytonWizard? wizard;

  /// Per-tab Navigator key – keeps the navigation stack alive in IndexedStack.
  final GlobalKey<NavigatorState> navigatorKey;

  AppTab({
    required this.id,
    required this.title,
    required this.attributes,
    this.wizard,
  }) : navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'tab-$id');

  String get model => attributes.model;

  /// Board views (`board`) are not supported yet (E33): placeholder.
  bool get isBoard =>
      wizard == null &&
      attributes.mode.isNotEmpty &&
      attributes.mode.first == 'board';
}

class TabsState {
  final List<AppTab> tabs;
  final int activeIndex;

  const TabsState({this.tabs = const [], this.activeIndex = -1});

  TabsState copyWith({List<AppTab>? tabs, int? activeIndex}) => TabsState(
        tabs: tabs ?? this.tabs,
        activeIndex: activeIndex ?? this.activeIndex,
      );

  AppTab? get activeTab =>
      activeIndex >= 0 && activeIndex < tabs.length ? tabs[activeIndex] : null;
}

/// Asks before a tab is closed (e.g. a modified form: save prompt, spec
/// 10.4); true = may close.
typedef TabCloseGuard = Future<bool> Function();

/// Provides the id of the tab to the screens inside its Navigator.
class TabScope extends InheritedWidget {
  final String tabId;
  const TabScope({super.key, required this.tabId, required super.child});

  static String? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TabScope>()?.tabId;

  @override
  bool updateShouldNotify(TabScope oldWidget) => oldWidget.tabId != tabId;
}

class TabsNotifier extends StateNotifier<TabsState> {
  TabsNotifier() : super(const TabsState());

  static const _uuid = Uuid();

  /// Close guards per tab (the screens of the tab's navigator stack).
  final Map<String, List<TabCloseGuard>> _closeGuards = {};

  void addCloseGuard(String tabId, TabCloseGuard guard) =>
      _closeGuards.putIfAbsent(tabId, () => []).add(guard);

  /// Whether the tab shows its first view (set by the tab's screen); only
  /// then an identical tab is activated instead of opened (spec 10.2).
  final Map<String, bool Function()> _firstView = {};

  void setFirstViewCheck(String tabId, bool Function()? check) {
    if (check == null) {
      _firstView.remove(tabId);
    } else {
      _firstView[tabId] = check;
    }
  }

  /// Closes all tabs, each after its guards (logout, spec 2.5.6/10.4);
  /// false when one was cancelled (that tab and the rest stay open).
  Future<bool> requestCloseAll() async {
    for (final tab in [...state.tabs].reversed) {
      if (!await requestCloseTab(tab.id)) {
        final idx = state.tabs.indexWhere((t) => t.id == tab.id);
        if (idx >= 0) activateTab(idx);
        return false;
      }
    }
    return true;
  }

  /// Next / previous tab (keyboard navigation, cyclic).
  void nextTab() {
    if (state.tabs.isEmpty) return;
    activateTab((state.activeIndex + 1) % state.tabs.length);
  }

  void previousTab() {
    if (state.tabs.isEmpty) return;
    activateTab(
        (state.activeIndex - 1 + state.tabs.length) % state.tabs.length);
  }

  void removeCloseGuard(String tabId, TabCloseGuard guard) =>
      _closeGuards[tabId]?.remove(guard);

  /// Closes the tab after all its guards agreed (topmost screen first).
  Future<bool> requestCloseTab(String id) async {
    for (final guard in [...?_closeGuards[id]].reversed) {
      if (!await guard()) return false;
    }
    closeTab(id);
    return true;
  }

  /// Opens a tab with [attributes], or for [model] with [initialDomain]
  /// (with [resId]: the form of that record first, SAO `mode: ['form']`).
  void openTab({
    required String title,
    String? model,
    List<dynamic> initialDomain = const [],
    int? resId,
    ScreenAttributes? attributes,
    TrytonWizard? wizard,
  }) {
    final attrs = attributes ??
        ScreenAttributes(
          model ?? wizard?.action ?? '',
          mode: resId != null ? const ['form', 'tree'] : const ['tree', 'form'],
          domain: List.unmodifiable(initialDomain),
          resId: resId,
        );
    // An identical tab at its first view is activated instead (SAO
    // `Tab.create` + `compare`, spec 10.2).
    if (wizard == null) {
      for (var i = 0; i < state.tabs.length; i++) {
        final tab = state.tabs[i];
        if (tab.wizard == null &&
            tab.attributes.sameAs(attrs) &&
            (_firstView[tab.id]?.call() ?? true)) {
          activateTab(i);
          return;
        }
      }
    }
    final tab = AppTab(
      id: _uuid.v4(),
      title: title,
      wizard: wizard,
      attributes: attrs,
    );
    final newTabs = [...state.tabs, tab];
    state = state.copyWith(tabs: newTabs, activeIndex: newTabs.length - 1);
  }

  void closeTab(String id) {
    final idx = state.tabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    _closeGuards.remove(id);
    _firstView.remove(id);
    final newTabs = [...state.tabs]..removeAt(idx);
    int newActive = state.activeIndex;
    if (newTabs.isEmpty) {
      newActive = -1;
    } else if (newActive >= newTabs.length) {
      newActive = newTabs.length - 1;
    } else if (newActive > idx) {
      newActive--;
    }
    state = state.copyWith(tabs: newTabs, activeIndex: newActive);
  }

  void activateTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    state = state.copyWith(activeIndex: index);
  }

  void clearAll() => state = const TabsState();
}

final tabsProvider = StateNotifierProvider<TabsNotifier, TabsState>((ref) {
  return TabsNotifier();
});

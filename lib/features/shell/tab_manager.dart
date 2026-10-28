import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// One open tab in the app shell – represents a list view opened from a menu action.
class AppTab {
  final String id;
  final String title;
  final String model;
  final List<dynamic> initialDomain;
  final String? contextModel;
  final String? contextDomain;
  final int? actionId;
  /// When set, the tab opens this record in a form instead of a list
  /// (SAO `mode: ['form']` with `res_id`).
  final int? resId;
  /// Per-tab Navigator key – keeps the navigation stack alive in IndexedStack.
  final GlobalKey<NavigatorState> navigatorKey;

  AppTab({
    required this.id,
    required this.title,
    required this.model,
    this.initialDomain = const [],
    this.contextModel,
    this.contextDomain,
    this.actionId,
    this.resId,
  }) : navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'tab-$id');
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

  void openTab({
    required String title,
    required String model,
    List<dynamic> initialDomain = const [],
    String? contextModel,
    String? contextDomain,
    int? actionId,
    int? resId,
  }) {
    final tab = AppTab(
      id: _uuid.v4(),
      title: title,
      model: model,
      initialDomain: List.unmodifiable(initialDomain),
      contextModel: contextModel,
      contextDomain: contextDomain,
      actionId: actionId,
      resId: resId,
    );
    final newTabs = [...state.tabs, tab];
    state = state.copyWith(tabs: newTabs, activeIndex: newTabs.length - 1);
  }

  void closeTab(String id) {
    final idx = state.tabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    _closeGuards.remove(id);
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

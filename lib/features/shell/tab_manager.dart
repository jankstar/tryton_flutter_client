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

class TabsNotifier extends StateNotifier<TabsState> {
  TabsNotifier() : super(const TabsState());

  static const _uuid = Uuid();

  void openTab({
    required String title,
    required String model,
    List<dynamic> initialDomain = const [],
    String? contextModel,
    String? contextDomain,
    int? actionId,
  }) {
    final tab = AppTab(
      id: _uuid.v4(),
      title: title,
      model: model,
      initialDomain: List.unmodifiable(initialDomain),
      contextModel: contextModel,
      contextDomain: contextDomain,
      actionId: actionId,
    );
    final newTabs = [...state.tabs, tab];
    state = state.copyWith(tabs: newTabs, activeIndex: newTabs.length - 1);
  }

  void closeTab(String id) {
    final idx = state.tabs.indexWhere((t) => t.id == id);
    if (idx < 0) return;
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

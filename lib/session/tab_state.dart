// lib/session/tab_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Manages the UI state for all open tabs, specifically their dirty status.
final tabStateProvider =
    StateNotifierProvider<TabStateNotifier, Map<String, bool>>((ref) {
      return TabStateNotifier();
    });

class TabStateNotifier extends StateNotifier<Map<String, bool>> {
  TabStateNotifier() : super({});

  void initTab(String tabId) {
    if (state.containsKey(tabId)) return;
    state = {...state, tabId: false};
  }

  void markDirty(String tabId) {
    if (state[tabId] == true) return;
    state = {...state, tabId: true};
  }

  void markClean(String tabId) {
    if (state[tabId] == false) return;
    state = {...state, tabId: false};
  }

  void removeTab(String tabId) {
    final newState = Map<String, bool>.from(state);
    newState.remove(tabId);
    state = newState;
  }
}

// lib/editor/tab_state_manager.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'editor_tab_models.dart';

/// REFACTOR: An abstract marker class for plugin-specific, "hot" tab state.
/// This state is managed for the lifetime of a tab but is not persisted.
abstract class TabState {
  // This class can be empty. It's used for type-checking and as a contract.
}

final tabStateManagerProvider =
    StateNotifierProvider<TabStateManager, Map<String, TabState>>((ref) {
  return TabStateManager();
});

class TabStateManager extends StateNotifier<Map<String, TabState>> {
  TabStateManager() : super({});

  /// Adds a new state object for a given tab.
  void addState(String tabUri, TabState tabState) {
    state = {...state, tabUri: tabState};
  }

  /// Removes and returns the state for a given tab.
  TabState? removeState(String tabUri) {
    final newState = Map<String, TabState>.from(state);
    final removedState = newState.remove(tabUri);
    state = newState;
    return removedState;
  }

  /// Retrieves the state for a specific tab.
  T?getState<T extends TabState>(String tabUri) {
    return state[tabUri] as T?;
  }
}
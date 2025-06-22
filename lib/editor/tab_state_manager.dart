import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'editor_tab_models.dart';

// REFACTOR: The abstract TabState marker class remains the same.
abstract class TabState {}

// NEW: A wrapper class to hold both the hot state and its dirty status.
class ManagedTabState {
  final TabState state;
  final bool isDirty;

  const ManagedTabState({required this.state, this.isDirty = false});

  ManagedTabState copyWith({TabState? state, bool? isDirty}) {
    return ManagedTabState(
      state: state ?? this.state,
      isDirty: isDirty ?? this.isDirty,
    );
  }
}

// REFACTOR: The provider now provides the consolidated manager.
final tabStateManagerProvider =
    StateNotifierProvider<TabStateManager, Map<String, ManagedTabState>>((ref) {
  return TabStateManager();
});

// REFACTOR: The StateNotifier is updated to manage the new wrapper class.
class TabStateManager extends StateNotifier<Map<String, ManagedTabState>> {
  TabStateManager() : super({});

  /// Adds a new state object for a given tab, initializing it as clean.
  void addState(String tabUri, TabState tabState) {
    state = {...state, tabUri: ManagedTabState(state: tabState)};
  }

  /// Removes and returns the state for a given tab.
  TabState? removeState(String tabUri) {
    final newState = Map<String, ManagedTabState>.from(state);
    final removed = newState.remove(tabUri);
    state = newState;
    return removed?.state;
  }

  /// Retrieves the state for a specific tab.
  T? getState<T extends TabState>(String tabUri) {
    return state[tabUri]?.state as T?;
  }

  /// Efficiently re-keys the hot state and its dirty status when a file is renamed.
  void rekeyState(String oldUri, String newUri) {
    if (state.containsKey(oldUri)) {
      final managedState = state[oldUri]!;
      final newState = Map<String, ManagedTabState>.from(state)
        ..remove(oldUri)
        ..[newUri] = managedState; // The entire object (including isDirty) is moved.
      state = newState;
    }
  }

  // NEW: Methods to manage dirty state, replacing the old TabStateNotifier.
  void markDirty(String tabUri) {
    if (state.containsKey(tabUri) && !state[tabUri]!.isDirty) {
      state = {
        ...state,
        tabUri: state[tabUri]!.copyWith(isDirty: true),
      };
    }
  }

  void markClean(String tabUri) {
    if (state.containsKey(tabUri) && state[tabUri]!.isDirty) {
      state = {
        ...state,
        tabUri: state[tabUri]!.copyWith(isDirty: false),
      };
    }
  }
}
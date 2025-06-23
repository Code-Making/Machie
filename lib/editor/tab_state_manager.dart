// lib/editor/tab_state_manager.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- HOT STATE MANAGEMENT ---

/// An abstract marker class for plugin-specific, "hot" tab state (e.g., controllers, images).
/// This state is managed for the lifetime of a tab but is not persisted.
abstract class TabState {}

/// Manages the "hot" state for all open tabs.
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
  T? getState<T extends TabState>(String tabUri) {
    return state[tabUri] as T?;
  }

  /// Efficiently re-keys the hot state when a file is renamed or moved.
  void rekeyState(String oldUri, String newUri) {
    if (state.containsKey(oldUri)) {
      final tabState = state[oldUri]!;
      final newState = Map<String, TabState>.from(state)
        ..remove(oldUri)
        ..[newUri] = tabState;
      state = newState;
    }
  }
}

// --- METADATA (BIDIRECTIONAL) STATE MANAGEMENT ---

/// Holds metadata about a tab, such as its dirty status.
class TabMetadata {
  final bool isDirty;
  const TabMetadata({this.isDirty = false});

  TabMetadata copyWith({bool? isDirty}) {
    return TabMetadata(isDirty: isDirty ?? this.isDirty);
  }
}

/// Manages metadata (like dirty status) for all open tabs.
final tabMetadataProvider =
    StateNotifierProvider<TabMetadataNotifier, Map<String, TabMetadata>>((ref) {
  return TabMetadataNotifier();
});

class TabMetadataNotifier extends StateNotifier<Map<String, TabMetadata>> {
  TabMetadataNotifier() : super({});

  /// Initializes metadata for a new tab.
  void initTab(String tabUri) {
    if (state.containsKey(tabUri)) return;
    state = {...state, tabUri: const TabMetadata()};
  }
  
  /// Removes metadata for a closed tab.
  void removeTab(String tabUri) {
    final newState = Map<String, TabMetadata>.from(state)..remove(tabUri);
    state = newState;
  }
  
  void markDirty(String tabUri) {
    if (state[tabUri]?.isDirty == false) {
      state = {
        ...state,
        tabUri: state[tabUri]!.copyWith(isDirty: true),
      };
    }
  }

  void markClean(String tabUri) {
    if (state[tabUri]?.isDirty == true) {
      state = {
        ...state,
        tabUri: state[tabUri]!.copyWith(isDirty: false),
      };
    }
  }

  /// Efficiently re-keys the metadata when a file is renamed or moved.
  void rekeyState(String oldUri, String newUri) {
    if (state.containsKey(oldUri)) {
      final metadata = state[oldUri]!;
      final newState = Map<String, TabMetadata>.from(state)
        ..remove(oldUri)
        ..[newUri] = metadata;
      state = newState;
    }
  }
}
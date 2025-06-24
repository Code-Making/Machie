// lib/editor/tab_state_manager.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    if (state.containsKey(tabUri) && state[tabUri]?.isDirty == false) {
      state = {...state, tabUri: state[tabUri]!.copyWith(isDirty: true)};
    }
  }

  void markClean(String tabUri) {
    if (state.containsKey(tabUri) && state[tabUri]?.isDirty == true) {
      state = {...state, tabUri: state[tabUri]!.copyWith(isDirty: false)};
    }
  }

  /// Efficiently re-keys the metadata when a file is renamed or moved.
  void rekeyState(String oldUri, String newUri) {
    if (state.containsKey(oldUri)) {
      final metadata = state[oldUri]!;
      final newState =
          Map<String, TabMetadata>.from(state)
            ..remove(oldUri)
            ..[newUri] = metadata;
      state = newState;
    }
  }
}

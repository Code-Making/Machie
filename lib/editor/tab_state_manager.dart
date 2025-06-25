// =========================================
// FILE: lib/editor/tab_state_manager.dart
// =========================================

// lib/editor/tab_state_manager.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/file_handler/file_handler.dart';

// REFACTORED: Metadata now holds the file and display properties.
@immutable
class TabMetadata {
  final DocumentFile file;
  final bool isDirty;

  const TabMetadata({required this.file, this.isDirty = false});

  String get title => file.name;

  TabMetadata copyWith({DocumentFile? file, bool? isDirty}) {
    return TabMetadata(
      file: file ?? this.file,
      isDirty: isDirty ?? this.isDirty,
    );
  }
}

// REFACTORED: The provider is now keyed by the stable tab ID.
final tabMetadataProvider =
    StateNotifierProvider<TabMetadataNotifier, Map<String, TabMetadata>>((ref) {
      return TabMetadataNotifier();
    });

class TabMetadataNotifier extends StateNotifier<Map<String, TabMetadata>> {
  TabMetadataNotifier() : super({});

  /// Initializes metadata for a new tab.
  void initTab(String tabId, DocumentFile file) {
    if (state.containsKey(tabId)) return;
    state = {...state, tabId: TabMetadata(file: file)};
  }

  /// Removes metadata for a closed tab.
  void removeTab(String tabId) {
    final newState = Map<String, TabMetadata>.from(state)..remove(tabId);
    state = newState;
  }

  void markDirty(String tabId) {
    if (state.containsKey(tabId) && state[tabId]?.isDirty == false) {
      state = {...state, tabId: state[tabId]!.copyWith(isDirty: true)};
    }
  }

  void markClean(String tabId) {
    if (state.containsKey(tabId) && state[tabId]?.isDirty == true) {
      state = {...state, tabId: state[tabId]!.copyWith(isDirty: false)};
    }
  }

  // REFACTORED: Method to update the file for a given tab ID.
  void updateFile(String tabId, DocumentFile newFile) {
     if (state.containsKey(tabId)) {
      state = {...state, tabId: state[tabId]!.copyWith(file: newFile)};
    }
  }

  // REFACTORED: This is no longer needed, as the key (tabId) is stable.
  // void rekeyState(String oldUri, String newUri) { ... }
}
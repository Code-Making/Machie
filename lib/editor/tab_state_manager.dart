// =========================================
// FILE: lib/editor/tab_state_manager.dart
// =========================================

// lib/editor/tab_state_manager.dart

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import '../data/file_handler/file_handler.dart';

import '../project/project_models.dart'; // ADDED

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

  // ADDED: toJson method for persistence.
  Map<String, dynamic> toJson() => {
    // We only need to persist the URI. The full DocumentFile will be
    // reconstituted from the URI on rehydration.
    'fileUri': file.uri,
    'isDirty': isDirty,
  };

  // ADDED: fromJson factory for rehydration.
  // Note: This creates a "partial" metadata object. The full DocumentFile
  // needs to be fetched separately. We'll use a placeholder for now.
  factory TabMetadata.fromJson(Map<String, dynamic> json) {
    return TabMetadata(
      file: IncompleteDocumentFile(uri: json['fileUri']),
      isDirty: json['isDirty'] ?? false,
    );
  }
}

// ... (TabMetadataNotifier is unchanged) ...
final tabMetadataProvider =
    StateNotifierProvider<TabMetadataNotifier, Map<String, TabMetadata>>((ref) {
      return TabMetadataNotifier();
    });

class TabMetadataNotifier extends StateNotifier<Map<String, TabMetadata>> {
  TabMetadataNotifier() : super({});

  void initTab(String tabId, DocumentFile file) {
    if (state.containsKey(tabId)) return;
    state = {...state, tabId: TabMetadata(file: file)};
  }

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

  void updateFile(String tabId, DocumentFile newFile) {
    if (state.containsKey(tabId)) {
      state = {...state, tabId: state[tabId]!.copyWith(file: newFile)};
    }
  }

  void clear() {
    state = {};
  }
}

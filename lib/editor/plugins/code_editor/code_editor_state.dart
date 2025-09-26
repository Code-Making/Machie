import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class CodeEditorState {
  final bool canUndo;
  final bool canRedo;
  final bool hasMark;
  final bool hasSelection; // <-- ADD THIS

  const CodeEditorState({
    this.canUndo = false,
    this.canRedo = false,
    this.hasMark = false,
    this.hasSelection = false, // <-- ADD THIS
  });

  CodeEditorState copyWith({
    bool? canUndo,
    bool? canRedo,
    bool? hasMark,
    bool? hasSelection, // <-- ADD THIS
  }) {
    return CodeEditorState(
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      hasMark: hasMark ?? this.hasMark,
      hasSelection: hasSelection ?? this.hasSelection, // <-- ADD THIS
    );
  }
}

class CodeEditorStateNotifier extends StateNotifier<CodeEditorState> {
  CodeEditorStateNotifier() : super(const CodeEditorState());

  void update({
    bool? canUndo,
    bool? canRedo,
    bool? hasMark,
    bool? hasSelection, // <-- ADD THIS
  }) {
    state = state.copyWith(
      canUndo: canUndo,
      canRedo: canRedo,
      hasMark: hasMark,
      hasSelection: hasSelection, // <-- ADD THIS
    );
  }
}

/// A provider family to create a unique state notifier for each open tab.
/// The tab's stable ID is used as the family parameter.
final codeEditorStateProvider = StateNotifierProvider.autoDispose
    .family<CodeEditorStateNotifier, CodeEditorState, String>(
      (ref, tabId) => CodeEditorStateNotifier(),
    );

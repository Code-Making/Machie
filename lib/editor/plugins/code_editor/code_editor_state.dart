import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents the reactive state of a single code editor instance.
@immutable
class CodeEditorState {
  final bool canUndo;
  final bool canRedo;
  final bool hasMark;

  const CodeEditorState({
    this.canUndo = false,
    this.canRedo = false,
    this.hasMark = false,
  });

  CodeEditorState copyWith({
    bool? canUndo,
    bool? canRedo,
    bool? hasMark,
  }) {
    return CodeEditorState(
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      hasMark: hasMark ?? this.hasMark,
    );
  }
}

/// Manages the state for a single code editor instance.
class CodeEditorStateNotifier extends StateNotifier<CodeEditorState> {
  CodeEditorStateNotifier() : super(const CodeEditorState());

  void update({bool? canUndo, bool? canRedo, bool? hasMark}) {
    state = state.copyWith(
      canUndo: canUndo,
      canRedo: canRedo,
      hasMark: hasMark,
    );
  }
}

/// A provider family to create a unique state notifier for each open tab.
/// The tab's stable ID is used as the family parameter.
final codeEditorStateProvider = StateNotifierProvider.autoDispose
    .family<CodeEditorStateNotifier, CodeEditorState, String>(
  (ref, tabId) => CodeEditorStateNotifier(),
);
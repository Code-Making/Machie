// =========================================
// UPDATED: lib/editor/plugins/code_editor/code_editor_state.dart
// =========================================

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Project imports:
import '../../services/text_editing_capability.dart';

@immutable
class CodeEditorCommandContext extends TextEditableCommandContext {
  final bool canUndo;
  final bool canRedo;
  final bool hasMark;

  const CodeEditorCommandContext({
    this.canUndo = false,
    this.canRedo = false,
    this.hasMark = false,
    required super.hasSelection,
    super.appBarOverride,
    super.appBarOverrideKey,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CodeEditorCommandContext &&
        other.canUndo == canUndo &&
        other.canRedo == canRedo &&
        other.hasMark == hasMark &&
        super == other;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, canUndo, canRedo, hasMark);
}

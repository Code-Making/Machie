// =========================================
// UPDATED: lib/editor/plugins/code_editor/code_editor_state.dart
// =========================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // ADDED: For Widget
import 'package:machine/editor/plugins/editor_command_context.dart';
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
  });

  // ADDED: operator == and hashCode for CodeEditorCommandContext
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CodeEditorCommandContext &&
           other.canUndo == canUndo &&
           other.canRedo == canRedo &&
           other.hasMark == hasMark &&
           super == other; // Delegate to TextEditableCommandContext's equality
  }

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        canUndo,
        canRedo,
        hasMark,
      );
}
// =========================================
// UPDATED: lib/editor/plugins/code_editor/code_editor_state.dart
// =========================================

import 'package:flutter/foundation.dart';
import 'package:machine/editor/plugins/editor_command_context.dart'; // Import the base class

@immutable
class CodeEditorCommandContext extends CommandContext {
  final bool canUndo;
  final bool canRedo;
  final bool hasMark;
  final bool hasSelection;

  const CodeEditorCommandContext({
    this.canUndo = false,
    this.canRedo = false,
    this.hasMark = false,
    this.hasSelection = false,
  });
}
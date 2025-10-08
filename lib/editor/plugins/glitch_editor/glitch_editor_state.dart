// =========================================
// NEW FILE: lib/editor/plugins/glitch_editor/glitch_editor_state.dart
// =========================================

import 'package:flutter/foundation.dart';
import 'package:machine/command/command_context.dart';

@immutable
class GlitchEditorCommandContext extends CommandContext {
  final bool canUndo;
  final bool canRedo;
  final bool isDirty;

  const GlitchEditorCommandContext({
    this.canUndo = false,
    this.canRedo = false,
    this.isDirty = false,
  });
}
// =========================================
// UPDATED: lib/editor/plugins/glitch_editor/glitch_editor_state.dart
// =========================================

import 'package:flutter/foundation.dart';

import '../../models/editor_command_context.dart';

@immutable
class GlitchEditorCommandContext extends CommandContext {
  final bool canUndo;
  final bool canRedo;

  const GlitchEditorCommandContext({
    this.canUndo = false,
    this.canRedo = false,
    // ADDED: Pass the (always null) override to the super constructor.
  }) : super(appBarOverride: null);
}

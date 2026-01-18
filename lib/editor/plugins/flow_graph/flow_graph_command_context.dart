// FILE: lib/editor/plugins/flow_graph/flow_graph_command_context.dart

import 'package:flutter/material.dart';
import 'package:machine/editor/models/editor_command_context.dart';

@immutable
class FlowGraphCommandContext extends CommandContext {
  final bool hasSelection;

  const FlowGraphCommandContext({
    required this.hasSelection,
    super.appBarOverride,
    super.appBarOverrideKey,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is FlowGraphCommandContext &&
          hasSelection == other.hasSelection;

  @override
  int get hashCode => Object.hash(super.hashCode, hasSelection);
}
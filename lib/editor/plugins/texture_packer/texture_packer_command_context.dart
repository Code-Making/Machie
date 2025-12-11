import 'package:flutter/material.dart';
import 'package:machine/editor/models/editor_command_context.dart';
import 'package:meta/meta.dart';

/// Defines the primary interaction modes for the Texture Packer editor.
enum TexturePackerMode {
  panZoom,
  slicing,
}

@immutable
class TexturePackerCommandContext extends CommandContext {
  final TexturePackerMode mode;
  final bool isSourceImagesPanelVisible;
  final bool isHierarchyPanelVisible;
  final bool hasSelection; // Is there a temporary drag-selection?

  const TexturePackerCommandContext({
    required this.mode,
    required this.isSourceImagesPanelVisible,
    required this.isHierarchyPanelVisible,
    required this.hasSelection,
    super.appBarOverride,
    super.appBarOverrideKey,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is TexturePackerCommandContext &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          isSourceImagesPanelVisible == other.isSourceImagesPanelVisible &&
          isHierarchyPanelVisible == other.isHierarchyPanelVisible &&
          hasSelection == other.hasSelection;

  @override
  int get hashCode =>
      super.hashCode ^
      mode.hashCode ^
      isSourceImagesPanelVisible.hashCode ^
      isHierarchyPanelVisible.hashCode ^
      hasSelection.hashCode;
}
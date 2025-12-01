// lib/editor/plugins/tiled_editor/tiled_command_context.dart

import 'package:flutter/material.dart';

import 'package:meta/meta.dart';

import '../../../models/editor_command_context.dart';
import 'tiled_paint_tools.dart';

@immutable
class TiledEditorCommandContext extends CommandContext {
  // General
  final TiledEditorMode mode;
  final bool isGridVisible;
  final bool canUndo;
  final bool canRedo;
  final bool isSnapToGridEnabled;
  final bool isPaletteVisible;
  final bool isLayersPanelVisible;

  // Sub-modes / Tools
  final TiledPaintMode paintMode;
  final ObjectTool activeObjectTool;
  final bool hasPolygonPoints;
  // Object-specific state
  final bool isObjectSelected;
  final bool hasFloatingTileSelection;

  const TiledEditorCommandContext({
    required this.mode,
    required this.isGridVisible,
    required this.canUndo,
    required this.canRedo,
    required this.isSnapToGridEnabled,
    required this.isPaletteVisible,
    required this.isLayersPanelVisible,
    required this.paintMode,
    required this.activeObjectTool,
    required this.hasPolygonPoints,
    required this.isObjectSelected,
    required this.hasFloatingTileSelection, // Add to constructor
    super.appBarOverride,
    super.appBarOverrideKey,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is TiledEditorCommandContext &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          isGridVisible == other.isGridVisible &&
          canUndo == other.canUndo &&
          canRedo == other.canRedo &&
          isSnapToGridEnabled == other.isSnapToGridEnabled &&
          isPaletteVisible == other.isPaletteVisible &&
          isLayersPanelVisible == other.isLayersPanelVisible &&
          paintMode == other.paintMode &&
          activeObjectTool == other.activeObjectTool &&
          hasPolygonPoints == other.hasPolygonPoints &&
          isObjectSelected == other.isObjectSelected &&
          hasFloatingTileSelection == other.hasFloatingTileSelection; // Add to comparison

  @override
  int get hashCode =>
      super.hashCode ^
      mode.hashCode ^
      isGridVisible.hashCode ^
      canUndo.hashCode ^
      canRedo.hashCode ^
      isSnapToGridEnabled.hashCode ^
      isPaletteVisible.hashCode ^
      isLayersPanelVisible.hashCode ^
      paintMode.hashCode ^
      activeObjectTool.hashCode ^
      hasPolygonPoints.hashCode ^
      isObjectSelected.hashCode ^
      hasFloatingTileSelection.hashCode;
}

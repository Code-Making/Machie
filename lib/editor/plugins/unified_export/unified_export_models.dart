// FILE: lib/editor/plugins/unified_export/unified_export_models.dart

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

enum ExportNodeType { tmx, tpacker, flowGraph, image, unknown }

class DependencyNode {
  final String sourcePath;
  final String destinationPath;
  final ExportNodeType type;
  final List<DependencyNode> children;
  bool included;

  DependencyNode({
    required this.sourcePath,
    required this.destinationPath,
    required this.type,
    this.children = const [],
    this.included = true,
  });
}

class PackableSlice {
  final String id; // Unique ID (e.g., "tileset_name::gid::15" or "sprite_name")
  final ui.Image sourceImage;
  final Rect sourceRect;
  final String originalName; // For metadata (frame name)
  
  // Alignment info if this slice comes from a grid
  final bool isGridTile;
  final int? originalGid;

  PackableSlice({
    required this.id,
    required this.sourceImage,
    required this.sourceRect,
    required this.originalName,
    this.isGridTile = false,
    this.originalGid,
  });
}

class AtlasPage {
  final int width;
  final int height;
  final Uint8List pngBytes;
  final Map<String, Rect> packedRects; // SliceID -> Destination Rect

  AtlasPage({
    required this.width,
    required this.height,
    required this.pngBytes,
    required this.packedRects,
  });
}

class ExportResult {
  final List<AtlasPage> atlases;
  final Map<String, dynamic> atlasMetaJson;
  final Map<String, int> gidRemapTable; // Old GID (per tileset context) -> New Global GID

  ExportResult({
    required this.atlases,
    required this.atlasMetaJson,
    required this.gidRemapTable,
  });
}

class ExportLog {
  final String message;
  final bool isError;
  final DateTime timestamp;

  ExportLog(this.message, {this.isError = false}) : timestamp = DateTime.now();
}
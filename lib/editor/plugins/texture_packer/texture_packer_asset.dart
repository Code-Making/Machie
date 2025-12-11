import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project/project_repository.dart';

import 'texture_packer_models.dart';

// -----------------------------------------------------------------------------
//region Spritesheet Data Models (Dart equivalent of the .ts interfaces)
// -----------------------------------------------------------------------------

@immutable
class SpritesheetFrameDataModel {
  final Map<String, int> frame;
  final Map<String, int>? sourceSize;
  // Add other fields from the .ts interface as needed (trimmed, rotated, etc.)

  const SpritesheetFrameDataModel({required this.frame, this.sourceSize});

  Map<String, dynamic> toJson() => {
        'frame': frame,
        if (sourceSize != null) 'sourceSize': sourceSize,
      };
}

@immutable
class SpritesheetDataModel {
  final Map<String, SpritesheetFrameDataModel> frames;
  final Map<String, dynamic> meta;
  final Map<String, List<String>>? animations;

  const SpritesheetDataModel({required this.frames, required this.meta, this.animations});

  Map<String, dynamic> toJson() => {
        'frames': frames.map((key, value) => MapEntry(key, value.toJson())),
        'meta': meta,
        if (animations != null) 'animations': animations,
      };
}

//endregion

// -----------------------------------------------------------------------------
//region Texture Packer Asset Data
// -----------------------------------------------------------------------------

/// A custom AssetData type representing a fully packed, in-memory atlas.
///
/// This is the runtime asset that other parts of an application could use.
/// It contains the generated spritesheet image and its corresponding JSON data.
class TexturePackerAssetData extends AssetData {
  final ui.Image atlasImage;
  final SpritesheetDataModel spritesheetData;

  const TexturePackerAssetData({required this.atlasImage, required this.spritesheetData});
}

//endregion

// -----------------------------------------------------------------------------
//region Texture Packer Asset Loader
// -----------------------------------------------------------------------------

/// Loads a `.tpacker` file, resolves its source image dependencies,
/// and builds a `TexturePackerAssetData` in memory.
class TexturePackerAssetLoader implements AssetLoader<TexturePackerAssetData>, IDependentAssetLoader<TexturePackerAssetData> {
  @override
  bool canLoad(ProjectDocumentFile file) {
    return file.name.toLowerCase().endsWith('.tpacker');
  }

  /// This method is called first by the AssetNotifier to discover dependencies.
  @override
  Future<Set<String>> getDependencies(Ref ref, ProjectDocumentFile file, ProjectRepository repo) async {
    final jsonString = await repo.readFile(file.uri);
    if (jsonString.trim().isEmpty) return const {};
    
    final packerProject = TexturePackerProject.fromJson(jsonDecode(jsonString));
    
    // Since we store project-relative paths, we can just return them directly.
    // The assetDataProvider will correctly resolve them relative to the project root.
    return packerProject.sourceImages.map((e) => e.path).toSet();
  }

  @override
  Future<TexturePackerAssetData> load(
    Ref ref,
    ProjectDocumentFile file,
    ProjectRepository repo,
  ) async {
    final jsonString = await repo.readFile(file.uri);
    final packerProject = TexturePackerProject.fromJson(jsonDecode(jsonString));

    final sourceImageAssets = <int, ui.Image>{};
    for (int i = 0; i < packerProject.sourceImages.length; i++) {
      final sourcePath = packerProject.sourceImages[i].path;
      
      // The 'sourcePath' is project-relative, which is exactly what
      // the assetDataProvider family expects.
      final assetData = ref.read(assetDataProvider(sourcePath)).value;

      if (assetData is ImageAssetData) {
        sourceImageAssets[i] = assetData.image;
      } else {
        throw Exception('Dependency asset "$sourcePath" was not loaded or is not a valid image.');
      }
    }

    final packResult = await _packAtlasInMemory(packerProject, sourceImageAssets);

    return TexturePackerAssetData(
      atlasImage: packResult.atlasImage,
      spritesheetData: packResult.spritesheetData,
    );
  }

  /// Placeholder for the in-memory packing logic (Phase 4).
  /// This function simulates the bin-packing and atlas drawing process.
  Future<({ui.Image atlasImage, SpritesheetDataModel spritesheetData})> _packAtlasInMemory(
    TexturePackerProject project,
    Map<int, ui.Image> sourceImages,
  ) async {
    // --- This section is a simplified stand-in for a real bin-packing algorithm ---
    const int atlasWidth = 1024; // Fixed width for simplicity
    final Map<String, SpritesheetFrameDataModel> frames = {};
    
    // In a real implementation, you would use a bin-packing algorithm to determine
    // the positions. Here, we'll just lay them out in a simple grid.
    int currentX = 0;
    int currentY = 0;
    int maxRowHeight = 0;

    // Use a PictureRecorder to draw the new atlas image.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    // TODO: Implement the recursive traversal of the project.tree to process sprites.
    // For now, we'll assume a flat list of sprites for demonstration.
    
    // (A real implementation would traverse `project.tree` and use `project.definitions`)

    // This is just a placeholder to create a dummy atlas.
    final placeholderRect = ui.Rect.fromLTWH(0, 0, 64, 64);
    canvas.drawRect(placeholderRect, ui.Paint()..color = const ui.Color(0xFFFF00FF));
    frames['placeholder'] = SpritesheetFrameDataModel(
      frame: {'x': 0, 'y': 0, 'w': 64, 'h': 64},
      sourceSize: {'w': 64, 'h': 64},
    );

    final int atlasHeight = currentY + maxRowHeight;
    // --- End of simplified packing logic ---

    final picture = recorder.endRecording();
    final atlasImage = await picture.toImage(atlasWidth, atlasHeight > 0 ? atlasHeight : 64);

    final spritesheetData = SpritesheetDataModel(
      frames: frames,
      // TODO: Process animations from project.tree/definitions
      animations: {},
      meta: {
        'app': 'Machine Texture Packer',
        'version': '1.0',
        'image': 'atlas.png', // This would be dynamic in the export phase
        'format': 'RGBA8888',
        'size': {'w': atlasImage.width, 'h': atlasImage.height},
        'scale': '1',
      },
    );

    return (atlasImage: atlasImage, spritesheetData: spritesheetData);
  }
}
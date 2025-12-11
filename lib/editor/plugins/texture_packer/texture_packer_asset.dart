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
    // 1. COLLECT: Traverse the tree to find all sprites and their data.
    final spritesToPack = <_SpriteToPack>[];
    final Map<String, String> nodeIdToFullName = {};

    void collectSprites(PackerItemNode node, String currentPath) {
      final nodeName = (node.id == 'root') ? '' : node.name;
      final newPath = (currentPath.isEmpty) ? nodeName : '$currentPath/$nodeName';

      if (node.type == PackerItemType.sprite) {
        final def = project.definitions[node.id] as SpriteDefinition?;
        if (def != null) {
          final sourceConfig = project.sourceImages[def.sourceImageIndex];
          final sourceImage = sourceImages[def.sourceImageIndex];
          if (sourceImage != null) {
            final slicing = sourceConfig.slicing;
            final left = slicing.margin + def.gridRect.x * (slicing.tileWidth + slicing.padding);
            final top = slicing.margin + def.gridRect.y * (slicing.tileHeight + slicing.padding);
            final width = def.gridRect.width * slicing.tileWidth + (def.gridRect.width - 1) * slicing.padding;
            final height = def.gridRect.height * slicing.tileHeight + (def.gridRect.height - 1) * slicing.padding;

            spritesToPack.add(_SpriteToPack(
              nodeId: node.id,
              fullName: newPath,
              sourceImage: sourceImage,
              sourceRect: Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble()),
            ));
            nodeIdToFullName[node.id] = newPath;
          }
        }
      }

      for (final child in node.children) {
        collectSprites(child, newPath);
      }
    }

    collectSprites(project.tree, '');

    // 2. PACK: Arrange the sprites into an atlas using a simple shelf algorithm.
    const int atlasWidth = 2048; // A common atlas width
    final Map<_SpriteToPack, Rect> packedLayout = {};

    if (spritesToPack.isNotEmpty) {
      // Sort sprites by height (descending) for better packing.
      spritesToPack.sort((a, b) => b.sourceRect.height.compareTo(a.sourceRect.height));

      int currentX = 0;
      int currentY = 0;
      int currentRowHeight = 0;

      for (final sprite in spritesToPack) {
        if (currentX + sprite.sourceRect.width > atlasWidth) {
          currentX = 0;
          currentY += currentRowHeight;
          currentRowHeight = 0;
        }

        packedLayout[sprite] = Rect.fromLTWH(
          currentX.toDouble(),
          currentY.toDouble(),
          sprite.sourceRect.width,
          sprite.sourceRect.height,
        );

        currentX += sprite.sourceRect.width.toInt();
        currentRowHeight = max(currentRowHeight, sprite.sourceRect.height.toInt());
      }
    }

    // 3. DRAW: Render the final atlas image.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    int finalAtlasHeight = 0;
    packedLayout.forEach((sprite, destRect) {
      canvas.drawImageRect(sprite.sourceImage, sprite.sourceRect, destRect, paint);
      finalAtlasHeight = max(finalAtlasHeight, destRect.bottom.toInt());
    });

    final picture = recorder.endRecording();
    // Ensure minimum size of 1x1 to prevent errors with empty atlases.
    final atlasImage = await picture.toImage(atlasWidth, max(1, finalAtlasHeight));

    // 4. GENERATE METADATA: Create the final JSON structure.
    final Map<String, SpritesheetFrameDataModel> frames = {};
    packedLayout.forEach((sprite, destRect) {
      frames[sprite.fullName] = SpritesheetFrameDataModel(
        frame: {
          'x': destRect.left.toInt(),
          'y': destRect.top.toInt(),
          'w': destRect.width.toInt(),
          'h': destRect.height.toInt(),
        },
        sourceSize: {
          'w': sprite.sourceRect.width.toInt(),
          'h': sprite.sourceRect.height.toInt(),
        },
      );
    });

    final Map<String, List<String>> animations = {};
    void collectAnimations(PackerItemNode node, String currentPath) {
      final nodeName = (node.id == 'root') ? '' : node.name;
      final newPath = (currentPath.isEmpty) ? nodeName : '$currentPath/$nodeName';

      if (node.type == PackerItemType.animation) {
        final def = project.definitions[node.id] as AnimationDefinition?;
        if (def != null) {
          animations[newPath] = def.frameIds
              .map((id) => nodeIdToFullName[id])
              .where((name) => name != null)
              .cast<String>()
              .toList();
        }
      }
      for (final child in node.children) {
        collectAnimations(child, newPath);
      }
    }

    collectAnimations(project.tree, '');
    
    final spritesheetData = SpritesheetDataModel(
      frames: frames,
      animations: animations,
      meta: {
        'app': 'Machine Texture Packer',
        'version': '1.0',
        'image': 'atlas.png', // This is a placeholder name for the in-memory asset
        'format': 'RGBA8888',
        'size': {'w': atlasImage.width, 'h': atlasImage.height},
        'scale': '1',
      },
    );

    return (atlasImage: atlasImage, spritesheetData: spritesheetData);
  }
}
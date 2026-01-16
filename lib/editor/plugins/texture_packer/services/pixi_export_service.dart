import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/utils/texture_packer_algo.dart';
import 'package:machine/logs/logs_provider.dart';

final pixiExportServiceProvider = Provider<PixiExportService>((ref) {
  return PixiExportService(ref);
});

class PixiExportService {
  final Ref _ref;

  PixiExportService(this._ref);

  Future<void> export({
    required TexturePackerProject project,
    required Map<String, AssetData> assetDataMap,
    required String destinationFolderUri,
    required String fileName, // Base name without extension
  }) async {
    final talker = _ref.read(talkerProvider);
    final repo = _ref.read(projectRepositoryProvider)!;

    talker.info('Starting Texture Packer export for $fileName...');

    // 1. Collect all sprites and resolve their source images
    final packerItems = <PackerInputItem<SpriteDefinition>>[];
    final spriteNames = <String, String>{}; // Definition ID -> Sprite Name

    // Helper to find source config
    SourceImageConfig? findSourceConfig(String id) {
      SourceImageConfig? traverse(SourceImageNode node) {
        if (node.id == id && node.type == SourceNodeType.image) return node.content;
        for (final child in node.children) {
          final result = traverse(child);
          if (result != null) return result;
        }
        return null;
      }
      return traverse(project.sourceImagesRoot);
    }

    void collectSprites(PackerItemNode node) {
      if (node.type == PackerItemType.sprite) {
        final def = project.definitions[node.id];
        if (def is SpriteDefinition) {
          final sourceConfig = findSourceConfig(def.sourceImageId);
          if (sourceConfig != null) {
            // Validate asset is loaded
            if (assetDataMap.containsKey(sourceConfig.path) &&
                assetDataMap[sourceConfig.path] is ImageAssetData) {
              
              final pxRect = _calculatePixelRect(sourceConfig, def.gridRect);
              
              packerItems.add(PackerInputItem(
                width: pxRect.width,
                height: pxRect.height,
                data: def,
              ));
              spriteNames[node.id] = node.name;
            } else {
              talker.warning('Skipping sprite ${node.name}: Asset not loaded (${sourceConfig.path})');
            }
          }
        }
      } else {
        for (final child in node.children) collectSprites(child);
      }
    }
    collectSprites(project.tree);

    if (packerItems.isEmpty) {
      throw Exception('No valid sprites found to export.');
    }

    // 2. Run Packing
    final packer = MaxRectsPacker(padding: 2);
    final packedResult = packer.pack(packerItems);

    // 3. Generate Atlas Image (PNG)
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    
    // We don't clear with a color, preserving transparency.
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    final framesData = <String, Map<String, dynamic>>{};

    for (final item in packedResult.items) {
      final def = item.data;
      final sourceConfig = findSourceConfig(def.sourceImageId)!;
      final asset = assetDataMap[sourceConfig.path] as ImageAssetData;
      
      final srcRect = _calculatePixelRect(sourceConfig, def.gridRect);
      final dstRect = ui.Rect.fromLTWH(item.x, item.y, item.width, item.height);

      // Draw to atlas
      canvas.drawImageRect(asset.image, srcRect, dstRect, paint);

      // Prepare JSON data for this frame
      // Reverse lookup name (inefficient but safe)
      final nodeId = project.definitions.entries.firstWhere((e) => e.value == def).key;
      final name = spriteNames[nodeId] ?? 'unknown';

      framesData[name] = {
        "frame": {"x": item.x.toInt(), "y": item.y.toInt(), "w": item.width.toInt(), "h": item.height.toInt()},
        "rotated": false,
        "trimmed": false,
        "spriteSourceSize": {"x": 0, "y": 0, "w": item.width.toInt(), "h": item.height.toInt()},
        "sourceSize": {"w": item.width.toInt(), "h": item.height.toInt()},
        // Pivot defaults to center (0.5, 0.5) in many engines, or 0,0. 
        // We'll leave it as 0.5, 0.5 or optional based on generic usage.
        "anchor": {"x": 0.5, "y": 0.5} 
      };
    }

    final picture = recorder.endRecording();
    final atlasImage = await picture.toImage(packedResult.width.toInt(), packedResult.height.toInt());
    final pngBytes = await atlasImage.toByteData(format: ui.ImageByteFormat.png);

    if (pngBytes == null) {
      throw Exception('Failed to encode atlas image.');
    }

    // 4. Generate JSON Data
    final animationsData = <String, List<String>>{};
    
    void collectAnimations(PackerItemNode node) {
      if (node.type == PackerItemType.animation) {
        final frameNames = node.children
            .where((c) => c.type == PackerItemType.sprite)
            .map((c) => c.name)
            .toList();
        
        if (frameNames.isNotEmpty) {
          animationsData[node.name] = frameNames;
        }
      }
      for (final child in node.children) collectAnimations(child);
    }
    collectAnimations(project.tree);

    final jsonOutput = {
      "frames": framesData,
      "animations": animationsData,
      "meta": {
        "app": "Machine Editor",
        "version": "1.0",
        "image": "$fileName.png",
        "format": "RGBA8888",
        "size": {"w": packedResult.width.toInt(), "h": packedResult.height.toInt()},
        "scale": "1"
      }
    };

    // 5. Write Files
    // Write PNG
    await repo.createDocumentFile(
      destinationFolderUri,
      '$fileName.png',
      initialBytes: pngBytes.buffer.asUint8List(),
      overwrite: true,
    );

    // Write JSON
    const encoder = JsonEncoder.withIndent('  ');
    await repo.createDocumentFile(
      destinationFolderUri,
      '$fileName.json',
      initialContent: encoder.convert(jsonOutput),
      overwrite: true,
    );

    talker.info('Texture Packer export completed successfully.');
  }

  ui.Rect _calculatePixelRect(SourceImageConfig config, GridRect grid) {
    final s = config.slicing;
    final left = s.margin + grid.x * (s.tileWidth + s.padding);
    final top = s.margin + grid.y * (s.tileHeight + s.padding);
    final width = grid.width * s.tileWidth + (grid.width - 1) * s.padding;
    final height = grid.height * s.tileHeight + (grid.height - 1) * s.padding;
    return ui.Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble());
  }
}
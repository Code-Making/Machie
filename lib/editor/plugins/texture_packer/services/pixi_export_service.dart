// FILE: lib/editor/plugins/texture_packer/services/pixi_export_service.dart

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/utils/texture_packer_algo.dart';
import 'package:machine/logs/logs_provider.dart';
import '../texture_packer_asset_resolver.dart';

final pixiExportServiceProvider = Provider<PixiExportService>((ref) {
  return PixiExportService(ref);
});

class PixiExportService {
  final Ref _ref;

  PixiExportService(this._ref);

  Future<void> export({
    required TexturePackerProject project,
    required TexturePackerAssetResolver resolver,
    required String destinationFolderUri,
    required String fileName,
  }) async {
    final talker = _ref.read(talkerProvider);
    final repo = _ref.read(projectRepositoryProvider)!;

    talker.info('Starting Texture Packer export for $fileName...');

    final packerItems = <PackerInputItem<SpriteDefinition>>[];
    final spriteNames = <String, String>{};

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

    // 1. Collect Sprites and Resolve Images via Resolver
    void collectSprites(PackerItemNode node) {
      if (node.type == PackerItemType.sprite) {
        final def = project.definitions[node.id];
        if (def is SpriteDefinition) {
          final sourceConfig = findSourceConfig(def.sourceImageId);
          if (sourceConfig != null) {
            // KEY CHANGE: Use resolver to get dimensions without loading full asset data map manually
            final image = resolver.getImage(sourceConfig.path);
            
            if (image != null) {
              final pxRect = _calculatePixelRect(sourceConfig, def.gridRect);
              
              packerItems.add(PackerInputItem(
                width: pxRect.width,
                height: pxRect.height,
                data: def,
              ));
              spriteNames[node.id] = node.name;
            } else {
              talker.warning('Skipping sprite ${node.name}: Image not found for path "${sourceConfig.path}"');
            }
          }
        }
      } else {
        for (final child in node.children) collectSprites(child);
      }
    }
    collectSprites(project.tree);

    if (packerItems.isEmpty) {
      throw Exception('No valid sprites found to export. Check source image paths.');
    }

    // 2. Pack
    final packer = MaxRectsPacker(padding: 2);
    final packedResult = packer.pack(packerItems);

    // 3. Draw
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    final framesData = <String, Map<String, dynamic>>{};

    for (final item in packedResult.items) {
      final def = item.data;
      final sourceConfig = findSourceConfig(def.sourceImageId)!;
      
      // KEY CHANGE: Retrieve image via resolver for drawing
      final image = resolver.getImage(sourceConfig.path)!;
      
      final srcRect = _calculatePixelRect(sourceConfig, def.gridRect);
      final dstRect = ui.Rect.fromLTWH(item.x, item.y, item.width, item.height);

      canvas.drawImageRect(image, srcRect, dstRect, paint);

      final nodeId = project.definitions.entries.firstWhere((e) => e.value == def).key;
      final name = spriteNames[nodeId] ?? 'unknown';

      framesData[name] = {
        "frame": {"x": item.x.toInt(), "y": item.y.toInt(), "w": item.width.toInt(), "h": item.height.toInt()},
        "rotated": false,
        "trimmed": false,
        "spriteSourceSize": {"x": 0, "y": 0, "w": item.width.toInt(), "h": item.height.toInt()},
        "sourceSize": {"w": item.width.toInt(), "h": item.height.toInt()},
        "anchor": {"x": 0.5, "y": 0.5}
      };
    }

    final picture = recorder.endRecording();
    final atlasImage = await picture.toImage(packedResult.width.toInt(), packedResult.height.toInt());
    final pngBytes = await atlasImage.toByteData(format: ui.ImageByteFormat.png);

    if (pngBytes == null) {
      throw Exception('Failed to encode atlas image.');
    }

    // 4. Metadata
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

    // 5. Save Files
    await repo.createDocumentFile(
      destinationFolderUri,
      '$fileName.png',
      initialBytes: pngBytes.buffer.asUint8List(),
      overwrite: true,
    );

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
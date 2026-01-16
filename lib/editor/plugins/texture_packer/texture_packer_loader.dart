import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/utils/texture_packer_algo.dart';

class TexturePackerAssetLoader implements IDependentAssetLoader<TexturePackerAssetData> {
  
  @override
  bool canLoad(ProjectDocumentFile file) {
    return file.name.toLowerCase().endsWith('.tpacker');
  }

  @override
  Future<Set<String>> getDependencies(Ref ref, ProjectDocumentFile file, ProjectRepository repo) async {
    final content = await repo.readFile(file.uri);
    if (content.trim().isEmpty) return {};

    try {
      final json = jsonDecode(content);
      final project = TexturePackerProject.fromJson(json);
      
      final dependencies = <String>{};
      
      // Traverse source tree to find all image paths
      void collectPaths(SourceImageNode node) {
        if (node.type == SourceNodeType.image && node.content != null) {
          if (node.content!.path.isNotEmpty) {
            dependencies.add(node.content!.path);
          }
        }
        for (final child in node.children) collectPaths(child);
      }
      collectPaths(project.sourceImagesRoot);
      
      return dependencies;
    } catch (e) {
      // If parsing fails, we have no dependencies.
      return {};
    }
  }

  @override
  Future<TexturePackerAssetData> load(Ref ref, ProjectDocumentFile file, ProjectRepository repo) async {
    final content = await repo.readFile(file.uri);
    final project = TexturePackerProject.fromJson(jsonDecode(content));

    // 1. Resolve Dependencies (Source Images)
    // We assume these are already loaded by the AssetNotifier before load() is called.
    final Map<String, ui.Image> sourceImages = {};
    
    // Helper to recursively find image paths again (same as getDependencies)
    // We map the path to the loaded ui.Image.
    void collectImages(SourceImageNode node) async {
      if (node.type == SourceNodeType.image && node.content != null) {
        final path = node.content!.path;
        if (path.isNotEmpty) {
          // Use ref.read because dependencies are guaranteed to be ready
          final assetData = await ref.read(assetDataProvider(path).future);
          if (assetData is ImageAssetData) {
            sourceImages[node.id] = assetData.image; // Map by Node ID for easy lookup
          }
        }
      }
      for (final child in node.children) collectImages(child);
    }
    collectImages(project.sourceImagesRoot);
    
    // Wait a tick just to ensure sync access isn't an issue, although ref.read should be fine
    // if getDependencies worked correctly. In a strict sense, we might need to await
    // individual provider futures if they weren't 'watched' but 'read' inside build.
    // However, assetDataProvider logic ensures they are watched.
    
    // 2. Prepare Items for Packing
    final packerItems = <PackerInputItem<SpriteDefinition>>[];
    final spriteNames = <String, String>{}; // Definition ID -> Sprite Name

    void collectSprites(PackerItemNode node) {
      if (node.type == PackerItemType.sprite) {
        final def = project.definitions[node.id];
        if (def is SpriteDefinition) {
          final sourceImage = sourceImages[def.sourceImageId];
          if (sourceImage != null) {
            final sourceConfig = _findSourceConfig(project.sourceImagesRoot, def.sourceImageId);
            if (sourceConfig != null) {
              final pxRect = _calculatePixelRect(sourceConfig, def.gridRect);
              
              packerItems.add(PackerInputItem(
                width: pxRect.width,
                height: pxRect.height,
                data: def, // We store the definition to link back later
              ));
              spriteNames[node.id] = node.name;
            }
          }
        }
      } else {
        // Recursively check children (Folders, Animations)
        for(final child in node.children) collectSprites(child);
      }
    }
    collectSprites(project.tree);

    // 3. Run Packing Algorithm
    final packer = MaxRectsPacker(padding: 2); // 2px padding for safety
    final result = packer.pack(packerItems);

    // 4. Build Result Data
    final frames = <String, TexturePackerSpriteData>{};
    final animations = <String, List<String>>{};

    // 4a. Map packed items back to their names and source data
    for (final item in result.items) {
      // Find the node ID associated with this definition
      // (Inefficient reverse lookup, but dataset is usually small < 1000 sprites)
      final nodeId = project.definitions.entries
          .firstWhere((e) => e.value == item.data)
          .key;
          
      final name = spriteNames[nodeId] ?? 'unknown';
      final def = item.data as SpriteDefinition;
      final sourceImage = sourceImages[def.sourceImageId]!;
      final sourceConfig = _findSourceConfig(project.sourceImagesRoot, def.sourceImageId)!;
      final sourceRect = _calculatePixelRect(sourceConfig, def.gridRect);

      frames[name] = TexturePackerSpriteData(
        name: name,
        sourceImage: sourceImage,
        sourceRect: sourceRect,
        packedRect: ui.Rect.fromLTWH(item.x, item.y, item.width, item.height),
      );
    }

    // 4b. Collect Animations
    void collectAnimations(PackerItemNode node) {
      if (node.type == PackerItemType.animation) {
        final frameNames = node.children
            .where((c) => c.type == PackerItemType.sprite)
            .map((c) => c.name)
            .toList();
        
        if (frameNames.isNotEmpty) {
          animations[node.name] = frameNames;
        }
      }
      for(final child in node.children) collectAnimations(child);
    }
    collectAnimations(project.tree);

    return TexturePackerAssetData(
      frames: frames,
      animations: animations,
      metaSize: ui.Size(result.width, result.height),
    );
  }

  // --- Helpers ---

  SourceImageConfig? _findSourceConfig(SourceImageNode node, String id) {
    if (node.id == id && node.type == SourceNodeType.image) return node.content;
    for (final child in node.children) {
      final res = _findSourceConfig(child, id);
      if (res != null) return res;
    }
    return null;
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
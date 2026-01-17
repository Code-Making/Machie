// FILE: lib/editor/plugins/texture_packer/texture_packer_loader.dart

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/utils/texture_packer_algo.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/project/project_settings_notifier.dart';

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
      final projectRootUri = ref.read(currentProjectProvider)!.rootUri;
      final tpackerPath = repo.fileHandler.getPathForDisplay(file.uri, relativeTo: projectRootUri);

      final json = jsonDecode(content);
      final project = TexturePackerProject.fromJson(json);
      
      final dependencies = <String>{};
      
      void collectPaths(SourceImageNode node) {
        if (node.type == SourceNodeType.image && node.content != null) {
          if (node.content!.path.isNotEmpty) {
            final resolvedPath = repo.resolveRelativePath(tpackerPath, node.content!.path);
            dependencies.add(resolvedPath);
          }
        }
        for (final child in node.children) collectPaths(child);
      }
      collectPaths(project.sourceImagesRoot);
      
      return dependencies;
    } catch (e) {
      return {};
    }
  }

  @override
  Future<TexturePackerAssetData> load(Ref ref, ProjectDocumentFile file, ProjectRepository repo) async {
    final content = await repo.readFile(file.uri);
    final project = TexturePackerProject.fromJson(jsonDecode(content));
    
    final projectRootUri = ref.read(currentProjectProvider)!.rootUri;
    final tpackerPath = repo.fileHandler.getPathForDisplay(file.uri, relativeTo: projectRootUri);

    final Map<String, ui.Image> sourceImages = {};
    
    
    final sourceNodes = <SourceImageNode>[];
    void collectNodes(SourceImageNode node) {
      if (node.type == SourceNodeType.image && node.content != null) {
        sourceNodes.add(node);
      }
      for (final child in node.children) collectNodes(child);
    }
    collectNodes(project.sourceImagesRoot);

    for (final node in sourceNodes) {
      final relativePath = node.content!.path;
      if (relativePath.isNotEmpty) {
        try {
          final resolvedPath = repo.resolveRelativePath(tpackerPath, relativePath);
          final assetData = await ref.read(assetDataProvider(resolvedPath).future);
          if (assetData is ImageAssetData) {
            sourceImages[node.id] = assetData.image;
          }
        } catch (e) {
          print('TexturePackerLoader: Failed to load source image $relativePath: $e');
        }
      }
    }
    
    final packerItems = <PackerInputItem<SpriteDefinition>>[];
    final spriteNames = <String, String>{}; 

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
                data: def, 
              ));
              spriteNames[node.id] = node.name;
            }
          }
        }
      } else {
        for(final child in node.children) collectSprites(child);
      }
    }
    collectSprites(project.tree);

    final packer = MaxRectsPacker(padding: 2);
    final result = packer.pack(packerItems);

    final frames = <String, TexturePackerSpriteData>{};
    final animations = <String, List<String>>{};

    for (final item in result.items) {
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
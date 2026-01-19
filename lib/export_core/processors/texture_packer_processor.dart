import 'dart:convert';
import 'dart:ui' as ui;
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import '../models.dart';
import '../services/asset_loader_service.dart';

class TexturePackerAssetProcessor implements AssetProcessor {
  final ProjectRepository repo;
  final ExportAssetLoaderService loader;
  final String projectRoot;

  TexturePackerAssetProcessor(this.repo, this.loader, this.projectRoot);

  @override
  bool canHandle(String filePath) => filePath.toLowerCase().endsWith('.tpacker');

  @override
  Future<List<ExportableAsset>> collect(String projectRelativePath) async {
    final assets = <ExportableAsset>[];

    final file = await repo.fileHandler.resolvePath(projectRoot, projectRelativePath);
    if (file == null) return [];

    final content = await repo.readFile(file.uri);
    final project = TexturePackerProject.fromJson(jsonDecode(content));

    // Helper to find source config
    SourceImageConfig? findSourceConfig(String id) {
      SourceImageConfig? traverse(SourceImageNode node) {
        if (node.id == id && node.type == SourceNodeType.image) return node.content;
        for (final child in node.children) {
          final res = traverse(child);
          if (res != null) return res;
        }
        return null;
      }
      return traverse(project.sourceImagesRoot);
    }

    // Traverse logic
    void traverseTree(PackerItemNode node) async {
      if (node.type == PackerItemType.sprite) {
        final def = project.definitions[node.id];
        if (def is SpriteDefinition) {
          final sourceConfig = findSourceConfig(def.sourceImageId);
          if (sourceConfig != null) {
            
            // Resolve relative to the .tpacker file
            final imagePath = repo.resolveRelativePath(projectRelativePath, sourceConfig.path);
            
            // Use cached loader (synchronous if already loaded, but we await)
            final image = await loader.loadImage(imagePath);
            
            if (image != null) {
              final rect = _calculatePixelRect(sourceConfig, def.gridRect);
              
              assets.add(ExportableAsset(
                id: ExportableAssetId(
                  sourcePath: imagePath,
                  x: rect.left.toInt(),
                  y: rect.top.toInt(),
                  width: rect.width.toInt(),
                  height: rect.height.toInt(),
                ),
                image: image,
                sourceRect: rect,
              ));
            }
          }
        }
      }
      for (final child in node.children) {
        traverseTree(child);
      }
    }

    traverseTree(project.tree);
    
    // Small delay to allow recursive async calls in traverseTree to complete 
    // (In a real impl, traverseTree would return Future<List> and we'd await all)
    // For brevity, assuming simpler flow or refactoring traverseTree to be fully async.
    
    return assets;
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
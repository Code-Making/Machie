import 'dart:ui' as ui;
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/tiled_editor/project_tsx_provider.dart';
import 'package:tiled/tiled.dart';
import '../models.dart';
import '../services/asset_loader_service.dart';

class TiledAssetProcessor implements AssetProcessor {
  final ProjectRepository repo;
  final ExportAssetLoaderService loader;
  final String projectRoot;

  TiledAssetProcessor(this.repo, this.loader, this.projectRoot);

  @override
  bool canHandle(String filePath) => filePath.toLowerCase().endsWith('.tmx');

  @override
  Future<List<ExportableAsset>> collect(String projectRelativePath) async {
    final assets = <ExportableAsset>[];
    
    // 1. Load and Parse TMX
    final file = await repo.fileHandler.resolvePath(projectRoot, projectRelativePath);
    if (file == null) return [];
    
    final content = await repo.readFile(file.uri);
    final parentUri = repo.fileHandler.getParentUri(file.uri);
    
    // Use existing ProjectTsxProvider to handle external tilesets
    final tsxProvider = ProjectTsxProvider(repo, parentUri);
    final tsxList = await ProjectTsxProvider.parseFromTmx(content, tsxProvider.getProvider);
    
    final map = TileMapParser.parseTmx(content, tsxList: tsxList);

    // 2. Identify Used GIDs
    final usedGids = _findUsedGids(map);

    // 3. Extract Assets for Used GIDs
    for (final gid in usedGids) {
      final tile = map.tileByGid(gid);
      final tileset = map.tilesetByTileGId(gid);
      
      if (tile == null || tileset == null) continue;

      // Determine Image Source Path
      String? rawSource = tile.image?.source ?? tileset.image?.source;
      if (rawSource == null) continue;

      // Resolve path relative to TMX or TSX
      String contextPath = projectRelativePath;
      if (tileset.source != null) {
        contextPath = repo.resolveRelativePath(projectRelativePath, tileset.source!);
      }
      final imagePath = repo.resolveRelativePath(contextPath, rawSource);

      // Load Image
      final image = await loader.loadImage(imagePath);
      if (image == null) continue;

      // Calculate Rect
      final rect = tileset.computeDrawRect(tile);
      
      // Create Exportable Asset
      assets.add(ExportableAsset(
        id: ExportableAssetId(
          sourcePath: imagePath,
          x: rect.left.toInt(),
          y: rect.top.toInt(),
          width: rect.width.toInt(),
          height: rect.height.toInt(),
        ),
        image: image,
        sourceRect: ui.Rect.fromLTWH(rect.left.toDouble(), rect.top.toDouble(), rect.width.toDouble(), rect.height.toDouble()),
      ));
    }

    // 4. Handle Image Layers
    for (final layer in map.layers.whereType<ImageLayer>()) {
      if (layer.image.source != null) {
        final imagePath = repo.resolveRelativePath(projectRelativePath, layer.image.source!);
        final image = await loader.loadImage(imagePath);
        if (image != null) {
          assets.add(ExportableAsset(
            id: ExportableAssetId(
              sourcePath: imagePath,
              x: 0, y: 0, 
              width: image.width, height: image.height
            ),
            image: image,
            sourceRect: ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          ));
        }
      }
    }

    return assets;
  }

  Set<int> _findUsedGids(TiledMap map) {
    final gids = <int>{};
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (final row in layer.tileData!) {
          for (final gid in row) {
            if (gid.tile != 0) gids.add(gid.tile);
          }
        }
      } else if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          if (obj.gid != null) gids.add(obj.gid!);
        }
      }
    }
    return gids;
  }
}
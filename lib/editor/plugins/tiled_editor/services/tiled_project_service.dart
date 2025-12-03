// FILE: lib/editor/plugins/tiled_editor/services/tiled_project_service.dart

import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiled/tiled.dart';

import '../../../../data/file_handler/file_handler.dart';
import '../../../../data/repositories/project/project_repository.dart';
import '../../../../logs/logs_provider.dart';
import '../../../../project/services/project_asset_service.dart';
import '../image_load_result.dart';
import '../project_tsx_provider.dart';
import '../tmj_writer.dart';
import '../tmx_writer.dart';

final tiledProjectServiceProvider = Provider<TiledProjectService>((ref) {
  return TiledProjectService(ref);
});

/// A container for a fully loaded and parsed Tiled map and its dependencies.
class TiledMapData {
  final TiledMap map;
  final Map<String, ImageLoadResult> imageCache;
  TiledMapData({required this.map, required this.imageCache});
}

/// A service dedicated to Tiled map data operations, abstracting away the
/// complexities of parsing, dependency resolution, and serialization.
class TiledProjectService {
  final Ref _ref;
  TiledProjectService(this._ref);

  /// Loads a TMX file, resolves all its external TSX and image dependencies,
  /// and returns a fully parsed [TiledMapData] object.
  Future<TiledMapData> loadMap(
    DocumentFile tmxFile,
    String initialTmxContent,
  ) async {
    final repo = _ref.read(projectRepositoryProvider)!;
    final assetService = _ref.read(projectAssetServiceProvider);
    final talker = _ref.read(talkerProvider);
    final tmxParentUri = repo.fileHandler.getParentUri(tmxFile.uri);

    // 1. Parse external tilesets (TSX)
    final tsxProvider = ProjectTsxProvider(repo, tmxParentUri);
    final tsxProviders = await ProjectTsxProvider.parseFromTmx(
      initialTmxContent,
      tsxProvider.getProvider,
    );

    // 2. Parse the TMX into a TiledMap object
    final map = TileMapParser.parseTmx(
      initialTmxContent,
      tsxList: tsxProviders,
    );

    // 3. Load all required images using the ProjectAssetService
    final imageLoadResults = <String, ImageLoadResult>{};
    final allTiledImages = map.tiledImages();
    final imageFutures = allTiledImages.map((tiledImage) async {
      final imageSourcePath = tiledImage.source;
      if (imageSourcePath == null) return;

      try {
        final baseUri = await _resolveImageBaseUri(tmxParentUri, repo, map, imageSourcePath);
        final imageFile = await repo.fileHandler.resolvePath(baseUri, imageSourcePath);

        if (imageFile == null) {
          throw Exception('File not found at path: $imageSourcePath (relative to $baseUri)');
        }
        
        final assetData = await assetService.load<ImageAssetData>(imageFile);

        if (assetData.hasError) {
          throw assetData.error!;
        }
        
        imageLoadResults[imageSourcePath] =
            ImageLoadResult(image: assetData.data, path: imageSourcePath);

      } catch (e, st) {
        talker.handle(e, st, 'Failed to load TMX image source: $imageSourcePath');
        imageLoadResults[imageSourcePath] =
            ImageLoadResult(error: e.toString(), path: imageSourcePath);
      }
    });

    await Future.wait(imageFutures);
    return TiledMapData(map: map, imageCache: imageLoadResults);
  }

  /// Serializes a [TiledMap] object into its XML (.tmx) string representation.
  String getMapContentAsTmx(TiledMap map) {
    return TmxWriter(map).toTmx();
  }
  
  /// Serializes a [TiledMap] object into its JSON (.tmj) string representation.
  String getMapContentAsTmj(TiledMap map) {
    return TmjWriter(map).toTmj();
  }

  // Helper method to determine the correct base path for resolving an image.
  Future<String> _resolveImageBaseUri(String tmxParentUri, ProjectRepository repo, TiledMap map, String imageSourcePath) async {
    final imageLayerSources = map.layers.whereType<ImageLayer>().map((l) => l.image.source).toSet();
    if (imageLayerSources.contains(imageSourcePath)) {
      return tmxParentUri;
    }

    final tileset = map.tilesets.firstWhereOrNull(
      (ts) => ts.image?.source == imageSourcePath || ts.tiles.any((t) => t.image?.source == imageSourcePath),
    );
    
    if (tileset != null && tileset.source != null) {
      final tsxFile = await repo.fileHandler.resolvePath(tmxParentUri, tileset.source!);
      if (tsxFile != null) {
        return repo.fileHandler.getParentUri(tsxFile.uri);
      }
    }
    return tmxParentUri;
  }
}
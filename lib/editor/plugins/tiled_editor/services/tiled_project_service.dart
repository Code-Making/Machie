// FILE: lib/editor/plugins/tiled_editor/services/tiled_project_service.dart

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiled/tiled.dart';

import '../../../../data/file_handler/file_handler.dart';
import '../../../../data/repositories/project/project_repository.dart';
import '../../../../logs/logs_provider.dart';
import '../../../../project/services/project_asset_cache_service.dart';
import '../image_load_result.dart';
import '../project_tsx_provider.dart';
import '../tiled_export_service.dart';
import '../tmj_writer.dart';
import '../tmx_writer.dart';
import '../tiled_map_notifier.dart'; // For deepCopy utilities

/// A provider for the TiledProjectService.
final tiledProjectServiceProvider = Provider<TiledProjectService>((ref) {
  return TiledProjectService(ref);
});

/// A container for a fully loaded and resolved Tiled map.
class TiledMapData {
  final TiledMap map;
  final Map<String, ImageLoadResult> imageCache;
  TiledMapData({required this.map, required this.imageCache});
}

/// Provides high-level, decoupled services for loading, processing,
/// and saving Tiled map data.
class TiledProjectService {
  final Ref _ref;
  TiledProjectService(this._ref);

  /// Loads a TMX file and all its dependencies (TSX, images), returning a
  /// fully resolved [TiledMapData] object.
  Future<TiledMapData> loadMap(DocumentFile tmxFile) async {
    final repo = _ref.read(projectRepositoryProvider)!;
    final assetCache = _ref.read(projectAssetCacheProvider);
    final talker = _ref.read(talkerProvider);

    final tmxContent = await repo.readFile(tmxFile.uri);
    final tmxParentUri = repo.fileHandler.getParentUri(tmxFile.uri);

    final tsxProvider = ProjectTsxProvider(repo, tmxParentUri);
    final tsxProviders = await ProjectTsxProvider.parseFromTmx(
      tmxContent,
      tsxProvider.getProvider,
    );

    final map = TileMapParser.parseTmx(tmxContent, tsxList: tsxProviders);
    
    // NOTE: For simplicity, this service doesn't use the _fixupParsedMap logic
    // from the widget. If that logic is critical for all use cases, it should
    // be extracted into a shared utility function.

    final imageLoadResults = <String, ImageLoadResult>{};
    final allImagesToLoad = map.tiledImages();

    final imageFutures = allImagesToLoad.map((tiledImage) async {
      final imageSourcePath = tiledImage.source;
      if (imageSourcePath == null) return;

      try {
        // This resolution logic can be extracted from TiledEditorWidgetState
        // into a shared utility if it becomes more complex.
        final tsxFile = (tileset.source != null) 
            ? await repo.fileHandler.resolvePath(tmxParentUri, tileset.source!)
            : null;
        final baseUri = tsxFile != null 
            ? repo.fileHandler.getParentUri(tsxFile.uri) 
            : tmxParentUri;

        final imageFile = await repo.fileHandler.resolvePath(baseUri, imageSourcePath);
        if (imageFile == null) throw Exception('Image file not found');

        final assetData = await assetCache.load<ui.Image>(imageFile);
        if (assetData.hasError) throw assetData.error!;

        imageLoadResults[imageSourcePath] =
            ImageLoadResult(image: assetData.data, path: imageSourcePath);
      } catch (e) {
        talker.warning('Failed to load image for export: $imageSourcePath. Error: $e');
        imageLoadResults[imageSourcePath] =
            ImageLoadResult(error: e.toString(), path: imageSourcePath);
      }
    });

    await Future.wait(imageFutures);
    return TiledMapData(map: map, imageCache: imageLoadResults);
  }

  /// Exports a list of maps, optionally packing their tilesets into a single atlas.
  ///
  /// This method encapsulates the logic previously in `TiledExportService`.
  Future<void> exportMaps({
    required List<TiledMapData> mapsToExport,
    required String destinationFolderUri,
    required String atlasFileName,
    required bool removeUnused,
    required bool asJson,
    required bool packInAtlas,
  }) async {
    final talker = _ref.read(talkerProvider);
    final repo = _ref.read(projectRepositoryProvider)!;

    final exportService = TiledExportService(_ref);

    // If packing, we need to do this as a single batch operation.
    if (packInAtlas) {
      talker.info('Atlas packing for multiple maps is a complex feature and not fully implemented in this service stub.');
      // TODO: Implement multi-map atlas packing. This would involve:
      // 1. Combining all TiledMapData objects.
      // 2. Running the atlas packing logic from TiledExportService across all combined assets.
      // 3. Re-writing each map file to point to the new single atlas.
      // For now, we will export them individually.
    }
    
    // For now, export each map individually.
    for (final mapData in mapsToExport) {
      final mapName = mapData.map.name ?? 'exported_map';
      await exportService.exportMap(
        map: mapData.map,
        imageCache: mapData.imageCache,
        destinationFolderUri: destinationFolderUri,
        mapFileName: mapName,
        atlasFileName: atlasFileName,
        removeUnused: removeUnused,
        asJson: asJson,
        packInAtlas: packInAtlas, // This will pack each map into its own atlas
      );
    }
  }
}
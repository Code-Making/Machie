// FILE: lib/editor/plugins/tiled_editor/services/tiled_project_service.dart

import 'dart:math';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiled/tiled.dart';
import 'package:xml/xml.dart';

import '../../../../data/file_handler/file_handler.dart';
import '../../../../data/repositories/project/project_repository.dart';
import '../../../../editor/models/asset_models.dart';
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

  /// Loads a TMX file, resolves all dependencies, applies necessary fixups,
  /// and returns a fully prepared [TiledMapData] object ready for the editor.
  Future<TiledMapData> loadAndPrepareMap(
    DocumentFile tmxFile,
    String initialTmxContent,
  ) async {
    final repo = _ref.read(projectRepositoryProvider)!;
    final assetService = _ref.read(projectAssetServiceProvider);
    final talker = _ref.read(talkerProvider);
    final tmxParentUri = repo.fileHandler.getParentUri(tmxFile.uri);

    // Step 1: Parse external tilesets (TSX)
    final tsxProvider = ProjectTsxProvider(repo, tmxParentUri);
    final tsxProviders = await ProjectTsxProvider.parseFromTmx(
      initialTmxContent,
      tsxProvider.getProvider,
    );

    // Step 2: Parse the TMX into a TiledMap object
    final map = TileMapParser.parseTmx(
      initialTmxContent,
      tsxList: tsxProviders,
    );

    // Step 3: Apply initial fixups to the parsed map structure
    _fixupParsedMap(map, initialTmxContent);

    // Step 4: Load all required images using the ProjectAssetService
    final imageLoadResults = <String, ImageLoadResult>{};
    final allTiledImages = map.tiledImages();
    final imageFutures = allTiledImages.map((tiledImage) async {
      final imageSourcePath = tiledImage.source;
      if (imageSourcePath == null) return;

      try {
        final baseUri =
            await _resolveImageBaseUri(tmxParentUri, repo, map, imageSourcePath);
        final imageFile =
            await repo.fileHandler.resolvePath(baseUri, imageSourcePath);

        if (imageFile == null) {
          throw Exception(
              'File not found at path: $imageSourcePath (relative to $baseUri)');
        }

        final assetData = await assetService.load<ImageAssetData>(imageFile);

        if (assetData.hasError) {
          throw assetData.error!;
        }

        imageLoadResults[imageSourcePath] =
            ImageLoadResult(image: assetData.data, path: imageSourcePath);
      } catch (e, st) {
        talker.handle(
            e, st, 'Failed to load TMX image source: $imageSourcePath');
        imageLoadResults[imageSourcePath] =
            ImageLoadResult(error: e.toString(), path: imageSourcePath);
      }
    });

    await Future.wait(imageFutures);

    // Step 5: Apply final fixups that depend on loaded images
    _fixupTilesetsAfterImageLoad(map, imageLoadResults);

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

  // --- Private Helper Methods (Moved from Widget) ---

  void _fixupParsedMap(TiledMap map, String tmxContent) {
    // ... (The exact same logic as was in TiledEditorWidgetState)
    final xmlDocument = XmlDocument.parse(tmxContent);
    final layerElements = xmlDocument.rootElement.findAllElements('layer');
    final objectGroupElements =
        xmlDocument.rootElement.findAllElements('objectgroup');
    for (final layerElement in layerElements) {
      final layerId = int.tryParse(layerElement.getAttribute('id') ?? '');
      if (layerId == null) continue;
      final layer =
          map.layers.firstWhereOrNull((l) => l.id == layerId) as TileLayer?;
      if (layer != null && (layer.tileData == null || layer.tileData!.isEmpty)) {
        final dataElement = layerElement.findElements('data').firstOrNull;
        if (dataElement != null && dataElement.getAttribute('encoding') == null) {
          final tileElements = dataElement.findElements('tile');
          final gids = tileElements
              .map((t) => int.tryParse(t.getAttribute('gid') ?? '0') ?? 0)
              .toList();
          if (gids.isNotEmpty) {
            layer.tileData = Gid.generate(gids, layer.width, layer.height);
          }
        }
      }
    }
    for (final objectGroupElement in objectGroupElements) {
      final layerId = int.tryParse(objectGroupElement.getAttribute('id') ?? '');
      if (layerId == null) continue;
      final objectGroup =
          map.layers.firstWhereOrNull((l) => l.id == layerId) as ObjectGroup?;
      if (objectGroup == null) continue;
      final objectElements = objectGroupElement.findAllElements('object');
      for (final objectElement in objectElements) {
        final objectId = int.tryParse(objectElement.getAttribute('id') ?? '');
        if (objectId == null) continue;
        final tiledObject =
            objectGroup.objects.firstWhereOrNull((o) => o.id == objectId);
        if (tiledObject != null) {
          final hasEllipse = objectElement.findElements('ellipse').isNotEmpty;
          final hasPoint = objectElement.findElements('point').isNotEmpty;
          if (hasEllipse) {
            tiledObject.ellipse = true;
            tiledObject.rectangle = false;
            tiledObject.point = false;
          } else if (hasPoint) {
            tiledObject.point = true;
            tiledObject.rectangle = false;
            tiledObject.ellipse = false;
          }
        }
      }
    }
    var nextAvailableId = map.nextLayerId;
    int findMaxId(List<Layer> layers) {
      var maxId = 0;
      for (final layer in layers) {
        if (layer.id != null) {
          maxId = max(maxId, layer.id!);
        }
        if (layer is Group) {
          maxId = max(maxId, findMaxId(layer.layers));
        }
      }
      return maxId;
    }

    if (nextAvailableId == null) {
      final maxLayerId = findMaxId(map.layers);
      nextAvailableId = maxLayerId + 1;
    }

    void assignIds(List<Layer> layers) {
      for (final layer in layers) {
        if (layer.id == null) {
          layer.id = nextAvailableId;
          nextAvailableId = nextAvailableId! + 1;
        }
        if (layer is Group) {
          assignIds(layer.layers);
        }
      }
    }

    assignIds(map.layers);
    map.nextLayerId = nextAvailableId;
  }

  void _fixupTilesetsAfterImageLoad(
      TiledMap map, Map<String, ImageLoadResult> tilesetImages) {
    // ... (The exact same logic as was in TiledEditorWidgetState)
    for (final tileset in map.tilesets) {
      if (tileset.tiles.isEmpty && tileset.image?.source != null) {
        final imageResult = tilesetImages[tileset.image!.source];
        final image = imageResult?.image;
        final tileWidth = tileset.tileWidth;
        final tileHeight = tileset.tileHeight;
        if (image != null &&
            tileWidth != null &&
            tileHeight != null &&
            tileWidth > 0 &&
            tileHeight > 0) {
          final columns = (image.width - tileset.margin * 2 + tileset.spacing) ~/
              (tileWidth + tileset.spacing);
          final rows = (image.height - tileset.margin * 2 + tileset.spacing) ~/
              (tileHeight + tileset.spacing);
          final tileCount = columns * rows;
          tileset.columns = columns;
          tileset.tileCount = tileCount;
          final newTiles = <Tile>[];
          for (var i = 0; i < tileCount; ++i) {
            newTiles.add(Tile(localId: i));
          }
          tileset.tiles = newTiles;
        }
      }
    }
  }

  Future<String> _resolveImageBaseUri(String tmxParentUri,
      ProjectRepository repo, TiledMap map, String imageSourcePath) async {
    // ... (The exact same logic as was in TiledEditorWidgetState)
    final imageLayerSources =
        map.layers.whereType<ImageLayer>().map((l) => l.image.source).toSet();
    if (imageLayerSources.contains(imageSourcePath)) {
      return tmxParentUri;
    }

    final tileset = map.tilesets.firstWhereOrNull(
      (ts) =>
          ts.image?.source == imageSourcePath ||
          ts.tiles.any((t) => t.image?.source == imageSourcePath),
    );

    if (tileset != null && tileset.source != null) {
      final tsxFile =
          await repo.fileHandler.resolvePath(tmxParentUri, tileset.source!);
      if (tsxFile != null) {
        return repo.fileHandler.getParentUri(tsxFile.uri);
      }
    }
    return tmxParentUri;
  }
}
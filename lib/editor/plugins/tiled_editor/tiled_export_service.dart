import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/tiled_editor/tiled_editor_plugin.dart';
import 'package:machine/editor/plugins/tiled_editor/tmj_writer.dart';
import 'package:machine/editor/plugins/tiled_editor/tmx_writer.dart';
import 'package:machine/editor/tab_metadata_notifier.dart';
import 'package:machine/logs/logs_provider.dart';
import 'package:tiled/tiled.dart';
import 'package:machine/editor/plugins/tiled_editor/image_load_result.dart'; // Add this import
import 'package:machine/asset_cache/asset_models.dart';

import 'tiled_map_notifier.dart';
import '../../../data/repositories/project/project_repository.dart';

final tiledExportServiceProvider = Provider<TiledExportService>((ref) {
  return TiledExportService(ref);
});


class _TileSourceInfo {
  final int oldGid;
  final Tile tile;
  final Tileset tileset;
  _TileSourceInfo(this.oldGid, this.tile, this.tileset);
}

class _PackAtlasResult {
  final TiledMap modifiedMap;
  final Uint8List atlasImageBytes;
  final String atlasImageName;
  _PackAtlasResult(this.modifiedMap, this.atlasImageBytes, this.atlasImageName);
}

class TiledExportService {
  final Ref _ref;
  TiledExportService(this._ref);

  Future<void> exportMap({
    required TiledMap map,
    required Map<String, AssetData> assetDataMap,
    required String destinationFolderUri,
    required String mapFileName,
    required String atlasFileName,
    required bool removeUnused,
    required bool asJson,
    required bool packInAtlas,
  }) async {
    final talker = _ref.read(talkerProvider);
    talker.info('Starting map export...');
    final repo = _ref.read(projectRepositoryProvider)!;
    final project = _ref.read(appNotifierProvider).value!.currentProject!;

    // 1. Create a temporary, deep copy of the map.
    TiledMap mapToExport = _deepCopyMap(map);
    Uint8List? atlasImageBytes;
    String? finalAtlasImageName;

    // 2. Conditionally remove unused tilesets.
    if (removeUnused) {
      final usedGids = _findUsedGids(mapToExport);
      mapToExport.tilesets.removeWhere((tileset) {
        final firstGid = tileset.firstGid ?? 0;
        final lastGid = firstGid + (tileset.tileCount ?? 0) - 1;
        final isUsed = usedGids.any((gid) => gid >= firstGid && gid <= lastGid);
        if (!isUsed) {
          talker.info('Removing unused tileset: ${tileset.name}');
        }
        return !isUsed;
      });
    }
    
    if (packInAtlas) {
      final result = await _packAtlas(mapToExport, assetDataMap, atlasFileName);
      mapToExport = result.modifiedMap;
      atlasImageBytes = result.atlasImageBytes;
      finalAtlasImageName = result.atlasImageName;
    }

    final sourceMapFile = _ref.read(tabMetadataProvider)[_ref.read(appNotifierProvider).value!.currentProject!.session.currentTab!.id]!.file;
    final sourceMapFolderUri = repo.fileHandler.getParentUri(sourceMapFile.uri);

    final assetsToCopy = <String>{};
    // If we packed an atlas, only copy non-tileset images (e.g., from ImageLayers)
    if (packInAtlas) {
      for (final layer in mapToExport.layers) {
        if (layer is ImageLayer && layer.image.source != null) {
          assetsToCopy.add(layer.image.source!);
        }
      }
    } else { // Otherwise, copy all used tileset images
      for (final tileset in mapToExport.tilesets) {
        if (tileset.image?.source != null) {
          assetsToCopy.add(tileset.image!.source!);
        }
      }
      for (final layer in mapToExport.layers) {
        if (layer is ImageLayer && layer.image.source != null) {
          assetsToCopy.add(layer.image.source!);
        }
      }
    }
    
    talker.info('Found ${assetsToCopy.length} external assets to copy.');

    for (final relativeAssetPath in assetsToCopy) {
      try {
        // Resolve the asset's original location. This is tricky because the path
        // in the TMX is relative to the TMX file itself.
        final assetFile = await repo.fileHandler.resolvePath(sourceMapFolderUri, relativeAssetPath);
        
        if (assetFile != null) {
          talker.info('Copying asset: ${assetFile.name}');
          await repo.copyDocumentFile(assetFile, destinationFolderUri);
        } else {
          talker.warning('Could not find asset to copy: $relativeAssetPath');
        }
      } catch (e, st) {
        talker.handle(e, st, 'Failed to copy asset: $relativeAssetPath');
      }
    }

    // --- END OF NEW LOGIC ---

    // 4. Generate the map file content.
    String fileContent;
    String fileExtension;
    if (asJson) {
      // This will now correctly serialize the map *after* it has been modified by _packAtlas
      fileContent = TmjWriter(mapToExport).toTmj();
      fileExtension = 'json';
    } else {
      fileContent = TmxWriter(mapToExport).toTmx();
      fileExtension = 'tmx';
    }
    
    final finalMapFileName = '$mapFileName.$fileExtension';

    // Save the new atlas image if it was created
    if (atlasImageBytes != null && finalAtlasImageName != null) {
      final atlasFile = await repo.createDocumentFile(
        destinationFolderUri,
        finalAtlasImageName!,
        initialBytes: atlasImageBytes,
        overwrite: true,
      );
        // _ref
        // .read(fileOperationControllerProvider)
        // .add(FileCreateEvent(createdFile: atlasFile));

    }
    
    final mapFile = await repo.createDocumentFile(
      destinationFolderUri,
      finalMapFileName,
      initialContent: fileContent,
      overwrite: true,
    );
    
        // _ref
        // .read(fileOperationControllerProvider)
        // .add(FileCreateEvent(createdFile: mapFile));


    talker.info('Export complete: $mapFileName');
  }

  Future<_PackAtlasResult> _packAtlas(TiledMap map, Map<String, AssetData> assetDataMap, String atlasBaseName) async {
    _ref.read(talkerProvider).info('Starting atlas packing...');
    final usedGids = _findUsedGids(map);
    final uniqueTileSources = <int, _TileSourceInfo>{};

    // 1. Gather all unique tile source information
    for (final gid in usedGids) {
      if (uniqueTileSources.containsKey(gid)) continue;
      final tile = map.tileByGid(gid);
      if (tile != null && !tile.isEmpty) {
        final tileset = map.tilesetByTileGId(gid);
        uniqueTileSources[gid] = _TileSourceInfo(gid, tile, tileset);
      }
    }
    final sortedTiles = uniqueTileSources.values.toList();

    // 2. Pack the tiles into a layout
    final int atlasWidth = 1024; // A reasonable default width
    final Map<int, ui.Rect> packedLayout = {}; // oldGid -> new Rect in atlas
    int currentX = 0;
    int currentY = 0;
    int maxYinRow = 0;
    for (final source in sortedTiles) {
      final tileWidth = source.tileset.tileWidth ?? map.tileWidth;
      final tileHeight = source.tileset.tileHeight ?? map.tileHeight;

      if (currentX + tileWidth > atlasWidth) {
        currentX = 0;
        currentY += maxYinRow;
        maxYinRow = 0;
      }
      packedLayout[source.oldGid] = ui.Rect.fromLTWH(
          currentX.toDouble(), currentY.toDouble(), tileWidth.toDouble(), tileHeight.toDouble());

      currentX += tileWidth;
      maxYinRow = max(maxYinRow, tileHeight);
    }
    final int atlasHeight = currentY + maxYinRow;
    
    // 3. Render the new atlas image
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    final allSourceImages = sortedTiles.map((e) => e.tileset.image?.source).toSet();
    
    for (final source in sortedTiles) {
      final destRect = packedLayout[source.oldGid]!;
      final tiledRect = source.tileset.computeDrawRect(source.tile);
      final sourceRect = ui.Rect.fromLTWH(
        tiledRect.left.toDouble(),
        tiledRect.top.toDouble(),
        tiledRect.width.toDouble(),
        tiledRect.height.toDouble(),
      );      
      final asset = assetDataMap[source.tileset.image!.source!];
      final sourceImage = asset is ImageAssetData ? asset.image : null;

      if (sourceImage != null) {
        canvas.drawImageRect(sourceImage, sourceRect, destRect, paint);
      }
    }
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(atlasWidth, atlasHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final atlasImageBytes = byteData!.buffer.asUint8List();

    // 4. Create new tileset and GID remap table
    final atlasName = atlasBaseName;
    final atlasFileName = '$atlasName.png'; // Construct filename with extension
    final Map<int, int> gidRemapTable = {};
    int newLocalId = 0;

    final atlasTileset = Tileset(
      name: atlasName,
      firstGid: 1, // Will be the only tileset, so it starts at 1
      tileWidth: map.tileWidth,
      tileHeight: map.tileHeight,
      tileCount: sortedTiles.length,
      columns: atlasWidth ~/ map.tileWidth,
      image: TiledImage(source: atlasFileName, width: atlasWidth, height: atlasHeight),
    );

    for (final source in sortedTiles) {
      gidRemapTable[source.oldGid] = atlasTileset.firstGid! + newLocalId;
      newLocalId++;
    }

    // 5. Rewrite map data
    for (final layer in map.layers) {
      if (layer is TileLayer) {
        for (int y = 0; y < layer.height; y++) {
          for (int x = 0; x < layer.width; x++) {
            final oldGid = layer.tileData![y][x];
            if (oldGid.tile != 0) {
              final newGidTile = gidRemapTable[oldGid.tile];
              if (newGidTile != null) {
                layer.tileData![y][x] = Gid(newGidTile, oldGid.flips);
              }
            }
          }
        }
      } else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          if (object.gid != null) {
            final newGid = gidRemapTable[object.gid];
            if (newGid != null) {
              object.gid = newGid;
            }
          }
        }
      }
    }
    
    // 6. Finalize the map object
    map.tilesets..clear()..add(atlasTileset);

    _ref.read(talkerProvider).info('Atlas packing complete.');
    return _PackAtlasResult(map, atlasImageBytes, atlasFileName);
  }

  Set<int> _findUsedGids(TiledMap map) {
    final usedGids = <int>{};
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (final row in layer.tileData!) {
          for (final gid in row) {
            if (gid.tile != 0) usedGids.add(gid.tile);
          }
        }
      } else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          if (object.gid != null) usedGids.add(object.gid!);
        }
      }
    }
    return usedGids;
  }
  
  TiledMap _deepCopyMap(TiledMap original) {
    final writer = TmxWriter(original);
    final tmxString = writer.toTmx();
    return TileMapParser.parseTmx(tmxString);
  }
}


// Placeholder for the name property that doesn't exist on the TiledMap object
extension TiledMapNameExtension on TiledMap {
  String? get name {
    return 'map';
  }
}
// FILE: lib/editor/plugins/tiled_editor/tiled_export_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/tiled_editor/tmj_writer.dart';
import 'package:machine/editor/plugins/tiled_editor/tmx_writer.dart';
import 'package:machine/editor/tab_metadata_notifier.dart';
import 'package:machine/logs/logs_provider.dart';
import 'package:tiled/tiled.dart';
import 'package:machine/asset_cache/asset_models.dart';

// Imports for dependency exports
import 'package:machine/editor/plugins/texture_packer/services/pixi_export_service.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_asset_resolver.dart';

import 'package:machine/editor/plugins/flow_graph/services/flow_export_service.dart';
import 'package:machine/editor/plugins/flow_graph/models/flow_graph_models.dart';
import 'package:machine/editor/plugins/flow_graph/flow_graph_asset_resolver.dart';

import 'tiled_asset_resolver.dart';

final tiledExportServiceProvider = Provider<TiledExportService>((ref) {
  return TiledExportService(ref);
});

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
    required TiledAssetResolver resolver,
    required String destinationFolderUri,
    required String mapFileName,
    required String atlasFileName,
    required bool removeUnused,
    required bool asJson,
    required bool packInAtlas,
  }) async {
    final talker = _ref.read(talkerProvider);
    final repo = _ref.read(projectRepositoryProvider)!;
    final project = _ref.read(appNotifierProvider).value!.currentProject!;

    talker.info('Starting map export orchestrator...');

    // 1. Deep Copy Map (We will modify paths in this copy)
    TiledMap mapToExport = _deepCopyMap(map);
    
    // 2. Process Embedded Texture Packer Files
    // If the map uses .tpacker files via the 'tp_atlases' custom property, we export them to PixiJS format
    // and update the map property to point to the .json files.
    await _processTexturePackerDependencies(
      mapToExport: mapToExport, 
      resolver: resolver, 
      destinationFolderUri: destinationFolderUri,
      assetDataMap: resolver.rawAssets,
    );

    // 3. Process Embedded Flow Graphs
    // Scan objects for 'flowGraph' property, export .fg to .json, update property.
    await _processFlowGraphDependencies(
      mapToExport: mapToExport, 
      resolver: resolver, 
      destinationFolderUri: destinationFolderUri,
      assetDataMap: resolver.rawAssets,
    );

    // 4. Tileset Optimization (Existing logic)
    if (removeUnused) {
      final usedGids = _findUsedGids(mapToExport);
      mapToExport.tilesets.removeWhere((tileset) {
        final firstGid = tileset.firstGid ?? 0;
        final lastGid = firstGid + (tileset.tileCount ?? 0) - 1;
        final isUsed = usedGids.any((gid) => gid >= firstGid && gid <= lastGid);
        return !isUsed;
      });
    }
    
    // 5. Atlas Packing (Existing logic)
    Uint8List? atlasImageBytes;
    String? finalAtlasImageName;

    if (packInAtlas) {
      final result = await _packAtlas(mapToExport, resolver, atlasFileName);
      mapToExport = result.modifiedMap;
      atlasImageBytes = result.atlasImageBytes;
      finalAtlasImageName = result.atlasImageName;
    }

    // 6. External Asset Copying (Images)
    // If not packing into an atlas, copy referenced images to the destination
    // and update map paths to be flat (filename only).
    if (!packInAtlas) {
      await _copyAndRelinkAssets(
        mapToExport: mapToExport,
        resolver: resolver,
        destinationFolderUri: destinationFolderUri,
      );
    }

    // 7. Write Map File
    String fileContent;
    String fileExtension;
    if (asJson) {
      fileContent = TmjWriter(mapToExport).toTmj();
      fileExtension = 'json';
    } else {
      fileContent = TmxWriter(mapToExport).toTmx();
      fileExtension = 'tmx';
    }
    
    final finalMapFileName = '$mapFileName.$fileExtension';

    // Write Atlas Image if generated
    if (atlasImageBytes != null && finalAtlasImageName != null) {
      await repo.createDocumentFile(
        destinationFolderUri,
        finalAtlasImageName!,
        initialBytes: atlasImageBytes,
        overwrite: true,
      );
    }
    
    // Write Map
    await repo.createDocumentFile(
      destinationFolderUri,
      finalMapFileName,
      initialContent: fileContent,
      overwrite: true,
    );

    talker.info('Export complete: $mapFileName');
  }

  /// Exports referenced .tpacker files to .png/.json and updates map properties.
  Future<void> _processTexturePackerDependencies({
    required TiledMap mapToExport,
    required TiledAssetResolver resolver,
    required String destinationFolderUri,
    required Map<String, AssetData> assetDataMap,
  }) async {
    final talker = _ref.read(talkerProvider);
    final repo = resolver.repo;
    final pixiService = _ref.read(pixiExportServiceProvider);

    final prop = mapToExport.properties['tp_atlases'];
    if (prop is! StringProperty || prop.value.isEmpty) return;

    final rawPaths = prop.value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final newPaths = <String>[];

    for (final relativePath in rawPaths) {
      try {
        // Resolve .tpacker file location relative to TMX
        final tpackerCanonicalKey = repo.resolveRelativePath(resolver.tmxPath, relativePath);
        
        // We need to read the raw file to get the project model (Assets only have the runtime data)
        final tpackerFile = await repo.fileHandler.resolvePath(repo.rootUri, tpackerCanonicalKey);
        
        if (tpackerFile == null) {
          talker.warning('Export: Could not find referenced atlas $relativePath');
          continue;
        }

        final content = await repo.readFile(tpackerFile.uri);
        final project = TexturePackerProject.fromJson(jsonDecode(content));
        
        // Create a resolver specific to this .tpacker file
        final tpackerPath = repo.fileHandler.getPathForDisplay(tpackerFile.uri, relativeTo: repo.rootUri);
        final tpackerResolver = TexturePackerAssetResolver(assetDataMap, repo, tpackerPath);

        final exportName = p.basenameWithoutExtension(tpackerFile.name);
        
        // Export to destination
        await pixiService.export(
          project: project,
          resolver: tpackerResolver,
          destinationFolderUri: destinationFolderUri,
          fileName: exportName,
        );

        // Update reference to point to the exported JSON
        newPaths.add('$exportName.json');
        talker.info('Exported dependency: $exportName.json');

      } catch (e, st) {
        talker.handle(e, st, 'Failed to export atlas dependency: $relativePath');
      }
    }

    // Update the property on the map to point to the exported files
    mapToExport.properties.byName['tp_atlases'] = StringProperty(
      name: 'tp_atlases',
      value: newPaths.join(','),
    );
  }

  /// Exports referenced .fg files to .json and updates object properties.
  Future<void> _processFlowGraphDependencies({
    required TiledMap mapToExport,
    required TiledAssetResolver resolver,
    required String destinationFolderUri,
    required Map<String, AssetData> assetDataMap,
  }) async {
    final talker = _ref.read(talkerProvider);
    final repo = resolver.repo;
    final flowService = _ref.read(flowExportServiceProvider);

    // Recursively find objects in groups
    void processLayer(Layer layer) {
      if (layer is Group) {
        for (final child in layer.layers) processLayer(child);
      } else if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          final prop = obj.properties['flowGraph'];
          if (prop is StringProperty && prop.value.isNotEmpty) {
            _exportSingleFlowGraph(
              obj: obj,
              relativePath: prop.value,
              resolver: resolver,
              repo: repo,
              destinationFolderUri: destinationFolderUri,
              assetDataMap: assetDataMap,
              flowService: flowService,
              talker: talker,
            );
          }
        }
      }
    }

    for (final layer in mapToExport.layers) {
      processLayer(layer);
    }
  }

  Future<void> _exportSingleFlowGraph({
    required TiledObject obj,
    required String relativePath,
    required TiledAssetResolver resolver,
    required ProjectRepository repo,
    required String destinationFolderUri,
    required Map<String, AssetData> assetDataMap,
    required FlowExportService flowService,
    required Talker talker,
  }) async {
    try {
      final fgCanonicalKey = repo.resolveRelativePath(resolver.tmxPath, relativePath);
      final fgFile = await repo.fileHandler.resolvePath(repo.rootUri, fgCanonicalKey);

      if (fgFile == null) {
        talker.warning('Export: Flow Graph file not found $relativePath');
        return;
      }

      final content = await repo.readFile(fgFile.uri);
      final graph = FlowGraph.deserialize(content);

      final fgPath = repo.fileHandler.getPathForDisplay(fgFile.uri, relativeTo: repo.rootUri);
      final fgResolver = FlowGraphAssetResolver(assetDataMap, repo, fgPath);

      final exportName = p.basenameWithoutExtension(fgFile.name);

      await flowService.export(
        graph: graph,
        resolver: fgResolver,
        destinationFolderUri: destinationFolderUri,
        fileName: exportName,
        embedSchema: true, // Usually games want the schema baked in
      );

      // Update property to point to new JSON
      obj.properties.byName['flowGraph'] = StringProperty(
        name: 'flowGraph',
        value: '$exportName.json',
      );
      talker.info('Exported Flow Graph: $exportName.json');

    } catch (e) {
      talker.warning('Failed to export Flow Graph $relativePath: $e');
    }
  }

  /// Copies image assets used by tilesets/layers to destination and flattens paths.
  Future<void> _copyAndRelinkAssets({
    required TiledMap mapToExport,
    required TiledAssetResolver resolver,
    required String destinationFolderUri,
  }) async {
    final repo = resolver.repo;
    final talker = _ref.read(talkerProvider);

    // 1. Relink Tilesets
    for (final tileset in mapToExport.tilesets) {
      if (tileset.image?.source != null) {
        final rawSource = tileset.image!.source!;
        
        // Calculate where the original file is
        final contextPath = (tileset.source != null) 
            ? repo.resolveRelativePath(resolver.tmxPath, tileset.source!) 
            : resolver.tmxPath;
            
        final canonicalKey = repo.resolveRelativePath(contextPath, rawSource);
        
        // Copy file
        final file = await repo.fileHandler.resolvePath(repo.rootUri, canonicalKey);
        if (file != null) {
          await repo.copyDocumentFile(file, destinationFolderUri);
          // Relink to flat filename
          tileset.image!.source = file.name;
          // Clear external tileset source to make it embedded in the export
          // (Simplifies runtime loading)
          tileset.source = null; 
        }
      }
    }

    // 2. Relink Image Layers
    for (final layer in mapToExport.layers) {
      if (layer is ImageLayer && layer.image.source != null) {
        final rawSource = layer.image.source!;
        final canonicalKey = repo.resolveRelativePath(resolver.tmxPath, rawSource);
        
        final file = await repo.fileHandler.resolvePath(repo.rootUri, canonicalKey);
        if (file != null) {
          await repo.copyDocumentFile(file, destinationFolderUri);
          layer.image.source = file.name;
        }
      }
    }
  }

  Future<_PackAtlasResult> _packAtlas(TiledMap map, TiledAssetResolver resolver, String atlasBaseName) async {
    _ref.read(talkerProvider).info('Starting atlas packing...');
    final usedGids = _findUsedGids(map);
    
    // Helper class to store packing info
    class TileInfo {
      final int oldGid;
      final Tile tile;
      final Tileset tileset;
      TileInfo(this.oldGid, this.tile, this.tileset);
    }

    final uniqueTileSources = <int, TileInfo>{};

    for (final gid in usedGids) {
      if (uniqueTileSources.containsKey(gid)) continue;
      final tile = map.tileByGid(gid);
      if (tile != null && !tile.isEmpty) {
        final tileset = map.tilesetByTileGId(gid);
        uniqueTileSources[gid] = TileInfo(gid, tile, tileset);
      }
    }
    final sortedTiles = uniqueTileSources.values.toList();

    // Simple row packing
    final int atlasWidth = 2048; // Bumped up for safety
    final Map<int, ui.Rect> packedLayout = {};
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
    
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    for (final source in sortedTiles) {
      final destRect = packedLayout[source.oldGid]!;
      
      final imageSource = source.tileset.image?.source;
      if (imageSource != null) {
        final sourceImage = resolver.getImage(imageSource, tileset: source.tileset);
        
        if (sourceImage != null) {
          final tiledRect = source.tileset.computeDrawRect(source.tile);
          final sourceRect = ui.Rect.fromLTWH(
            tiledRect.left.toDouble(),
            tiledRect.top.toDouble(),
            tiledRect.width.toDouble(),
            tiledRect.height.toDouble(),
          );
          canvas.drawImageRect(sourceImage, sourceRect, destRect, paint);
        }
      }
    }
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(atlasWidth, atlasHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final atlasImageBytes = byteData!.buffer.asUint8List();

    final atlasFileName = '$atlasBaseName.png';
    
    // Remap GIDs
    final Map<int, int> gidRemapTable = {};
    int newLocalId = 0;

    final atlasTileset = Tileset(
      name: atlasBaseName,
      firstGid: 1,
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

    _remapMapGids(map, gidRemapTable);
    
    map.tilesets..clear()..add(atlasTileset);

    _ref.read(talkerProvider).info('Atlas packing complete.');
    return _PackAtlasResult(map, atlasImageBytes, atlasFileName);
  }

  void _remapMapGids(TiledMap map, Map<int, int> remapTable) {
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (int y = 0; y < layer.height; y++) {
          for (int x = 0; x < layer.width; x++) {
            final oldGid = layer.tileData![y][x];
            if (oldGid.tile != 0) {
              final newGidTile = remapTable[oldGid.tile];
              if (newGidTile != null) {
                layer.tileData![y][x] = Gid(newGidTile, oldGid.flips);
              }
            }
          }
        }
      } else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          if (object.gid != null) {
            final newGid = remapTable[object.gid];
            if (newGid != null) {
              object.gid = newGid;
            }
          }
        }
      }
    }
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
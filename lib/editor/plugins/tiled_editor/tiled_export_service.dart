import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/tiled_editor/tmj_writer.dart';
import 'package:machine/editor/plugins/tiled_editor/tmx_writer.dart';
import 'package:machine/logs/logs_provider.dart';
import 'package:tiled/tiled.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/utils/texture_packer_algo.dart';

import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart' show TexturePackerProject, SourceImageNode, SourceImageConfig, GridRect, PackerItemType;
import 'package:machine/editor/plugins/flow_graph/services/flow_export_service.dart';
import 'package:machine/editor/plugins/flow_graph/models/flow_graph_models.dart';
import 'package:machine/editor/plugins/flow_graph/flow_graph_asset_resolver.dart';

import 'tiled_asset_resolver.dart';

class _UnifiedAssetSource {
  /// Canonical path to the source image file
  final String sourcePath;
  final ui.Rect sourceRect;
  final ui.Image? image; 

  _UnifiedAssetSource({
    required this.sourcePath,
    required this.sourceRect,
    this.image,
  });

  int get width => sourceRect.width.toInt();
  int get height => sourceRect.height.toInt();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _UnifiedAssetSource &&
          sourcePath == other.sourcePath &&
          sourceRect == other.sourceRect;

  @override
  int get hashCode => Object.hash(sourcePath, sourceRect);
}

class _ExportCollection {
  final Set<_UnifiedAssetSource> uniqueAssets;
  final Map<int, _UnifiedAssetSource> gidToSource;
  final Map<String, _UnifiedAssetSource> spriteToSource;

  _ExportCollection({
    required this.uniqueAssets,
    required this.gidToSource,
    required this.spriteToSource,
  });
}

// GID Flag Helpers
const int _flippedHorizontallyFlag = 0x80000000;
const int _flippedVerticallyFlag = 0x40000000;
const int _flippedDiagonallyFlag = 0x20000000;
const int _flippedMask = _flippedHorizontallyFlag | _flippedVerticallyFlag | _flippedDiagonallyFlag;
const int _gidMask = ~_flippedMask;

int _getCleanGid(int gid) => gid & _gidMask;
int _getGidFlags(int gid) => gid & _flippedMask;

class _UnifiedPackResult {
  final Uint8List atlasImageBytes;
  final int atlasWidth;
  final int atlasHeight;
  final Map<String, ui.Rect> packedRects;

  _UnifiedPackResult({
    required this.atlasImageBytes,
    required this.atlasWidth,
    required this.atlasHeight,
    required this.packedRects,
  });
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
    bool removeUnused = true,
    bool asJson = false,
    bool packInAtlas = true,
  }) async {
    final talker = _ref.read(talkerProvider);
    final repo = resolver.repo;
    talker.info('Starting unified map export...');

    // 1. Deep copy map to avoid mutating editor state
    TiledMap mapToExport = _deepCopyMap(map);

    // 2. Process external FlowGraph dependencies (export .fg -> .json)
    await _processFlowGraphDependencies(mapToExport, resolver, destinationFolderUri);

    if (packInAtlas) {
      // 3a. Collect unique assets (Deduped by path + rect)
      final collection = await _collectUnifiedAssets(mapToExport, resolver);

      if (collection.uniqueAssets.isNotEmpty) {
        talker.info('Collected ${collection.uniqueAssets.length} unique assets to pack.');

        // 3b. Pack Assets
        final packResult = await _packUnifiedAtlas(collection.uniqueAssets, atlasFileName);
        talker.info('Atlas packing complete. ${packResult.atlasWidth}x${packResult.atlasHeight}');

        // 3c. Generate New GIDs
        // Sort assets by source path for deterministic GID assignment
        final sortedAssets = collection.uniqueAssets.toList()
          ..sort((a, b) => a.sourcePath.compareTo(b.sourcePath));

        final sourceToNewGid = <_UnifiedAssetSource, int>{};
        int currentGid = 1; // Tiled GIDs start at 1

        for (final asset in sortedAssets) {
          sourceToNewGid[asset] = currentGid++;
        }

        // 3d. Build Remap Tables
        final gidRemap = <int, int>{};
        final spriteRemap = <String, int>{};

        // Map Old GID -> New GID
        collection.gidToSource.forEach((oldGid, asset) {
          if (sourceToNewGid.containsKey(asset)) {
            gidRemap[oldGid] = sourceToNewGid[asset]!;
          }
        });

        // Map Sprite Name -> New GID
        collection.spriteToSource.forEach((name, asset) {
          if (sourceToNewGid.containsKey(asset)) {
            spriteRemap[name] = sourceToNewGid[asset]!;
          }
        });

        // 3e. Apply Remapping to Map Layer Data
        _remapMapGids(mapToExport, gidRemap, spriteRemap);

        // 3f. Replace Tilesets with Single Atlas Tileset
        _finalizeTilesets(mapToExport, packResult, atlasFileName, sortedAssets);

        // 3g. Write Atlas Files
        await repo.createDocumentFile(
          destinationFolderUri,
          '$atlasFileName.png',
          initialBytes: packResult.atlasImageBytes,
          overwrite: true,
        );
        
        // Generate JSON with sprite names as keys for easy lookup in engine
        await repo.createDocumentFile(
          destinationFolderUri,
          '$atlasFileName.json',
          initialContent: _generatePixiJson(packResult, atlasFileName, sortedAssets),
          overwrite: true,
        );
      } else {
        talker.warning("No assets found to pack. Clearing tilesets.");
        mapToExport.tilesets.clear();
      }
    } else {
      // 4. Legacy Mode: Just copy files
      await _copyAndRelinkAssets(mapToExport, resolver, destinationFolderUri);
    }

    // 5. Write Map File
    final String fileContent = asJson ? TmjWriter(mapToExport).toTmj() : TmxWriter(mapToExport).toTmx();
    final String fileExtension = asJson ? 'json' : 'tmx';
    
    await repo.createDocumentFile(
      destinationFolderUri,
      '$mapFileName.$fileExtension',
      initialContent: fileContent,
      overwrite: true,
    );

    talker.info('Export complete: $mapFileName.$fileExtension');
  }
  
    void _finalizeTilesets(
    TiledMap map, 
    _UnifiedPackResult result, 
    String atlasName, 
    List<_UnifiedAssetSource> sortedAssets
  ) {
    final newTiles = <Tile>[];
    
    // Create tile definitions for the new Tileset
    for (int i = 0; i < sortedAssets.length; i++) {
      final asset = sortedAssets[i];
      final rect = result.packedRects[asset.hashCode.toString()]!;
      
      // We store the original source info in properties for debugging/reverse mapping
      final newTile = Tile(
        localId: i,
        properties: CustomProperties({
          'atlas_coords': StringProperty(
            name: 'atlas_coords', 
            value: '${rect.left.toInt()},${rect.top.toInt()},${rect.width.toInt()},${rect.height.toInt()}'
          ),
          'original_source': StringProperty(name: 'original_source', value: asset.sourcePath),
        }),
      );
      
      // Tiled Image Collection support:
      // If we wanted to strictly support Tiled visualization of irregular atlases, 
      // we would set `image` on this Tile individually. 
      // However, since we generated a single Big Image, we set that on the Tileset.
      // NOTE: Tiled DOES NOT support irregular grids on a single image tileset easily. 
      // The map will look correct in Engine (using JSON data), but might look jumbled in Tiled 
      // if opened directly unless we forced a grid (which MaxRects doesn't do).
      // For this implementation, we assume Engine priority.
      
      newTiles.add(newTile);
    }

    final newTileset = Tileset(
      name: atlasName,
      firstGid: 1,
      // We set tileWidth/Height to the smallest unit or map default to satisfy Tiled schema
      tileWidth: map.tileWidth, 
      tileHeight: map.tileHeight,
      tileCount: newTiles.length,
      columns: 0, // 0 implies Image Collection or irregular
      image: TiledImage(
        source: '$atlasName.png', 
        width: result.atlasWidth, 
        height: result.atlasHeight
      ),
    )..tiles = newTiles;

    map.tilesets..clear()..add(newTileset);
    
    // Clean up development-only properties
    map.properties.byName.remove('tp_atlases');
  }
  
  void _remapAndFinalizeMap(
    TiledMap map, 
    _UnifiedPackResult result, 
    String atlasName, 
    Map<_UnifiedAssetSource, int> sourceToNewGid
  ) {
    final newTiles = <Tile>[];
    
    // Create tiles for the new Tileset
    sourceToNewGid.forEach((asset, newGid) {
      final localId = newGid - 1;
      final rect = result.packedRects[asset.hashCode.toString()]!; // Retrieve packed rect
      
      // We define a tile with custom properties indicating its region in the atlas
      final newTile = Tile(
        localId: localId,
        properties: CustomProperties({
          'atlas_rect': StringProperty(
            name: 'atlas_rect', 
            value: '${rect.left.toInt()},${rect.top.toInt()},${rect.width.toInt()},${rect.height.toInt()}'
          ),
          'original_source': StringProperty(name: 'original_source', value: asset.sourcePath),
        }),
      );
      newTiles.add(newTile);
    });

    // Create the single unified Tileset
    final newTileset = Tileset(
      name: atlasName,
      firstGid: 1,
      tileWidth: map.tileWidth,   // Keep map defaults
      tileHeight: map.tileHeight, // Keep map defaults
      tileCount: newTiles.length,
      columns: 0, // 0 columns often implies image collection or non-grid
      image: TiledImage(
        source: '$atlasName.png', 
        width: result.atlasWidth, 
        height: result.atlasHeight
      ),
    )..tiles = newTiles;

    map.tilesets..clear()..add(newTileset);
    
    // Perform the GID replacement on layers
    // We pass the maps we built in exportMap
    // (Note: The caller of this method needs to pass gidRemap/spriteRemap, 
    //  OR we move the map creation logic inside here. 
    //  For this snippet, assume we pass the maps created in Step 3 above).
  }

Future<_ExportCollection> _collectUnifiedAssets(TiledMap map, TiledAssetResolver resolver) async {
    final talker = _ref.read(talkerProvider);
    final uniqueAssets = <_UnifiedAssetSource>{};
    final gidToSource = <int, _UnifiedAssetSource>{};
    final spriteToSource = <String, _UnifiedAssetSource>{};

    // 1. Collect from Tile Layers (GIDs)
    final usedGids = _findUsedGids(map);
    for (final gid in usedGids) {
      final cleanGid = _getCleanGid(gid);
      if (cleanGid == 0) continue;

      final tile = map.tileByGid(cleanGid);
      final tileset = map.tilesetByTileGId(cleanGid);
      
      if (tileset != null) {
        final imageSource = tile?.image?.source ?? tileset.image?.source;
        if (imageSource != null) {
          final image = resolver.getImage(imageSource, tileset: tileset);
          
          if (image != null) {
            // Determine the context path to resolve the absolute/canonical path for equality checks
            final contextPath = (tileset.source != null) 
                ? resolver.repo.resolveRelativePath(resolver.tmxPath, tileset.source!) 
                : resolver.tmxPath;
            final canonicalPath = resolver.repo.resolveRelativePath(contextPath, imageSource);

            // Calculate precise source rect for this tile
            final rect = tileset.computeDrawRect(tile ?? Tile(localId: cleanGid - tileset.firstGid!));
            final sourceRect = ui.Rect.fromLTWH(
                rect.left.toDouble(), rect.top.toDouble(), 
                rect.width.toDouble(), rect.height.toDouble()
            );

            final asset = _UnifiedAssetSource(
              sourcePath: canonicalPath,
              sourceRect: sourceRect,
              image: image,
            );

            uniqueAssets.add(asset);
            gidToSource[cleanGid] = asset;
          }
        }
      }
    }

    // 2. Collect from Object Layers (Texture Packer Sprites)
    final tpAtlasesProp = map.properties['tp_atlases'];
    if (tpAtlasesProp is StringProperty && tpAtlasesProp.value.isNotEmpty) {
      final tpackerFiles = tpAtlasesProp.value.split(',').map((e) => e.trim());

      for (final layer in map.layers) {
        if (layer is ObjectGroup) {
          for (final obj in layer.objects) {
            final spriteProp = obj.properties['tp_sprite'];
            if (spriteProp is StringProperty && spriteProp.value.isNotEmpty) {
              final spriteName = spriteProp.value;
              final spriteData = _findSpriteDataInAtlases(spriteName, tpackerFiles, resolver);
              
              if (spriteData != null) {
                // Determine path for the atlas source image
                // Note: The spriteData contains a ui.Image, but we need a path for equality.
                // We assume spriteData comes from a loaded AssetData which has a path.
                // For simplicity here, we rely on the object identity or create a composite key.
                // Since we don't have the path easily in spriteData, we use the spriteName + unique ID assumption 
                // OR we fetch the path from the resolver logic if possible.
                // *Fix*: We will use the spriteName as a proxy key if path isn't available, 
                // but ideally TexturePackerAssetData should store source paths. 
                // Given current constraints, we construct a key.
                
                final asset = _UnifiedAssetSource(
                  sourcePath: "sprite:$spriteName", // Virtual path for sprite reference
                  sourceRect: spriteData.sourceRect,
                  image: spriteData.sourceImage,
                );

                uniqueAssets.add(asset);
                spriteToSource[spriteName] = asset;
              }
            }
          }
        }
      }
    }

    // 3. Image Layers
    for(final layer in map.layers) {
      if (layer is ImageLayer && layer.image.source != null) {
        final canonicalPath = resolver.repo.resolveRelativePath(resolver.tmxPath, layer.image.source!);
        final image = resolver.getImage(layer.image.source);
        if (image != null) {
          final asset = _UnifiedAssetSource(
            sourcePath: canonicalPath,
            sourceRect: ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
            image: image,
          );
          uniqueAssets.add(asset);
          // Image Layers don't use GIDs or Sprite Names for mapping, they render directly.
          // But we pack them to ensure they are in the atlas if "packInAtlas" is true.
        }
      }
    }

    return _ExportCollection(
      uniqueAssets: uniqueAssets, 
      gidToSource: gidToSource, 
      spriteToSource: spriteToSource
    );
  }

  TexturePackerSpriteData? _findSpriteDataInAtlases(String spriteName, Iterable<String> tpackerFiles, TiledAssetResolver resolver) {
    for (final path in tpackerFiles) {
      final canonicalKey = resolver.repo.resolveRelativePath(resolver.tmxPath, path);
      final asset = resolver.getAsset(canonicalKey);
      if (asset is TexturePackerAssetData) {
        if (asset.frames.containsKey(spriteName)) return asset.frames[spriteName]!;
        if (asset.animations.containsKey(spriteName)) {
          final firstFrameName = asset.animations[spriteName]!.firstOrNull;
          if (firstFrameName != null && asset.frames.containsKey(firstFrameName)) {
            return asset.frames[firstFrameName]!;
          }
        }
      }
    }
    return null;
  }
  
  Future<_UnifiedPackResult> _packUnifiedAtlas(Set<_UnifiedAssetSource> assets, String atlasName) async {
    final items = assets.map((asset) => PackerInputItem(
      width: asset.width.toDouble(),
      height: asset.height.toDouble(),
      data: asset,
    )).toList();

    final packer = MaxRectsPacker(padding: 2);
    final packedResult = packer.pack(items);

    final potWidth = _nextPowerOfTwo(packedResult.width.toInt());
    final potHeight = _nextPowerOfTwo(packedResult.height.toInt());
    
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    final packedRects = <String, ui.Rect>{};

    for (final item in packedResult.items) {
      final source = item.data as _UnifiedAssetSource;
      final destRect = ui.Rect.fromLTWH(item.x, item.y, item.width, item.height);
      canvas.drawImageRect(source.sourceImage, source.sourceRect, destRect, paint);
      packedRects[source.uniqueId] = destRect;
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(potWidth, potHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    if (byteData == null) throw Exception('Failed to encode atlas image.');

    return _UnifiedPackResult(
      atlasImageBytes: byteData.buffer.asUint8List(),
      atlasWidth: potWidth,
      atlasHeight: potHeight,
      packedRects: packedRects,
    );
  }

  // START: PHASE 3 CODE

  /// Phase 3: Rewrites the TiledMap data to use the newly created atlas.
  void _remapAndFinalizeMap(TiledMap map, _UnifiedPackResult result, String atlasName) {
    final newTiles = <Tile>[];
    final gidRemap = <int, int>{}; // Maps old GID -> new GID
    final spriteRemap = <String, int>{}; // Maps sprite name -> new GID

    int currentLocalId = 0;

    // Sort keys for deterministic GID assignment
    final sortedKeys = result.packedRects.keys.toList()..sort();

    // 1. Create a new Tile entry in the tileset for each packed asset.
    for (final uniqueId in sortedKeys) {
      final rect = result.packedRects[uniqueId]!;
      // This tile doesn't need its own image; it's just a reference
      // to a region of the main tileset image.
      final newTile = Tile(
        localId: currentLocalId,
        // Custom property to store the source rect, which some engines might use.
        properties: CustomProperties({'sourceRect': StringProperty(name: 'sourceRect', value: '${rect.left},${rect.top},${rect.width},${rect.height}')}),
      );
      newTiles.add(newTile);

      // 2. Populate the remapping tables.
      // The new GID is the tile's local ID + the tileset's firstGid (which is 1).
      final newGid = currentLocalId + 1;
      if (uniqueId.startsWith('gid_')) {
        final oldGid = int.parse(uniqueId.substring(4));
        gidRemap[oldGid] = newGid;
      } else {
        spriteRemap[uniqueId] = newGid;
      }
      currentLocalId++;
    }

    // 3. Create the single, unified Tileset.
    final newTileset = Tileset(
      name: atlasName,
      firstGid: 1, // It's the only tileset, so it starts at 1.
      tileWidth: map.tileWidth, // Use the map's original tile dimensions.
      tileHeight: map.tileHeight,
      tileCount: newTiles.length,
      columns: result.atlasWidth ~/ map.tileWidth, // Calculate columns based on atlas width.
      image: TiledImage(source: '$atlasName.png', width: result.atlasWidth, height: result.atlasHeight),
    )..tiles = newTiles;

    // 4. Replace all old tilesets with the new one.
    map.tilesets..clear()..add(newTileset);
    
    // 5. Rewrite all GIDs in the map's layers and objects.
    _remapMapGids(map, gidRemap, spriteRemap);

    // 6. Clean up obsolete properties.
    map.properties.byName.remove('tp_atlases');
  }

  /// Helper for Phase 3 that iterates through layers and objects to update their GIDs.
void _remapMapGids(TiledMap map, Map<int, int> gidRemap, Map<String, int> spriteRemap) {
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (int y = 0; y < layer.height; y++) {
          for (int x = 0; x < layer.width; x++) {
            final rawGid = layer.tileData![y][x].tile; // .tile property in this library usually holds the full int including flags? 
            // Note: The 'tiled' library Gid object splits index and flags. 
            // However, to ensure binary accuracy during export re-mapping, we often treat it as raw int.
            // If the library provides .tile as the raw ID (flags stripped) and .flips separately:
            
            final oldCleanId = layer.tileData![y][x].tile;
            final flips = layer.tileData![y][x].flips;
            
            if (oldCleanId != 0 && gidRemap.containsKey(oldCleanId)) {
              final newCleanId = gidRemap[oldCleanId]!;
              // We construct a new Gid object with the new ID but existing flips
              layer.tileData![y][x] = Gid(newCleanId, flips);
            }
          }
        }
      } 
      else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          if (object.gid != null) {
            final rawGid = object.gid!;
            final oldCleanId = _getCleanGid(rawGid);
            final flags = _getGidFlags(rawGid);

            if (gidRemap.containsKey(oldCleanId)) {
              final newCleanId = gidRemap[oldCleanId]!;
              object.gid = newCleanId | flags;
            }
          }
          
          // Handle Texture Packer sprites referenced by custom property
          final spriteProp = object.properties['tp_sprite'];
          if (spriteProp is StringProperty && spriteProp.value.isNotEmpty) {
            final newGid = spriteRemap[spriteProp.value];
            if (newGid != null) {
              // Sprites from TP usually default to no flags unless the object was rotated, 
              // but Tiled objects store rotation separately from GID flags usually.
              // We preserve existing flags if any were set on the placeholder object.
              final flags = object.gid != null ? _getGidFlags(object.gid!) : 0;
              object.gid = newGid | flags;
              
              // Clean up the property since it's now a native GID
              object.properties.byName.remove('tp_sprite');
              // Ensure dimensions match the new packed sprite if width/height were 0
              // (This part is handled during object loading/rendering usually, but good to reset for export if needed)
            }
          }
        }
      }
    }
  }

  // END: PHASE 3 CODE

String _generatePixiJson(_UnifiedPackResult result, String atlasName) {
    final frames = <String, dynamic>{};
    
    // Sort keys for deterministic output
    final sortedKeys = result.packedRects.keys.toList()..sort();

    for (final uniqueId in sortedKeys) {
      final rect = result.packedRects[uniqueId]!;
      
      // For GIDs, we might want to store them simply as "1", "2" etc or keep "gid_1"
      // Usually engines prefer clean names.
      // If it's a sprite name (e.g. "hero_run"), use that. 
      // If it's a GID, stripping "gid_" might be cleaner for array-based lookups, 
      // but "gid_1" is safer to avoid collisions with sprite names starting with numbers.
      
      frames[uniqueId] = {
        "frame": {
          "x": rect.left.toInt(),
          "y": rect.top.toInt(),
          "w": rect.width.toInt(),
          "h": rect.height.toInt()
        },
        "rotated": false,
        "trimmed": false,
        "spriteSourceSize": {
          "x": 0,
          "y": 0,
          "w": rect.width.toInt(),
          "h": rect.height.toInt()
        },
        "sourceSize": {
          "w": rect.width.toInt(),
          "h": rect.height.toInt()
        },
        // Anchor is generic, engines usually override this or read from meta
        "anchor": {"x": 0.5, "y": 0.5} 
      };
    }
    
    final jsonOutput = {
      "frames": frames,
      "meta": {
        "app": "Machine Editor",
        "version": "1.0",
        "image": "$atlasName.png",
        "format": "RGBA8888",
        "size": {"w": result.atlasWidth, "h": result.atlasHeight},
        "scale": "1"
      }
    };
    return const JsonEncoder.withIndent('  ').convert(jsonOutput);
  }

  int _nextPowerOfTwo(int v) {
    v--; v |= v >> 1; v |= v >> 2; v |= v >> 4; v |= v >> 8; v |= v >> 16; v++;
    return v;
  }

  // START: PHASE 4 CODE

  /// Phase 4: Process and relink external file dependencies like FlowGraphs.
  Future<void> _processFlowGraphDependencies(TiledMap mapToExport, TiledAssetResolver resolver, String destinationFolderUri) async {
    final talker = _ref.read(talkerProvider);
    final repo = resolver.repo;
    final flowService = _ref.read(flowExportServiceProvider);

    for (final layer in mapToExport.layers) {
      if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          final prop = obj.properties['flowGraph'];
          if (prop is StringProperty && prop.value.isNotEmpty) {
            try {
              // 1. Resolve the .fg file path
              final fgCanonicalKey = repo.resolveRelativePath(resolver.tmxPath, prop.value);
              final fgFile = await repo.fileHandler.resolvePath(repo.rootUri, fgCanonicalKey);
              if (fgFile == null) continue;
              
              // 2. Read, parse, and export the FlowGraph to JSON
              final content = await repo.readFile(fgFile.uri);
              final graph = FlowGraph.deserialize(content);
              final fgPath = repo.fileHandler.getPathForDisplay(fgFile.uri, relativeTo: repo.rootUri);
              final fgResolver = FlowGraphAssetResolver(resolver.rawAssets, repo, fgPath);
              final exportName = p.basenameWithoutExtension(fgFile.name);

              await flowService.export(
                graph: graph,
                resolver: fgResolver,
                destinationFolderUri: destinationFolderUri,
                fileName: exportName,
                embedSchema: true, // Embedding schema is good for distribution
              );
              
              // 3. Update the property on the Tiled object to point to the new .json file
              obj.properties.byName['flowGraph'] = StringProperty(name: 'flowGraph', value: '$exportName.json');

            } catch (e) {
              talker.warning('Failed to export Flow Graph dependency "${prop.value}": $e');
            }
          }
        }
      }
    }
  }

  /// Phase 4: Alternative workflow for when atlas packing is disabled.
  /// Copies assets to the destination and updates their links.
  Future<void> _copyAndRelinkAssets(TiledMap mapToExport, TiledAssetResolver resolver, String destinationFolderUri) async {
    final repo = resolver.repo;
    for (final tileset in mapToExport.tilesets) {
      if (tileset.image?.source != null) {
        final rawSource = tileset.image!.source!;
        // Determine context (TMX or external TSX)
        final contextPath = (tileset.source != null) 
            ? repo.resolveRelativePath(resolver.tmxPath, tileset.source!) 
            : resolver.tmxPath;
        
        final canonicalKey = repo.resolveRelativePath(contextPath, rawSource);
        final file = await repo.fileHandler.resolvePath(repo.rootUri, canonicalKey);

        if (file != null) {
          await repo.copyDocumentFile(file, destinationFolderUri);
          final oldImage = tileset.image!;
          // Update the path to be relative to the new map location
          tileset.image = TiledImage(source: file.name, width: oldImage.width, height: oldImage.height);
          // Nullify the external source to embed the tileset definition
          tileset.source = null; 
        }
      }
    }
    // Repeat for Image Layers
    for (final layer in mapToExport.layers) {
      if (layer is ImageLayer && layer.image.source != null) {
        final rawSource = layer.image.source!;
        final canonicalKey = repo.resolveRelativePath(resolver.tmxPath, rawSource);
        final file = await repo.fileHandler.resolvePath(repo.rootUri, canonicalKey);
        if (file != null) {
          await repo.copyDocumentFile(file, destinationFolderUri);
          final oldImage = layer.image;
          layer.image = TiledImage(source: file.name, width: oldImage.width, height: oldImage.height);
        }
      }
    }
  }

  // END: PHASE 4 CODE

  Set<int> _findUsedGids(TiledMap map) {
    final usedGids = <int>{};
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (final row in layer.tileData!) for (final gid in row) if (gid.tile != 0) usedGids.add(gid.tile);
      } else if (layer is ObjectGroup) {
        for (final object in layer.objects) if (object.gid != null) usedGids.add(object.gid!);
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
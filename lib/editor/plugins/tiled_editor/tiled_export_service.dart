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
import 'package:machine/utils/texture_packer_algo.dart'; // Retained for type references if needed

import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart' show TexturePackerAssetData;
import 'package:machine/editor/plugins/flow_graph/services/flow_export_service.dart';
import 'package:machine/editor/plugins/flow_graph/models/flow_graph_models.dart';
import 'package:machine/editor/plugins/flow_graph/flow_graph_asset_resolver.dart';

import 'tiled_asset_resolver.dart';

final tiledExportServiceProvider = Provider<TiledExportService>((ref) {
  return TiledExportService(ref);
});

class _UnifiedAssetSource {
  final String uniqueId;
  final ui.Image sourceImage;
  final ui.Rect sourceRect;
  final int width;
  final int height;

  _UnifiedAssetSource({
    required this.uniqueId,
    required this.sourceImage,
    required this.sourceRect,
  }) : width = sourceRect.width.toInt(),
       height = sourceRect.height.toInt();

  @override
  bool operator ==(Object other) => other is _UnifiedAssetSource && other.uniqueId == uniqueId;
  @override
  int get hashCode => uniqueId.hashCode;
}

class _UnifiedPackResult {
  final Uint8List atlasImageBytes;
  final int atlasWidth;
  final int atlasHeight;
  final int columns;
  final Map<String, ui.Rect> packedRects;
  final Map<String, int> idToGid;

  _UnifiedPackResult({
    required this.atlasImageBytes,
    required this.atlasWidth,
    required this.atlasHeight,
    required this.columns,
    required this.packedRects,
    required this.idToGid,
  });
}

class TiledExportService {
  final Ref _ref;
  TiledExportService(this._ref);

  // --- Tiled Flag Constants ---
  static const int _flippedHorizontallyFlag = 0x80000000;
  static const int _flippedVerticallyFlag = 0x40000000;
  static const int _flippedDiagonallyFlag = 0x20000000;
  static const int _flagMask = _flippedHorizontallyFlag | _flippedVerticallyFlag | _flippedDiagonallyFlag;
  static const int _gidMask = ~_flagMask;

  /// Extracts the pure ID without flags.
  int _getCleanGid(int gid) => gid & _gidMask;

  /// Extracts only the flags.
  int _getGidFlags(int gid) => gid & _flagMask;

  /// Calculates the next power of two for a given number.
  int _nextPowerOfTwo(int v) {
    if (v <= 0) return 2;
    v--;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    v++;
    return v;
  }

  Future<void> exportMap({
    required TiledMap map,
    required TiledAssetResolver resolver,
    required String destinationFolderUri,
    required String mapFileName,
    required String atlasFileName,
    bool removeUnused = true, 
    bool asJson = false,
    bool packInAtlas = true,
    bool packAssetsOnly = false,
  }) async {
    final talker = _ref.read(talkerProvider);
    final repo = resolver.repo;
    talker.info('Starting map export...');

    // Work on a deep copy so we don't mutate the editor state
    TiledMap mapToExport = _deepCopyMap(map);

    // 1. Process Dependencies (Flow Graphs, etc.)
    await _processFlowGraphDependencies(mapToExport, resolver, destinationFolderUri);

    if (packInAtlas) {
      // 2. Collect Assets
      final assetsToPack = await _collectUnifiedAssets(mapToExport, resolver);

      if (assetsToPack.isNotEmpty) {
        talker.info('Collected ${assetsToPack.length} unique graphical assets to pack.');
        
        // 3. Pack Atlas (Strict Grid for Tiled Compatibility)
        final packResult = await _packUnifiedAtlasGrid(assetsToPack, map.tileWidth, map.tileHeight);
        talker.info('Atlas packing complete. Size: ${packResult.atlasWidth}x${packResult.atlasHeight}, Cols: ${packResult.columns}');
        
        // 4. Write Atlas Files
        await repo.createDocumentFile(
          destinationFolderUri,
          '$atlasFileName.png',
          initialBytes: packResult.atlasImageBytes,
          overwrite: true,
        );
        await repo.createDocumentFile(
          destinationFolderUri,
          '$atlasFileName.json',
          initialContent: _generatePixiJson(packResult, atlasFileName),
          overwrite: true,
        );

        // 5. Update Map Data (Remap GIDs)
        if (!packAssetsOnly) {
          _remapAndFinalizeMap(mapToExport, packResult, atlasFileName);
        }

      } else {
        talker.info("No tiles or sprites found to pack into an atlas.");
        if (!packAssetsOnly) {
          mapToExport.tilesets.clear();
        }
      }
    } else {
      // Non-atlas mode: Copy raw assets
      await _copyAndRelinkAssets(mapToExport, resolver, destinationFolderUri);
    }
    
    // 6. Write the Map File
    if (!packAssetsOnly) {
      String fileContent = asJson ? TmjWriter(mapToExport).toTmj() : TmxWriter(mapToExport).toTmx();
      String fileExtension = asJson ? 'json' : 'tmx';
      await repo.createDocumentFile(
        destinationFolderUri,
        '$mapFileName.$fileExtension',
        initialContent: fileContent,
        overwrite: true,
      );
      talker.info('Unified export complete: $mapFileName.$fileExtension');
    } else {
      talker.info('Pack-only mode: Skipped generating map file.');
    }
  }

  Future<Set<_UnifiedAssetSource>> _collectUnifiedAssets(TiledMap map, TiledAssetResolver resolver) async {
    final talker = _ref.read(talkerProvider);
    final assets = <_UnifiedAssetSource>{};
    final seenKeys = <String>{};

    void addAsset(String key, ui.Image? image, ui.Rect srcRect) {
      if (image != null && !seenKeys.contains(key)) {
        seenKeys.add(key);
        assets.add(_UnifiedAssetSource(
          uniqueId: key,
          sourceImage: image,
          sourceRect: srcRect,
        ));
      }
    }

    // 1. Collect from Tile Layers
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (final row in layer.tileData!) {
          for (final gidData in row) {
            final rawGid = gidData.tile;
            final cleanGid = _getCleanGid(rawGid);
            if (cleanGid == 0) continue;

            final tileset = map.tilesetByTileGId(cleanGid);
            if (tileset == null) continue;

            final localId = cleanGid - tileset.firstGid!;
            final uniqueKey = 'tile_${tileset.name}_$localId';

            if (!seenKeys.contains(uniqueKey)) {
              final tile = map.tileByGid(cleanGid);
              final imageSource = tile?.image?.source ?? tileset.image?.source;
              
              if (imageSource != null) {
                final image = resolver.getImage(imageSource, tileset: tileset);
                if (image != null) {
                  final rect = tileset.computeDrawRect(tile ?? Tile(localId: localId));
                  addAsset(uniqueKey, image, ui.Rect.fromLTWH(
                    rect.left.toDouble(),
                    rect.top.toDouble(),
                    rect.width.toDouble(),
                    rect.height.toDouble(),
                  ));
                } else {
                   talker.warning('Could not find source image "$imageSource" for GID $cleanGid');
                }
              }
            }
          }
        }
      }
    }

    // 2. Collect from Object Layers
    for (final layer in map.layers) {
      if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          // A. Tile Objects (GID based)
          if (obj.gid != null) {
            final cleanGid = _getCleanGid(obj.gid!);
            if (cleanGid == 0) continue;
            
            final tileset = map.tilesetByTileGId(cleanGid);
            if (tileset != null) {
              final localId = cleanGid - tileset.firstGid!;
              final uniqueKey = 'tile_${tileset.name}_$localId';
              
              if (!seenKeys.contains(uniqueKey)) {
                 final tile = map.tileByGid(cleanGid);
                 final imageSource = tile?.image?.source ?? tileset.image?.source;
                 if (imageSource != null) {
                   final image = resolver.getImage(imageSource, tileset: tileset);
                   if (image != null) {
                     final rect = tileset.computeDrawRect(tile ?? Tile(localId: localId));
                     addAsset(uniqueKey, image, ui.Rect.fromLTWH(
                       rect.left.toDouble(), 
                       rect.top.toDouble(), 
                       rect.width.toDouble(), 
                       rect.height.toDouble()
                     ));
                   }
                 }
              }
            }
          }
          
          // B. Texture Packer Sprites (Custom property)
          final spriteProp = obj.properties['tp_sprite'];
          if (spriteProp is StringProperty && spriteProp.value.isNotEmpty) {
            final spriteName = spriteProp.value;
            final uniqueKey = 'sprite_$spriteName';
            
            final tpAtlasesProp = map.properties['tp_atlases'];
            if (tpAtlasesProp is StringProperty) {
               final tpackerFiles = tpAtlasesProp.value.split(',').map((e) => e.trim());
               final spriteData = _findSpriteDataInAtlases(spriteName, tpackerFiles, resolver);
               
               if (spriteData != null) {
                 addAsset(uniqueKey, spriteData.sourceImage, spriteData.sourceRect);
               } else {
                 talker.warning('Could not resolve sprite "$spriteName" from linked atlases.');
               }
            }
          }
        }
      }
    }

    // 3. Collect Image Layers
    for(final layer in map.layers) {
      if (layer is ImageLayer && layer.image.source != null) {
        final image = resolver.getImage(layer.image.source);
        if (image != null) {
          addAsset(
            'image_layer_${layer.id}',
            image,
            ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble())
          );
        } else {
          talker.warning('Could not find source image "${layer.image.source}" for Image Layer "${layer.name}"');
        }
      }
    }

    return assets;
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
  
  /// Packs assets into a strict grid compatible with Tiled's standard single-image tileset.
  /// Large assets will span multiple tiles (rows/cols).
  Future<_UnifiedPackResult> _packUnifiedAtlasGrid(Set<_UnifiedAssetSource> assets, int tileWidth, int tileHeight) async {
    // Sort to prioritize large items (Naive strategy) or ID for determinism.
    // Deterministic sort with height priority usually gives decent packing.
    final sortedAssets = assets.toList()..sort((a, b) {
       // Height Descending, then Width Descending, then ID Ascending
       if (a.height != b.height) return b.height.compareTo(a.height);
       if (a.width != b.width) return b.width.compareTo(a.width);
       return a.uniqueId.compareTo(b.uniqueId);
    });

    // Determine initial Atlas width (Power of Two)
    // Estimate total area
    double totalArea = 0;
    for(var a in sortedAssets) totalArea += (a.width * a.height);
    
    // Start with sqrt area, min 256
    int potSize = _nextPowerOfTwo(sqrt(totalArea).ceil());
    if (potSize < 256) potSize = 256;
    
    // Ensure width is at least the widest asset
    int maxAssetWidth = sortedAssets.isEmpty ? 0 : sortedAssets.map((e) => e.width).reduce(max);
    if (potSize < maxAssetWidth) potSize = _nextPowerOfTwo(maxAssetWidth);

    int columns = potSize ~/ tileWidth;
    if (columns < 1) {
      // Should not happen if potSize >= maxAssetWidth >= tileWidth
      // But safety fallback:
      potSize = _nextPowerOfTwo(tileWidth * sortedAssets.length);
      columns = potSize ~/ tileWidth;
    }

    // Grid tracker: grid[row][col] = isOccupied
    final List<List<bool>> grid = [];

    void ensureRows(int rowIndex) {
      while (grid.length <= rowIndex) {
        grid.add(List.filled(columns, false));
      }
    }

    bool checkFit(int c, int r, int wCells, int hCells) {
      ensureRows(r + hCells - 1);
      for (int y = 0; y < hCells; y++) {
        for (int x = 0; x < wCells; x++) {
          if (c + x >= columns) return false;
          if (grid[r + y][c + x]) return false;
        }
      }
      return true;
    }

    void markOccupied(int c, int r, int wCells, int hCells) {
      for (int y = 0; y < hCells; y++) {
        for (int x = 0; x < wCells; x++) {
          grid[r + y][c + x] = true;
        }
      }
    }

    final packedRects = <String, ui.Rect>{};
    final idToGid = <String, int>{};

    for (final asset in sortedAssets) {
      final wCells = (asset.width / tileWidth).ceil();
      final hCells = (asset.height / tileHeight).ceil();

      bool placed = false;
      int r = 0;
      
      // Infinite scroll search for spot
      while (!placed) {
        ensureRows(r + hCells); // Ensure we have enough rows to check
        for (int c = 0; c <= columns - wCells; c++) {
          if (checkFit(c, r, wCells, hCells)) {
            markOccupied(c, r, wCells, hCells);
            
            final px = (c * tileWidth).toDouble();
            final py = (r * tileHeight).toDouble();
            
            packedRects[asset.uniqueId] = ui.Rect.fromLTWH(px, py, asset.width.toDouble(), asset.height.toDouble());
            
            // GID is based on the top-left cell index.
            // Index = row * columns + col
            // GID = Index + 1 (since GID 0 is null)
            int gidIndex = (r * columns) + c + 1;
            idToGid[asset.uniqueId] = gidIndex;
            
            placed = true;
            break;
          }
        }
        if (!placed) r++;
      }
    }

    // Determine final height
    int totalRows = grid.length;
    // Trim empty rows at the end if any (not strictly necessary but cleaner)
    // (Omitted for brevity, grid usually grows tightly)
    
    int neededHeight = totalRows * tileHeight;
    int potHeight = _nextPowerOfTwo(neededHeight);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    for (final entry in packedRects.entries) {
      final id = entry.key;
      final destRect = entry.value;
      final asset = sortedAssets.firstWhere((a) => a.uniqueId == id);
      
      canvas.drawImageRect(asset.sourceImage, asset.sourceRect, destRect, paint);
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(potSize, potHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    if (byteData == null) throw Exception('Failed to encode atlas image.');

    return _UnifiedPackResult(
      atlasImageBytes: byteData.buffer.asUint8List(),
      atlasWidth: potSize,
      atlasHeight: potHeight,
      columns: columns,
      packedRects: packedRects,
      idToGid: idToGid,
    );
  }

  void _remapAndFinalizeMap(TiledMap map, _UnifiedPackResult result, String atlasName) {
    // Generate new tiles for the tileset
    // We only strictly need to define properties for tiles that correspond to our packed assets.
    // The Tileset itself is defined by the grid.
    final newTiles = <Tile>[];
    
    // Sort logic handled in pack? No, idToGid is the truth source now.
    // But we need to create tile definitions for Tiled XML.
    // Iterate our assets to create property definitions.
    result.idToGid.forEach((uniqueId, gid) {
      // Local ID in tileset = GID - FirstGid(1) = GID - 1
      final localId = gid - 1;
      final rect = result.packedRects[uniqueId]!;
      
      newTiles.add(Tile(
        localId: localId,
        properties: CustomProperties({
          'atlas_id': StringProperty(name: 'atlas_id', value: uniqueId),
          // Store rect so engines know exact sub-region if asset is smaller than tile grid
          'atlas_rect': StringProperty(name: 'atlas_rect', value: '${rect.left},${rect.top},${rect.width},${rect.height}'),
        }),
      ));
    });

    // Keep reference to old tilesets for lookup
    final oldTilesets = List<Tileset>.from(map.tilesets);

    // Create New Tileset
    final newTileset = Tileset(
      name: atlasName,
      firstGid: 1,
      tileWidth: map.tileWidth,
      tileHeight: map.tileHeight,
      tileCount: result.columns * (result.atlasHeight ~/ map.tileHeight), // Approximate total count
      columns: result.columns,
      image: TiledImage(source: '$atlasName.png', width: result.atlasWidth, height: result.atlasHeight),
    )..tiles = newTiles;

    // Perform Remap
    _performSafeRemap(map, oldTilesets, result.idToGid, result.packedRects);

    // Now safe to replace tilesets
    map.tilesets..clear()..add(newTileset);
    map.properties.byName.remove('tp_atlases');
  }

  void _performSafeRemap(
    TiledMap map, 
    List<Tileset> oldTilesets, 
    Map<String, int> keyToNewGid,
    Map<String, ui.Rect> keyToRect,
  ) {
    // Helper to find tileset in the OLD list
    Tileset? findTileset(int gid) {
      for (var i = oldTilesets.length - 1; i >= 0; i--) {
        if (oldTilesets[i].firstGid != null && oldTilesets[i].firstGid! <= gid) {
          return oldTilesets[i];
        }
      }
      return null;
    }

    // 1. Remap Tile Layers
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (int y = 0; y < layer.height; y++) {
          for (int x = 0; x < layer.width; x++) {
            final g = layer.tileData![y][x];
            final rawGid = g.tile;
            if (rawGid == 0) continue;

            final cleanGid = _getCleanGid(rawGid);
            final flags = _getGidFlags(rawGid);

            final oldTileset = findTileset(cleanGid);
            if (oldTileset != null) {
              final localId = cleanGid - oldTileset.firstGid!;
              final key = 'tile_${oldTileset.name}_$localId';

              if (keyToNewGid.containsKey(key)) {
                final newGid = keyToNewGid[key]! | flags;
                layer.tileData![y][x] = Gid(newGid, g.flips);
              } else {
                // If not found in atlas (should not happen if collected correctly), keep or clear?
                // Clear to avoid ghost tiles from old tileset indices pointing to new tileset images
                layer.tileData![y][x] = Gid.fromInt(0);
              }
            }
          }
        }
      } 
      // 2. Remap Object Layers
      else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          // A. Tile Objects
          if (object.gid != null) {
            final rawGid = object.gid!;
            final cleanGid = _getCleanGid(rawGid);
            final flags = _getGidFlags(rawGid);
            
            final oldTileset = findTileset(cleanGid);
            if (oldTileset != null) {
              final localId = cleanGid - oldTileset.firstGid!;
              final key = 'tile_${oldTileset.name}_$localId';
              
              if (keyToNewGid.containsKey(key)) {
                object.gid = keyToNewGid[key]! | flags;
                // Optional: Update size if needed
              }
            }
          }

          // B. Sprite Objects
          final spriteProp = object.properties['tp_sprite'];
          if (spriteProp is StringProperty && spriteProp.value.isNotEmpty) {
            final key = 'sprite_${spriteProp.value}';
            
            if (keyToNewGid.containsKey(key)) {
              final newGid = keyToNewGid[key]!;
              final currentFlags = object.gid != null ? _getGidFlags(object.gid!) : 0;
              object.gid = newGid | currentFlags;
              
              // Coordinate Fix: Top-Left (Rect) to Bottom-Left (Tiled Object)
              if (keyToRect.containsKey(key)) {
                final r = keyToRect[key]!;
                object.width = r.width;
                object.height = r.height;
                object.y += object.height;
              }
              
              object.properties.byName.remove('tp_sprite');
            }
          }
        }
      }
    }
  }

  String _generatePixiJson(_UnifiedPackResult result, String atlasName) {
    final frames = <String, dynamic>{};
    // Sort keys just to have stable JSON output
    final sortedKeys = result.packedRects.keys.toList()..sort();

    for (final uniqueId in sortedKeys) {
      final rect = result.packedRects[uniqueId]!;
      frames[uniqueId] = {
        "frame": {"x": rect.left.toInt(), "y": rect.top.toInt(), "w": rect.width.toInt(), "h": rect.height.toInt()},
        "rotated": false,
        "trimmed": false,
        "spriteSourceSize": {"x": 0, "y": 0, "w": rect.width.toInt(), "h": rect.height.toInt()},
        "sourceSize": {"w": rect.width.toInt(), "h": rect.height.toInt()},
        "anchor": {"x": 0.5, "y": 0.5}
      };
    }
    
    final jsonOutput = {
      "frames": frames,
      "meta": {
        "app": "Machine Editor - Unified Grid Export",
        "version": "1.0",
        "image": "$atlasName.png",
        "format": "RGBA8888",
        "size": {"w": result.atlasWidth, "h": result.atlasHeight},
        "scale": "1"
      }
    };
    return const JsonEncoder.withIndent('  ').convert(jsonOutput);
  }

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
              final fgCanonicalKey = repo.resolveRelativePath(resolver.tmxPath, prop.value);
              final fgFile = await repo.fileHandler.resolvePath(repo.rootUri, fgCanonicalKey);
              if (fgFile == null) continue;
              
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
                embedSchema: true,
              );
              
              obj.properties.byName['flowGraph'] = StringProperty(name: 'flowGraph', value: '$exportName.json');

            } catch (e) {
              talker.warning('Failed to export Flow Graph dependency "${prop.value}": $e');
            }
          }
        }
      }
    }
  }

  Future<void> _copyAndRelinkAssets(TiledMap mapToExport, TiledAssetResolver resolver, String destinationFolderUri) async {
    final repo = resolver.repo;
    
    // Copy Tileset Images
    for (final tileset in mapToExport.tilesets) {
      if (tileset.image?.source != null) {
        final rawSource = tileset.image!.source!;
        final contextPath = (tileset.source != null) 
            ? repo.resolveRelativePath(resolver.tmxPath, tileset.source!) 
            : resolver.tmxPath;
        
        final canonicalKey = repo.resolveRelativePath(contextPath, rawSource);
        final file = await repo.fileHandler.resolvePath(repo.rootUri, canonicalKey);

        if (file != null) {
          await repo.copyDocumentFile(file, destinationFolderUri);
          final oldImage = tileset.image!;
          tileset.image = TiledImage(source: file.name, width: oldImage.width, height: oldImage.height);
          tileset.source = null;
        }
      }
    }
    
    // Copy Image Layers
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
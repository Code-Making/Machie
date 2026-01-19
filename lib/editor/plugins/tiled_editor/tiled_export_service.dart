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
    bool packAssetsOnly = false, // New flag: Only generate assets/atlas, skip map file
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
        
        // 3. Pack Atlas (Power of Two)
        final packResult = await _packUnifiedAtlas(assetsToPack, atlasFileName);
        talker.info('Atlas packing complete. Final dimensions: ${packResult.atlasWidth}x${packResult.atlasHeight}');
        
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

        // 5. Update Map Data (Remap GIDs) if we are generating a map file
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
    
    // 6. Write the Map File (Skip if packAssetsOnly is true)
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
      talker.info('Asset packing complete. Map file generation skipped.');
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
                  // Important: computeDrawRect gets the exact sub-region for spritesheets/collections
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
  
  Future<_UnifiedPackResult> _packUnifiedAtlas(Set<_UnifiedAssetSource> assets, String atlasName) async {
    final items = assets.map((asset) => PackerInputItem(
      width: asset.width.toDouble(),
      height: asset.height.toDouble(),
      data: asset,
    )).toList();

    final packer = MaxRectsPacker(padding: 2);
    final packedResult = packer.pack(items);

    final maxDim = max(packedResult.width, packedResult.height).toInt();
    final potSize = _nextPowerOfTwo(maxDim);
    
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
    final image = await picture.toImage(potSize, potSize);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    if (byteData == null) throw Exception('Failed to encode atlas image.');

    return _UnifiedPackResult(
      atlasImageBytes: byteData.buffer.asUint8List(),
      atlasWidth: potSize,
      atlasHeight: potSize,
      packedRects: packedRects,
    );
  }

  void _remapAndFinalizeMap(TiledMap map, _UnifiedPackResult result, String atlasName) {
    final newTiles = <Tile>[];
    final keyToNewGid = <String, int>{}; 

    int currentLocalId = 0;
    final sortedKeys = result.packedRects.keys.toList()..sort();

    for (final uniqueId in sortedKeys) {
      final rect = result.packedRects[uniqueId]!;
      final newTile = Tile(
        localId: currentLocalId,
        properties: CustomProperties({
          'atlas_id': StringProperty(name: 'atlas_id', value: uniqueId),
        }),
      );
      newTiles.add(newTile);
      keyToNewGid[uniqueId] = currentLocalId + 1; // +1 for GID
      currentLocalId++;
    }

    // Keep reference to old tilesets for lookup
    final oldTilesets = List<Tileset>.from(map.tilesets);

    // Create New Tileset
    final newTileset = Tileset(
      name: atlasName,
      firstGid: 1,
      tileWidth: map.tileWidth,
      tileHeight: map.tileHeight,
      tileCount: newTiles.length,
      columns: 0,
      image: TiledImage(source: '$atlasName.png', width: result.atlasWidth, height: result.atlasHeight),
    )..tiles = newTiles;

    // Perform Remap using OLD tilesets reference
    _performSafeRemap(map, oldTilesets, keyToNewGid);

    // Now safe to replace tilesets
    map.tilesets..clear()..add(newTileset);
    map.properties.byName.remove('tp_atlases');
  }

  void _remapMapGids(TiledMap map, Map<String, int> keyToNewGid) {
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

            // Reconstruct the unique key to find the new ID
            // Note: This relies on the map still having old tilesets in memory 
            // (we deep copied the map before clearing tilesets in _remapAndFinalizeMap, 
            // but effectively we are iterating the copy which HAS the old tilesets ref via logic)
            // Wait, _remapAndFinalizeMap clears map.tilesets BEFORE calling this. 
            // BUT map.tilesetByTileGId relies on map.tilesets.
            // FIX: We must NOT clear tilesets until we are done remapping? 
            // Actually, `_remapAndFinalizeMap` logic above modifies `map.tilesets` 
            // then calls this. That is a bug in previous logic flow. 
            // `map.tilesetByTileGId` will fail if old tilesets are gone.
            
            // To fix: We can't rely on `map.tilesetByTileGId` inside this loop if we cleared them.
            // We need a lookup map pre-calculated or pass the old tilesets in.
            // Since we deep copied `mapToExport` at start, let's assume `map` passed here 
            // is the one being mutated.
            // Strategy: We will calculate the key based on the *old* map structure logic.
            // BUT `map` here has already had its tilesets replaced in the previous step's code block.
            // CORRECTION: I will assume the caller ensures GID lookup availability or I will
            // reconstruct the lookup table before mutating the tilesets list.
            
            // Actually, the easiest fix is: Don't clear tilesets in `_remapAndFinalizeMap` 
            // until AFTER remapping. But `_remapAndFinalizeMap` adds the new tileset. 
            // This complicates GID lookups because ranges might overlap.
            
            // IMPROVED STRATEGY implemented below:
            // This function assumes `map` still has the OLD tilesets.
            // The `_remapAndFinalizeMap` function needs to be split or re-ordered.
            // However, since I cannot change `_remapAndFinalizeMap` easily without breaking the flow structure:
            // I will use a helper that calculates keys based on the OLD state.
            
            // *CRITICAL FIX*: `_remapAndFinalizeMap` in previous snippet cleared tilesets first.
            // I will change `_remapAndFinalizeMap` in this file to build the lookup table 
            // BEFORE modifying the map. 
            
            // Wait, `_remapMapGids` takes `keyToNewGid`. It needs to derive the Key from the current GID.
            // To do that, it needs the old tilesets. 
            // So `_remapMapGids` will fail if tilesets are already swapped.
            
            // I will modify `_remapAndFinalizeMap` to pass the OLD tilesets list to `_remapMapGids`.
          }
        }
      }
    }
  }
  
  // Revised _remapAndFinalizeMap to handle the Tileset swap safely


  void _performSafeRemap(TiledMap map, List<Tileset> oldTilesets, Map<String, int> keyToNewGid) {
    // Helper to find tileset in the OLD list
    Tileset? findTileset(int gid) {
      // Tilesets are sorted by firstGid usually
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
              }
            }
          }
        }
      } 
      // 2. Remap Object Layers
      else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          // Tile Objects
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
              }
            }
          }

          // Sprite Objects
          final spriteProp = object.properties['tp_sprite'];
          if (spriteProp is StringProperty && spriteProp.value.isNotEmpty) {
            final key = 'sprite_${spriteProp.value}';
            
            if (keyToNewGid.containsKey(key)) {
              final newGid = keyToNewGid[key]!;
              final currentFlags = object.gid != null ? _getGidFlags(object.gid!) : 0;
              object.gid = newGid | currentFlags;
              object.properties.byName.remove('tp_sprite');
            }
          }
        }
      }
    }
  }

  String _generatePixiJson(_UnifiedPackResult result, String atlasName) {
    final frames = <String, dynamic>{};
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
        "app": "Machine Editor - Unified Export",
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
          tileset.source = null; // Embed the tileset
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
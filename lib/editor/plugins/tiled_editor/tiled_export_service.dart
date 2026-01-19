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

import 'package:machine/editor/plugins/flow_graph/services/flow_export_service.dart';
import 'package:machine/editor/plugins/flow_graph/models/flow_graph_models.dart';
import 'package:machine/editor/plugins/flow_graph/flow_graph_asset_resolver.dart';

import 'tiled_asset_resolver.dart';

// --- Provider Definition ---
final tiledExportServiceProvider = Provider<TiledExportService>((ref) {
  return TiledExportService(ref);
});

// --- Helper Classes ---

class _UnifiedAssetSource {
  /// Canonical path to the source image file or a unique key for sprites (e.g. "sprite:name")
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

class _UnifiedPackResult {
  final Uint8List atlasImageBytes;
  final int atlasWidth;
  final int atlasHeight;
  // Keys are the hashCode.toString() of the _UnifiedAssetSource
  final Map<String, ui.Rect> packedRects;

  _UnifiedPackResult({
    required this.atlasImageBytes,
    required this.atlasWidth,
    required this.atlasHeight,
    required this.packedRects,
  });
}

// --- Constants for GID Flags ---
const int _flippedHorizontallyFlag = 0x80000000;
const int _flippedVerticallyFlag = 0x40000000;
const int _flippedDiagonallyFlag = 0x20000000;
const int _flippedMask = _flippedHorizontallyFlag | _flippedVerticallyFlag | _flippedDiagonallyFlag;
const int _gidMask = ~_flippedMask;

int _getCleanGid(int gid) => gid & _gidMask;
int _getGidFlags(int gid) => gid & _flippedMask;


// --- Service Implementation ---

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

  // --- Collection Logic ---

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
          } else {
             talker.warning('Could not load image for GID $cleanGid: $imageSource');
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
                // Use a virtual path "sprite:Name" to ensure equality works correctly for sprites
                final asset = _UnifiedAssetSource(
                  sourcePath: "sprite:$spriteName", 
                  sourceRect: spriteData.sourceRect,
                  image: spriteData.sourceImage,
                );

                uniqueAssets.add(asset);
                spriteToSource[spriteName] = asset;
              } else {
                talker.warning('Could not resolve sprite "$spriteName"');
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
        }
      }
    }

    return _ExportCollection(
      uniqueAssets: uniqueAssets, 
      gidToSource: gidToSource, 
      spriteToSource: spriteToSource
    );
  }

  // --- Packing Logic ---

  Future<_UnifiedPackResult> _packUnifiedAtlas(Set<_UnifiedAssetSource> assets, String atlasName) async {
    final items = assets.map((asset) => PackerInputItem(
      width: asset.width.toDouble(),
      height: asset.height.toDouble(),
      data: asset,
    )).toList();

    // Use MaxRects packing algo
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
      
      if (source.image != null) {
        canvas.drawImageRect(source.image!, source.sourceRect, destRect, paint);
      }
      
      // Store using hashcode to map back in finalize step
      packedRects[source.hashCode.toString()] = destRect;
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

  // --- Remapping Logic ---

  void _remapMapGids(TiledMap map, Map<int, int> gidRemap, Map<String, int> spriteRemap) {
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (int y = 0; y < layer.height; y++) {
          for (int x = 0; x < layer.width; x++) {
            final rawGid = layer.tileData![y][x].tile;
            final flips = layer.tileData![y][x].flips;
            
            // Look up clean GID
            if (rawGid != 0 && gidRemap.containsKey(rawGid)) {
              final newGid = gidRemap[rawGid]!;
              layer.tileData![y][x] = Gid(newGid, flips);
            }
          }
        }
      } 
      else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          // Handle standard Tile Objects
          if (object.gid != null) {
            final rawGid = object.gid!;
            final oldCleanId = _getCleanGid(rawGid);
            final flags = _getGidFlags(rawGid);

            if (gidRemap.containsKey(oldCleanId)) {
              final newCleanId = gidRemap[oldCleanId]!;
              object.gid = newCleanId | flags; // Re-apply flags
            }
          }
          
          // Handle Texture Packer Sprites
          final spriteProp = object.properties['tp_sprite'];
          if (spriteProp is StringProperty && spriteProp.value.isNotEmpty) {
            final newGid = spriteRemap[spriteProp.value];
            if (newGid != null) {
              final flags = object.gid != null ? _getGidFlags(object.gid!) : 0;
              object.gid = newGid | flags;
              object.properties.byName.remove('tp_sprite');
            }
          }
        }
      }
    }
  }

  void _finalizeTilesets(
    TiledMap map, 
    _UnifiedPackResult result, 
    String atlasName, 
    List<_UnifiedAssetSource> sortedAssets
  ) {
    final newTiles = <Tile>[];
    
    for (int i = 0; i < sortedAssets.length; i++) {
      final asset = sortedAssets[i];
      final rect = result.packedRects[asset.hashCode.toString()]!;
      
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
      newTiles.add(newTile);
    }

    final newTileset = Tileset(
      name: atlasName,
      firstGid: 1,
      tileWidth: map.tileWidth,
      tileHeight: map.tileHeight,
      tileCount: newTiles.length,
      columns: 0, 
      image: TiledImage(
        source: '$atlasName.png', 
        width: result.atlasWidth, 
        height: result.atlasHeight
      ),
    )..tiles = newTiles;

    map.tilesets..clear()..add(newTileset);
    map.properties.byName.remove('tp_atlases');
  }

  String _generatePixiJson(
    _UnifiedPackResult result, 
    String atlasName, 
    List<_UnifiedAssetSource> sortedAssets
  ) {
    final frames = <String, dynamic>{};
    
    for (int i = 0; i < sortedAssets.length; i++) {
      final asset = sortedAssets[i];
      final rect = result.packedRects[asset.hashCode.toString()]!;
      
      // Use sprite name from path if available, else standard tile index
      String frameName;
      if (asset.sourcePath.startsWith('sprite:')) {
        frameName = asset.sourcePath.substring(7);
      } else {
        frameName = 'tile_$i'; 
      }

      frames[frameName] = {
        "frame": {
          "x": rect.left.toInt(),
          "y": rect.top.toInt(),
          "w": rect.width.toInt(),
          "h": rect.height.toInt()
        },
        "rotated": false,
        "trimmed": false,
        "spriteSourceSize": {
          "x": 0, "y": 0,
          "w": rect.width.toInt(),
          "h": rect.height.toInt()
        },
        "sourceSize": {
          "w": rect.width.toInt(),
          "h": rect.height.toInt()
        },
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

  // --- Dependency Processing ---

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

  // --- Legacy Copy Mode ---

  Future<void> _copyAndRelinkAssets(TiledMap mapToExport, TiledAssetResolver resolver, String destinationFolderUri) async {
    final repo = resolver.repo;
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

  // --- Utilities ---

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

  TiledMap _deepCopyMap(TiledMap original) {
    final writer = TmxWriter(original);
    final tmxString = writer.toTmx();
    return TileMapParser.parseTmx(tmxString);
  }

  int _nextPowerOfTwo(int v) {
    v--; v |= v >> 1; v |= v >> 2; v |= v >> 4; v |= v >> 8; v |= v >> 16; v++;
    return v;
  }
}
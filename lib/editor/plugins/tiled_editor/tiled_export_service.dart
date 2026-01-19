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

// --- Provider ---
final tiledExportServiceProvider = Provider<TiledExportService>((ref) {
  return TiledExportService(ref);
});

// --- Helper Data Structures ---

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
  /// Maps _UnifiedAssetSource.hashCode.toString() -> Packed Rect
  final Map<String, ui.Rect> packedRects;

  _UnifiedPackResult({
    required this.atlasImageBytes,
    required this.atlasWidth,
    required this.atlasHeight,
    required this.packedRects,
  });
}

// --- GID Constants ---
const int _flippedHorizontallyFlag = 0x80000000;
const int _flippedVerticallyFlag = 0x40000000;
const int _flippedDiagonallyFlag = 0x20000000;
const int _flippedMask = _flippedHorizontallyFlag | _flippedVerticallyFlag | _flippedDiagonallyFlag;
const int _gidMask = ~_flippedMask;

int _getCleanGid(int gid) => gid & _gidMask;
int _getGidFlags(int gid) => gid & _flippedMask;


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
    talker.info('Starting unified map export for $mapFileName');

    // 1. Work on a copy
    TiledMap mapToExport = _deepCopyMap(map);

    // 2. Export FlowGraphs referenced in objects
    await _processFlowGraphDependencies(mapToExport, resolver, destinationFolderUri);

    if (packInAtlas) {
      // 3. Collect Unique Assets (Tiles + Sprites)
      final collection = await _collectUnifiedAssets(mapToExport, resolver);

      if (collection.uniqueAssets.isNotEmpty) {
        talker.info('Packing ${collection.uniqueAssets.length} unique assets...');

        // 4. Pack into Atlas
        final packResult = await _packUnifiedAtlas(collection.uniqueAssets, atlasFileName);
        
        // 5. Create Source -> NewGID Mapping
        // Sort for determinism
        final sortedAssets = collection.uniqueAssets.toList()
          ..sort((a, b) => a.sourcePath.compareTo(b.sourcePath));

        final sourceToNewGid = <_UnifiedAssetSource, int>{};
        final newGidToRect = <int, ui.Rect>{}; // For updating object sizes
        int currentGid = 1;

        for (final asset in sortedAssets) {
          sourceToNewGid[asset] = currentGid;
          
          final packedRect = packResult.packedRects[asset.hashCode.toString()];
          if (packedRect != null) {
            newGidToRect[currentGid] = packedRect;
          }
          currentGid++;
        }

        // 6. Build Lookup Tables for Map Data
        final gidRemap = <int, int>{};
        final spriteRemap = <String, int>{};

        collection.gidToSource.forEach((oldGid, asset) {
          if (sourceToNewGid.containsKey(asset)) {
            gidRemap[oldGid] = sourceToNewGid[asset]!;
          }
        });

        collection.spriteToSource.forEach((name, asset) {
          if (sourceToNewGid.containsKey(asset)) {
            spriteRemap[name] = sourceToNewGid[asset]!;
          }
        });

        // 7. Remap GIDs in Map and Update Object Dimensions
        _remapMapGids(mapToExport, gidRemap, spriteRemap, newGidToRect);

        // 8. Generate and Assign the new Unified Tileset
        _finalizeTilesets(mapToExport, packResult, atlasFileName, sortedAssets);

        // 9. Save Atlas Image & JSON
        await repo.createDocumentFile(
          destinationFolderUri,
          '$atlasFileName.png',
          initialBytes: packResult.atlasImageBytes,
          overwrite: true,
        );
        
        await repo.createDocumentFile(
          destinationFolderUri,
          '$atlasFileName.json',
          initialContent: _generatePixiJson(packResult, atlasFileName, sortedAssets),
          overwrite: true,
        );

      } else {
        talker.warning("No assets to pack. Exporting map with empty tilesets.");
        mapToExport.tilesets.clear();
      }
    } else {
      // Legacy copy mode
      await _copyAndRelinkAssets(mapToExport, resolver, destinationFolderUri);
    }

    // 10. Save Map File
    final String fileContent = asJson ? TmjWriter(mapToExport).toTmj() : TmxWriter(mapToExport).toTmx();
    final String fileExtension = asJson ? 'json' : 'tmx';
    
    await repo.createDocumentFile(
      destinationFolderUri,
      '$mapFileName.$fileExtension',
      initialContent: fileContent,
      overwrite: true,
    );

    talker.info('Map exported successfully.');
  }

  // ---------------------------------------------------------------------------
  // Data Collection
  // ---------------------------------------------------------------------------

  Future<_ExportCollection> _collectUnifiedAssets(TiledMap map, TiledAssetResolver resolver) async {
    final uniqueAssets = <_UnifiedAssetSource>{};
    final gidToSource = <int, _UnifiedAssetSource>{};
    final spriteToSource = <String, _UnifiedAssetSource>{};

    // A. Tile Layers
    final usedGids = _findUsedGids(map);
    for (final rawGid in usedGids) {
      final cleanGid = _getCleanGid(rawGid);
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

    // B. Texture Packer Sprites (via Custom Properties)
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
                // Key by sprite name to ensure deduping across multiple objects using same sprite
                final asset = _UnifiedAssetSource(
                  sourcePath: "sprite:$spriteName", 
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

    // C. Image Layers
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

  // ---------------------------------------------------------------------------
  // Packing
  // ---------------------------------------------------------------------------

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
      
      if (source.image != null) {
        canvas.drawImageRect(source.image!, source.sourceRect, destRect, paint);
      }
      
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

  // ---------------------------------------------------------------------------
  // Remapping & Updates
  // ---------------------------------------------------------------------------

  void _remapMapGids(
    TiledMap map, 
    Map<int, int> gidRemap, 
    Map<String, int> spriteRemap,
    Map<int, ui.Rect> newGidToRect,
  ) {
    for (final layer in map.layers) {
      // 1. Update Tile Layers
      if (layer is TileLayer && layer.tileData != null) {
        for (int y = 0; y < layer.height; y++) {
          for (int x = 0; x < layer.width; x++) {
            final rawGid = layer.tileData![y][x].tile;
            final flips = layer.tileData![y][x].flips;
            
            // rawGid usually comes clean from the tiled library, check docs if issues persist.
            // Assuming library provides clean ID in .tile:
            if (rawGid != 0 && gidRemap.containsKey(rawGid)) {
              final newGid = gidRemap[rawGid]!;
              layer.tileData![y][x] = Gid(newGid, flips);
            }
          }
        }
      } 
      // 2. Update Object Layers
      else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          int? newCleanGid;
          
          // A. Standard Tile Objects
          if (object.gid != null) {
            final rawGid = object.gid!;
            final oldCleanId = _getCleanGid(rawGid);
            final flags = _getGidFlags(rawGid);

            if (gidRemap.containsKey(oldCleanId)) {
              newCleanGid = gidRemap[oldCleanId]!;
              object.gid = newCleanGid | flags;
            }
          }
          
          // B. Texture Packer Sprites
          final spriteProp = object.properties['tp_sprite'];
          if (spriteProp is StringProperty && spriteProp.value.isNotEmpty) {
            final mappedGid = spriteRemap[spriteProp.value];
            if (mappedGid != null) {
              final flags = object.gid != null ? _getGidFlags(object.gid!) : 0;
              newCleanGid = mappedGid;
              object.gid = newCleanGid | flags;
              object.properties.byName.remove('tp_sprite');
            }
          }

          // C. Update Object Dimensions to match the packed asset
          if (newCleanGid != null && newGidToRect.containsKey(newCleanGid)) {
             final rect = newGidToRect[newCleanGid]!;
             object.width = rect.width;
             object.height = rect.height;
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
        localId: i, // Local ID in the new atlas (0-based)
        // Store metadata for engine parsers
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

  // --- Helpers ---

  Future<void> _processFlowGraphDependencies(TiledMap map, TiledAssetResolver resolver, String destUri) async {
    final flowService = _ref.read(flowExportServiceProvider);
    for (final layer in map.layers) {
      if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          final prop = obj.properties['flowGraph'];
          if (prop is StringProperty && prop.value.isNotEmpty) {
            try {
              final fgKey = resolver.repo.resolveRelativePath(resolver.tmxPath, prop.value);
              final fgFile = await resolver.repo.fileHandler.resolvePath(resolver.repo.rootUri, fgKey);
              if (fgFile != null) {
                final content = await resolver.repo.readFile(fgFile.uri);
                final graph = FlowGraph.deserialize(content);
                final fgPath = resolver.repo.fileHandler.getPathForDisplay(fgFile.uri, relativeTo: resolver.repo.rootUri);
                final fgResolver = FlowGraphAssetResolver(resolver.rawAssets, resolver.repo, fgPath);
                final name = p.basenameWithoutExtension(fgFile.name);
                
                await flowService.export(
                  graph: graph, 
                  resolver: fgResolver, 
                  destinationFolderUri: destUri, 
                  fileName: name, 
                  embedSchema: true
                );
                obj.properties.byName['flowGraph'] = StringProperty(name: 'flowGraph', value: '$name.json');
              }
            } catch (_) {}
          }
        }
      }
    }
  }

  Future<void> _copyAndRelinkAssets(TiledMap map, TiledAssetResolver resolver, String destUri) async {
    final repo = resolver.repo;
    for (final tileset in map.tilesets) {
      if (tileset.image?.source != null) {
        final rawSource = tileset.image!.source!;
        final contextPath = (tileset.source != null) 
            ? repo.resolveRelativePath(resolver.tmxPath, tileset.source!) 
            : resolver.tmxPath;
        
        final canonicalKey = repo.resolveRelativePath(contextPath, rawSource);
        final file = await repo.fileHandler.resolvePath(repo.rootUri, canonicalKey);

        if (file != null) {
          await repo.copyDocumentFile(file, destUri);
          final oldImage = tileset.image!;
          tileset.image = TiledImage(source: file.name, width: oldImage.width, height: oldImage.height);
          tileset.source = null; 
        }
      }
    }
    for (final layer in map.layers) {
      if (layer is ImageLayer && layer.image.source != null) {
        final rawSource = layer.image.source!;
        final canonicalKey = repo.resolveRelativePath(resolver.tmxPath, rawSource);
        final file = await repo.fileHandler.resolvePath(repo.rootUri, canonicalKey);
        if (file != null) {
          await repo.copyDocumentFile(file, destUri);
          final oldImage = layer.image;
          layer.image = TiledImage(source: file.name, width: oldImage.width, height: oldImage.height);
        }
      }
    }
  }

  Set<int> _findUsedGids(TiledMap map) {
    final used = <int>{};
    for(final l in map.layers) {
      if (l is TileLayer && l.tileData != null) {
        for(final row in l.tileData!) for(final g in row) if(g.tile!=0) used.add(g.tile);
      }
      if (l is ObjectGroup) {
        for(final o in l.objects) if(o.gid != null) used.add(o.gid!);
      }
    }
    return used;
  }

  TexturePackerSpriteData? _findSpriteDataInAtlases(String name, Iterable<String> files, TiledAssetResolver resolver) {
    for (final path in files) {
      final key = resolver.repo.resolveRelativePath(resolver.tmxPath, path);
      final asset = resolver.getAsset(key);
      if (asset is TexturePackerAssetData) {
        if (asset.frames.containsKey(name)) return asset.frames[name];
        if (asset.animations.containsKey(name)) {
          final first = asset.animations[name]!.firstOrNull;
          if (first != null) return asset.frames[first];
        }
      }
    }
    return null;
  }

  TiledMap _deepCopyMap(TiledMap original) {
    final writer = TmxWriter(original);
    return TileMapParser.parseTmx(writer.toTmx());
  }

  int _nextPowerOfTwo(int v) {
    v--; v |= v >> 1; v |= v >> 2; v |= v >> 4; v |= v >> 8; v |= v >> 16; v++;
    return v;
  }

  String _generatePixiJson(_UnifiedPackResult result, String atlasName, List<_UnifiedAssetSource> assets) {
    final frames = <String, dynamic>{};
    for (int i = 0; i < assets.length; i++) {
      final asset = assets[i];
      final rect = result.packedRects[asset.hashCode.toString()]!;
      String name = asset.sourcePath.startsWith('sprite:') 
          ? asset.sourcePath.substring(7) 
          : 'tile_$i';
      
      frames[name] = {
        "frame": {"x": rect.left.toInt(), "y": rect.top.toInt(), "w": rect.width.toInt(), "h": rect.height.toInt()},
        "rotated": false, "trimmed": false,
        "spriteSourceSize": {"x": 0, "y": 0, "w": rect.width.toInt(), "h": rect.height.toInt()},
        "sourceSize": {"w": rect.width.toInt(), "h": rect.height.toInt()},
        "anchor": {"x": 0.5, "y": 0.5}
      };
    }
    return const JsonEncoder.withIndent('  ').convert({
      "frames": frames,
      "meta": {"app": "Machine Editor", "version": "1.0", "image": "$atlasName.png", "size": {"w": result.atlasWidth, "h": result.atlasHeight}, "scale": "1"}
    });
  }
}
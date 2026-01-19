// FILE: lib/editor/plugins/tiled_editor/tiled_export_service.dart

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

// Helper to represent a unique visual asset source for packing
class _UnifiedAssetSource {
  final String uniqueId; // gid for tiles, sprite name for sprites
  final ui.Image sourceImage;
  final Rect sourceRect;
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

// Helper to store the result of the unified packing
class _UnifiedPackResult {
  final Uint8List atlasImageBytes;
  final int atlasWidth;
  final int atlasHeight;
  final Map<String, Rect> packedRects; // Map from uniqueId to its new Rect in the atlas

  _UnifiedPackResult({
    required this.atlasImageBytes,
    required this.atlasWidth,
    required this.atlasHeight,
    required this.packedRects,
  });
}

final tiledExportServiceProvider = Provider<TiledExportService>((ref) {
  return TiledExportService(ref);
});

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

    TiledMap mapToExport = _deepCopyMap(map);

    await _processFlowGraphDependencies(mapToExport, resolver, destinationFolderUri);

    if (packInAtlas) {
      final assetsToPack = await _collectUnifiedAssets(mapToExport, resolver);

      if (assetsToPack.isNotEmpty) {
        final packResult = await _packUnifiedAtlas(assetsToPack, atlasFileName);
        _remapAndFinalizeMap(mapToExport, packResult, atlasFileName);
        
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
      } else {
        talker.info("No tiles or sprites found to pack into an atlas.");
        mapToExport.tilesets.clear();
      }
    } else {
      await _copyAndRelinkAssets(mapToExport, resolver, destinationFolderUri);
    }
    
    String fileContent = asJson ? TmjWriter(mapToExport).toTmj() : TmxWriter(mapToExport).toTmx();
    String fileExtension = asJson ? 'json' : 'tmx';
    await repo.createDocumentFile(
      destinationFolderUri,
      '$mapFileName.$fileExtension',
      initialContent: fileContent,
      overwrite: true,
    );

    talker.info('Unified export complete: $mapFileName.$fileExtension');
  }

  Future<Set<_UnifiedAssetSource>> _collectUnifiedAssets(TiledMap map, TiledAssetResolver resolver) async {
    final talker = _ref.read(talkerProvider);
    final assets = <_UnifiedAssetSource>{};

    final usedGids = _findUsedGids(map);
    for (final gid in usedGids) {
      final tile = map.tileByGid(gid);
      final tileset = map.tilesetByTileGId(gid);
      if (tile == null || tile.isEmpty) continue;
      
      final imageSource = tile.image?.source ?? tileset.image?.source;
      if (imageSource != null) {
        final image = resolver.getImage(imageSource, tileset: tileset);
        if (image != null) {
          final rect = tileset.computeDrawRect(tile);
          assets.add(_UnifiedAssetSource(
            uniqueId: 'gid_$gid',
            sourceImage: image,
            sourceRect: Rect.fromLTWH(rect.left.toDouble(), rect.top.toDouble(), rect.width.toDouble(), rect.height.toDouble()),
          ));
        }
      }
    }

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
                assets.add(_UnifiedAssetSource(
                  uniqueId: spriteName,
                  sourceImage: spriteData.sourceImage,
                  sourceRect: spriteData.sourceRect,
                ));
              } else {
                talker.warning('Could not find source for tp_sprite "$spriteName" during export.');
              }
            }
          }
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
      }
    }
    return null;
  }

  Future<_UnifiedPackResult> _packUnifiedAtlas(Set<_UnifiedAssetSource> assets, String atlasName) async {
    final items = assets.map((asset) => PackerInputItem(
      width: asset.width,
      height: asset.height,
      data: asset,
    )).toList();

    final packer = MaxRectsPacker(padding: 2);
    final packedResult = packer.pack(items);

    final potWidth = _nextPowerOfTwo(packedResult.width.toInt());
    final potHeight = _nextPowerOfTwo(packedResult.height.toInt());
    
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    final packedRects = <String, Rect>{};

    for (final item in packedResult.items) {
      final source = item.data as _UnifiedAssetSource;
      final destRect = Rect.fromLTWH(item.x, item.y, item.width, item.height);
      canvas.drawImageRect(source.sourceImage, source.sourceRect, destRect, paint);
      packedRects[source.uniqueId] = destRect;
    }

    final picture = recorder.endRecording();
    // FIX: Cast int to double
    final image = await picture.toImage(potWidth, potHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    
    return _UnifiedPackResult(
      atlasImageBytes: byteData!.buffer.asUint8List(),
      atlasWidth: potWidth,
      atlasHeight: potHeight,
      packedRects: packedRects,
    );
  }

  void _remapAndFinalizeMap(TiledMap map, _UnifiedPackResult result, String atlasName) {
    final newTiles = <Tile>[];
    final gidRemap = <int, int>{};
    final spriteRemap = <String, int>{};

    int currentLocalId = 0;
    final sortedKeys = result.packedRects.keys.toList()..sort();

    for (final uniqueId in sortedKeys) {
      final rect = result.packedRects[uniqueId]!;
      
      // FIX: Create Tile object and then set properties
      final newTile = Tile(localId: currentLocalId);
      newTile.width = rect.width.toInt();
      newTile.height = rect.height.toInt();
      newTile.x = rect.left.toInt();
      newTile.y = rect.top.toInt();
      
      newTiles.add(newTile);

      if (uniqueId.startsWith('gid_')) {
        final oldGid = int.parse(uniqueId.substring(4));
        gidRemap[oldGid] = currentLocalId + 1;
      } else {
        spriteRemap[uniqueId] = currentLocalId + 1;
      }
      currentLocalId++;
    }

    final newTileset = Tileset(
      name: atlasName,
      firstGid: 1,
      tileWidth: map.tileWidth,
      tileHeight: map.tileHeight,
      tileCount: newTiles.length,
      columns: result.atlasWidth ~/ map.tileWidth,
      image: TiledImage(source: '$atlasName.png', width: result.atlasWidth, height: result.atlasHeight),
    )..tiles = newTiles;

    map.tilesets..clear()..add(newTileset);
    
    _remapMapGids(map, gidRemap, spriteRemap);
    map.properties.byName.remove('tp_atlases');
  }

  String _generatePixiJson(_UnifiedPackResult result, String atlasName) {
    final frames = <String, dynamic>{};
    result.packedRects.forEach((uniqueId, rect) {
      if (!uniqueId.startsWith('gid_')) {
        frames[uniqueId] = {
          "frame": {"x": rect.left.toInt(), "y": rect.top.toInt(), "w": rect.width.toInt(), "h": rect.height.toInt()},
          "rotated": false, "trimmed": false,
          "spriteSourceSize": {"x": 0, "y": 0, "w": rect.width.toInt(), "h": rect.height.toInt()},
          "sourceSize": {"w": rect.width.toInt(), "h": rect.height.toInt()},
        };
      }
    });
    
    final jsonOutput = {
      "frames": frames,
      "meta": {
        "app": "Machine Editor - Unified Export",
        "version": "1.0",
        "image": "$atlasName.png",
        "size": {"w": result.atlasWidth, "h": result.atlasHeight},
        "scale": "1"
      }
    };
    return const JsonEncoder.withIndent('  ').convert(jsonOutput);
  }

  void _remapMapGids(TiledMap map, Map<int, int> gidRemap, Map<String, int> spriteRemap) {
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (int y = 0; y < layer.height; y++) {
          for (int x = 0; x < layer.width; x++) {
            final oldGid = layer.tileData![y][x];
            if (oldGid.tile != 0) {
              final newGidTile = gidRemap[oldGid.tile];
              if (newGidTile != null) {
                layer.tileData![y][x] = Gid(newGidTile, oldGid.flips);
              }
            }
          }
        }
      } else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          if (object.gid != null) {
            final newGid = gidRemap[object.gid];
            if (newGid != null) object.gid = newGid;
          }
          final spriteProp = object.properties['tp_sprite'];
          if (spriteProp is StringProperty && spriteProp.value.isNotEmpty) {
            final newGid = spriteRemap[spriteProp.value];
            if (newGid != null) {
              object.gid = newGid;
              object.properties.byName.remove('tp_sprite');
            }
          }
        }
      }
    }
  }

  int _nextPowerOfTwo(int v) {
    v--;
    v |= v >> 1; v |= v >> 2; v |= v >> 4; v |= v >> 8; v |= v >> 16;
    v++;
    return v;
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
              talker.warning('Failed to export Flow Graph ${prop.value}: $e');
            }
          }
        }
      }
    }
  }

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
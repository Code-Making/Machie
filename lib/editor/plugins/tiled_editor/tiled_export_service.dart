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

// FIXED: Added SlicingConfig to the show list
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart' show TexturePackerProject, SourceImageNode, SourceImageConfig, GridRect, PackerItemType, SourceNodeType, SpriteDefinition, PackerItemNode, PackerItemDefinition, SlicingConfig;
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
  final bool isTile;

  _UnifiedAssetSource({
    required this.uniqueId,
    required this.sourceImage,
    required this.sourceRect,
    required this.isTile,
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
  final int tileGridCols;
  final int tileGridRows;

  _UnifiedPackResult({
    required this.atlasImageBytes,
    required this.atlasWidth,
    required this.atlasHeight,
    required this.packedRects,
    this.tileGridCols = 0,
    this.tileGridRows = 0,
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

    TiledMap mapToExport = _deepCopyMap(map);
    
    _UnifiedPackResult? packResult;

    if (packInAtlas) {
      final assetsToPack = await _collectUnifiedAssets(mapToExport, resolver);

      if (assetsToPack.isNotEmpty) {
        talker.info('Collected ${assetsToPack.length} unique graphical assets to pack.');
        
        // Pass map tile size for grid calculation
        packResult = await _packUnifiedAtlas(assetsToPack, mapToExport.tileWidth, mapToExport.tileHeight);
        talker.info('Atlas packing complete. Dimensions: ${packResult.atlasWidth}x${packResult.atlasHeight}');
        
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

    await _processDependencies(
      mapToExport, 
      resolver, 
      destinationFolderUri, 
      asJson: asJson,
      packResult: packResult,
      atlasFileName: atlasFileName,
    );
    
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
    final sortedGids = usedGids.toList()..sort();

    for (final gid in sortedGids) {
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
            sourceRect: ui.Rect.fromLTWH(rect.left.toDouble(), rect.top.toDouble(), rect.width.toDouble(), rect.height.toDouble()),
            isTile: true, 
          ));
        } else {
           talker.warning('Could not find source image "$imageSource" for GID $gid.');
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
                  isTile: false, 
                ));
              } else {
                talker.warning('Could not find source for tp_sprite "$spriteName".');
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
  
  Future<_UnifiedPackResult> _packUnifiedAtlas(Set<_UnifiedAssetSource> assets, int mapTileWidth, int mapTileHeight) async {
    final tiles = assets.where((a) => a.isTile).toList();
    final sprites = assets.where((a) => !a.isTile).toList();

    // --- 1. Layout Tiles (Strict Grid) ---
    // Start with a reasonable power of 2 width
    int atlasWidth = 512;
    int atlasHeight = 512;
    
    double area = 0;
    for (var a in assets) area += a.width * a.height;
    while (atlasWidth * atlasHeight < area * 1.5) {
      if (atlasWidth <= atlasHeight) atlasWidth *= 2; else atlasHeight *= 2;
    }
    if (atlasWidth < mapTileWidth) atlasWidth = _nextPowerOfTwo(mapTileWidth);

    final packedRects = <String, ui.Rect>{};
    
    final int cols = atlasWidth ~/ mapTileWidth;
    if (cols == 0) throw Exception("Tile width larger than atlas width");
    
    final int rows = (tiles.length / cols).ceil();
    final int tileSectionHeight = rows * mapTileHeight;
    
    for (int i = 0; i < tiles.length; i++) {
      final tile = tiles[i];
      final col = i % cols;
      final row = i ~/ cols;
      
      final x = col * mapTileWidth;
      final y = row * mapTileHeight;
      
      packedRects[tile.uniqueId] = ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), tile.width.toDouble(), tile.height.toDouble());
    }

    // --- 2. Layout Sprites (Packer) ---
    // We will pack sprites into a separate coordinate space then append them below the tiles
    int spriteSectionHeight = 0;
    int finalAtlasWidth = atlasWidth;

    if (sprites.isNotEmpty) {
      final spriteItems = sprites.map((s) => PackerInputItem(
        width: s.width.toDouble(), 
        height: s.height.toDouble(), 
        data: s
      )).toList();

      // Use basic packer with just padding. It usually grows or picks a size.
      // Assuming we can't control it easily, we pack and then analyze the result.
      final packer = MaxRectsPacker(padding: 2); // FIXED: Removed width/height parameters
      final result = packer.pack(spriteItems);
      
      spriteSectionHeight = result.height.toInt();
      // Ensure the atlas is wide enough for the packed sprites too
      finalAtlasWidth = max(atlasWidth, result.width.toInt());

      for (final item in result.items) {
        final s = item.data as _UnifiedAssetSource;
        // Shift Y down by the height of the tile grid
        packedRects[s.uniqueId] = ui.Rect.fromLTWH(
          item.x, 
          item.y + tileSectionHeight, 
          item.width, 
          item.height
        );
      }
    }

    // --- 3. Finalize Dimensions ---
    int totalHeight = tileSectionHeight + spriteSectionHeight;
    int potWidth = _nextPowerOfTwo(finalAtlasWidth);
    int potHeight = _nextPowerOfTwo(totalHeight);

    // --- 4. Draw Atlas ---
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    for (final asset in assets) {
      final rect = packedRects[asset.uniqueId];
      if (rect != null) {
        canvas.drawImageRect(asset.sourceImage, asset.sourceRect, rect, paint);
      }
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
      tileGridCols: cols,
      tileGridRows: rows,
    );
  }

  void _remapAndFinalizeMap(TiledMap map, _UnifiedPackResult result, String atlasName) {
    // We only create tileset entries for actual Tiles (starting with gid_)
    final newTiles = <Tile>[];
    final gidRemap = <int, int>{}; 

    int currentLocalId = 0;
    
    final sortedGidKeys = result.packedRects.keys
        .where((k) => k.startsWith('gid_'))
        .toList()
        ..sort((a, b) {
           final rA = result.packedRects[a]!;
           final rB = result.packedRects[b]!;
           // Sort strictly top-to-bottom, then left-to-right (Raster scan order)
           // to align with the Tileset grid assumption
           final rowA = rA.top;
           final rowB = rB.top;
           if ((rowA - rowB).abs() > 0.1) return rowA.compareTo(rowB);
           return rA.left.compareTo(rB.left);
        });

    for (final uniqueId in sortedGidKeys) {
      final rect = result.packedRects[uniqueId]!;
      
      // Calculate local ID based on the atlas grid we established
      final col = (rect.left / map.tileWidth).round();
      final row = (rect.top / map.tileHeight).round();
      final targetLocalId = row * result.tileGridCols + col;
      
      // Fill gaps if any (though loop should be dense based on previous packing)
      while (currentLocalId < targetLocalId) {
        newTiles.add(Tile(localId: currentLocalId)); 
        currentLocalId++;
      }

      final newTile = Tile(
        localId: currentLocalId,
        properties: CustomProperties({'sourceRect': StringProperty(name: 'sourceRect', value: '${rect.left},${rect.top},${rect.width},${rect.height}')}),
      );
      newTiles.add(newTile);

      final oldGid = int.parse(uniqueId.substring(4));
      gidRemap[oldGid] = currentLocalId + 1;
      
      currentLocalId++;
    }

    final newTileset = Tileset(
      name: atlasName,
      firstGid: 1,
      tileWidth: map.tileWidth, 
      tileHeight: map.tileHeight,
      // Tile count only needs to cover the Grid section
      tileCount: currentLocalId, 
      columns: result.tileGridCols,
      image: TiledImage(source: '$atlasName.png', width: result.atlasWidth, height: result.atlasHeight),
    )..tiles = newTiles;

    map.tilesets..clear()..add(newTileset);
    
    _remapMapGids(map, gidRemap);

    map.properties.byName.remove('tp_atlases');
  }

  void _remapMapGids(TiledMap map, Map<int, int> gidRemap) {
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (int y = 0; y < layer.height; y++) {
          for (int x = 0; x < layer.width; x++) {
            final oldGid = layer.tileData![y][x];
            if (oldGid.tile != 0) {
              final newGidTile = gidRemap[oldGid.tile];
              if (newGidTile != null) {
                layer.tileData![y][x] = Gid(newGidTile, oldGid.flips);
              } else {
                layer.tileData![y][x] = Gid(0, oldGid.flips);
              }
            }
          }
        }
      } 
      else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          if (object.gid != null) {
            final newGid = gidRemap[object.gid];
            if (newGid != null) {
              object.gid = newGid;
            }
          }
        }
      }
    }
  }

  String _generatePixiJson(_UnifiedPackResult result, String atlasName) {
    final frames = <String, dynamic>{};
    for (final entry in result.packedRects.entries) {
      final uniqueId = entry.key;
      final rect = entry.value;
      
      if (!uniqueId.startsWith('gid_')) {
        frames[uniqueId] = {
          "frame": {"x": rect.left.toInt(), "y": rect.top.toInt(), "w": rect.width.toInt(), "h": rect.height.toInt()},
          "rotated": false, "trimmed": false,
          "spriteSourceSize": {"x": 0, "y": 0, "w": rect.width.toInt(), "h": rect.height.toInt()},
          "sourceSize": {"w": rect.width.toInt(), "h": rect.height.toInt()},
        };
      }
    }
    
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

  int _nextPowerOfTwo(int v) {
    v--; v |= v >> 1; v |= v >> 2; v |= v >> 4; v |= v >> 8; v |= v >> 16; v++;
    return v;
  }

  Future<void> _processDependencies(
    TiledMap mapToExport, 
    TiledAssetResolver resolver, 
    String destinationFolderUri,
    {
      required bool asJson,
      _UnifiedPackResult? packResult,
      String? atlasFileName,
    }
  ) async {
    final talker = _ref.read(talkerProvider);
    final repo = resolver.repo;
    final flowService = _ref.read(flowExportServiceProvider);

    // 1. Process FlowGraphs
    for (final layer in mapToExport.layers) {
      if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          final prop = obj.properties['flowGraph'];
          if (prop is StringProperty && prop.value.isNotEmpty) {
            try {
              final fgCanonicalKey = repo.resolveRelativePath(resolver.tmxPath, prop.value);
              final fgFile = await repo.fileHandler.resolvePath(repo.rootUri, fgCanonicalKey);
              if (fgFile == null) continue;

              final exportName = p.basenameWithoutExtension(fgFile.name);

              if (asJson) {
                final content = await repo.readFile(fgFile.uri);
                final graph = FlowGraph.deserialize(content);
                final fgPath = repo.fileHandler.getPathForDisplay(fgFile.uri, relativeTo: repo.rootUri);
                final fgResolver = FlowGraphAssetResolver(resolver.rawAssets, repo, fgPath);

                await flowService.export(
                  graph: graph,
                  resolver: fgResolver,
                  destinationFolderUri: destinationFolderUri,
                  fileName: exportName,
                  embedSchema: true,
                );
                obj.properties.byName['flowGraph'] = StringProperty(name: 'flowGraph', value: '$exportName.json');
              } else {
                await repo.copyDocumentFile(fgFile, destinationFolderUri);
                obj.properties.byName['flowGraph'] = StringProperty(name: 'flowGraph', value: '$exportName.fg');
              }
            } catch (e) {
              talker.warning('Failed to process Flow Graph dependency "${prop.value}": $e');
            }
          }
        }
      }
    }

    // 2. Process .tpacker files if NOT exported as JSON
    // REPACK Logic: Even when exporting TMX, we want the sprites to point to the new unified atlas.
    // So we copy the .tpacker file but modify it to reference the new atlas image and new rects.
    if (!asJson && packResult != null && atlasFileName != null) {
      final tpAtlasesProp = mapToExport.properties['tp_atlases'];
      if (tpAtlasesProp is StringProperty && tpAtlasesProp.value.isNotEmpty) {
        final rawPaths = tpAtlasesProp.value.split(',').map((e) => e.trim());
        final newPaths = <String>[];

        for (final path in rawPaths) {
          try {
            final canonicalKey = repo.resolveRelativePath(resolver.tmxPath, path);
            final tpackerFile = await repo.fileHandler.resolvePath(repo.rootUri, canonicalKey);
            if (tpackerFile != null) {
              
              // Load original
              final content = await repo.readFile(tpackerFile.uri);
              final project = TexturePackerProject.fromJson(jsonDecode(content));
              
              // Repack data
              final repackedProject = _repackTpackerProject(project, packResult, atlasFileName);
              
              // Save
              final newFileName = tpackerFile.name;
              await repo.createDocumentFile(
                destinationFolderUri, 
                newFileName, 
                initialContent: const JsonEncoder.withIndent('  ').convert(repackedProject.toJson()),
                overwrite: true
              );
              
              newPaths.add(newFileName);
            }
          } catch (e) {
            talker.warning('Failed to repack .tpacker dependency "$path": $e');
          }
        }
        mapToExport.properties.byName['tp_atlases'] = StringProperty(name: 'tp_atlases', value: newPaths.join(','));
      }
    } else if (asJson) {
      mapToExport.properties.byName.remove('tp_atlases');
    }
  }

  TexturePackerProject _repackTpackerProject(
    TexturePackerProject original, 
    _UnifiedPackResult packResult, 
    String atlasFileName
  ) {
    final atlasSourceId = 'atlas_source';
    // Create new Source Root pointing to the generated atlas PNG
    final newSourceRoot = SourceImageNode(
      id: 'root',
      name: 'root',
      type: SourceNodeType.folder,
      children: [
        SourceImageNode(
          id: atlasSourceId,
          name: '$atlasFileName.png',
          type: SourceNodeType.image,
          // FIXED: Used SlicingConfig directly
          content: const SourceImageConfig(
            path: '', 
            slicing: SlicingConfig(tileWidth: 1, tileHeight: 1, margin: 0, padding: 0),
          )
        )
      ]
    );

    final newDefinitions = <String, PackerItemDefinition>{};
    
    original.definitions.forEach((nodeId, def) {
      if (def is SpriteDefinition) {
        final nodeName = _findNodeName(original.tree, nodeId);
        // Look up using the uniqueId (sprite name)
        if (nodeName != null && packResult.packedRects.containsKey(nodeName)) {
          final rect = packResult.packedRects[nodeName]!;
          newDefinitions[nodeId] = SpriteDefinition(
            sourceImageId: atlasSourceId,
            gridRect: GridRect(
              x: rect.left.toInt(),
              y: rect.top.toInt(),
              width: rect.width.toInt(),
              height: rect.height.toInt(),
            ),
          );
        }
      } else {
        newDefinitions[nodeId] = def;
      }
    });

    return original.copyWith(
      sourceImagesRoot: newSourceRoot,
      definitions: newDefinitions,
    );
  }

  String? _findNodeName(PackerItemNode node, String id) {
    if (node.id == id) return node.name;
    for (final child in node.children) {
      final res = _findNodeName(child, id);
      if (res != null) return res;
    }
    return null;
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
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

import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart' show TexturePackerProject, SourceImageNode, SourceImageConfig, GridRect, PackerItemType, SourceNodeType, SpriteDefinition, PackerItemNode, PackerItemDefinition;
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
  // Metadata to help reconstruction
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
    
    // We store packResult here so dependencies can use it to update their refs
    _UnifiedPackResult? packResult;

    if (packInAtlas) {
      final assetsToPack = await _collectUnifiedAssets(mapToExport, resolver);

      if (assetsToPack.isNotEmpty) {
        talker.info('Collected ${assetsToPack.length} unique graphical assets to pack.');
        
        packResult = await _packUnifiedAtlas(assetsToPack, mapToExport.tileWidth, mapToExport.tileHeight);
        talker.info('Atlas packing complete. Dimensions: ${packResult.atlasWidth}x${packResult.atlasHeight}');
        
        // Remap map data to use the new atlas
        _remapAndFinalizeMap(mapToExport, packResult, atlasFileName);
        
        // Write Atlas Image
        await repo.createDocumentFile(
          destinationFolderUri,
          '$atlasFileName.png',
          initialBytes: packResult.atlasImageBytes,
          overwrite: true,
        );
        // Write Atlas JSON (Metadata)
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

    // Process Dependencies (.fg, .tpacker)
    // Pass the packResult so .tpacker files can be rewritten to point to the new atlas
    await _processDependencies(
      mapToExport, 
      resolver, 
      destinationFolderUri, 
      asJson: asJson,
      packResult: packResult,
      atlasFileName: atlasFileName,
    );
    
    // Write Final Map File
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
    // Sort GIDs to ensure deterministic order which is important for the grid layout
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
    
    // Also scan .tpacker files for *all* sprites if we want the output .tpacker to be complete?
    // For now, we only pack what is used in the map to optimize texture space.
    // The rewritten .tpacker will only contain definitions for sprites present in the atlas.

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

    // 1. Calculate Grid Layout for Tiles
    // We attempt to make the grid roughly square or fit standard texture sizes
    int potWidth = 512;
    int potHeight = 512;
    
    // Estimate area needed
    double area = 0;
    for (var a in assets) area += a.width * a.height;
    
    // Find approximate square POT
    while (potWidth * potHeight < area * 1.5) { // 1.5 factor for packing inefficiency
      if (potWidth <= potHeight) potWidth *= 2; else potHeight *= 2;
    }
    if (potWidth < mapTileWidth) potWidth = _nextPowerOfTwo(mapTileWidth);

    // Layout Tiles in strict grid at top
    final packedRects = <String, ui.Rect>{};
    
    final int cols = potWidth ~/ mapTileWidth;
    if (cols == 0) throw Exception("Tile width larger than atlas width");
    
    final int rows = (tiles.length / cols).ceil();
    final int tileSectionHeight = rows * mapTileHeight;
    
    // Ensure height accommodates tiles
    while (tileSectionHeight > potHeight) {
      potHeight *= 2;
    }

    for (int i = 0; i < tiles.length; i++) {
      final tile = tiles[i];
      final col = i % cols;
      final row = i ~/ cols;
      
      final x = col * mapTileWidth;
      final y = row * mapTileHeight;
      
      // If original tile is smaller than grid cell, center it or align top-left?
      // Tiled usually aligns bottom-left or simply renders the image.
      // We will draw it at (x,y). Note: if tile source is larger than mapTileWidth, it might bleed.
      // Assuming tiles match mapTileWidth/Height roughly.
      
      packedRects[tile.uniqueId] = ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), tile.width.toDouble(), tile.height.toDouble());
    }

    // 2. Pack Sprites in remaining space
    if (sprites.isNotEmpty) {
      // Available space is below the tile grid
      final spriteItems = sprites.map((s) => PackerInputItem(
        width: s.width.toDouble(), 
        height: s.height.toDouble(), 
        data: s
      )).toList();

      // We need a packer that can handle 'growing' or simply fitting into available rects.
      // MaxRectsPacker implementation usually takes fixed width/height.
      // We will try to pack into (potWidth x (potHeight - tileSectionHeight)).
      // If it fails, we double height and try again.
      
      while (true) {
        final availableHeight = potHeight - tileSectionHeight;
        if (availableHeight > 0) {
          final packer = MaxRectsPacker(width: potWidth.toDouble(), height: availableHeight.toDouble(), padding: 2);
          try {
            final result = packer.pack(spriteItems);
            // Apply offset
            for (final item in result.items) {
              final s = item.data as _UnifiedAssetSource;
              packedRects[s.uniqueId] = ui.Rect.fromLTWH(item.x, item.y + tileSectionHeight, item.width, item.height);
            }
            break; // Success
          } catch (e) {
            // Packing failed, grow
            potHeight *= 2;
          }
        } else {
          potHeight *= 2;
        }
        
        if (potHeight > 8192) throw Exception("Texture Atlas exceeded 8192px height.");
      }
    }

    // 3. Draw Atlas
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
    // 1. Create Tile entries for the GRID section (Tiles)
    // We only create tileset entries for the items that were packed into the grid.
    // The sprites (isTile=false) are accessed via sprite objects and don't need GIDs in the tileset 
    // because they are now effectively distinct objects or will be looked up via JSON.
    // However, if we want them visible in Tiled (if TMX is opened), they need GIDs.
    // BUT the prompt says "A sprite... doesn't need to be mapped as gid".
    // So we ONLY map the 'gid_' assets to the tileset.

    final newTiles = <Tile>[];
    final gidRemap = <int, int>{}; 

    int currentLocalId = 0;
    
    // Iterate through GID assets based on the packed grid order
    final sortedGidKeys = result.packedRects.keys
        .where((k) => k.startsWith('gid_'))
        .toList()
        ..sort((a, b) {
           // Sort by packed position (row major) to ensure GIDs match the visual grid
           final rA = result.packedRects[a]!;
           final rB = result.packedRects[b]!;
           final rowA = rA.top;
           final rowB = rB.top;
           if (rowA != rowB) return rowA.compareTo(rowB);
           return rA.left.compareTo(rB.left);
        });

    for (final uniqueId in sortedGidKeys) {
      final rect = result.packedRects[uniqueId]!;
      
      // Calculate local ID based on grid position
      // x = col * width -> col = x / width
      final col = (rect.left / map.tileWidth).round();
      final row = (rect.top / map.tileHeight).round();
      final targetLocalId = row * result.tileGridCols + col;
      
      // Fill gaps if necessary (though our packing logic shouldn't leave gaps in ID sequence)
      while (currentLocalId < targetLocalId) {
        newTiles.add(Tile(localId: currentLocalId)); // Empty tile
        currentLocalId++;
      }

      final newTile = Tile(
        localId: currentLocalId,
        // We store source rect for reference
        properties: CustomProperties({'sourceRect': StringProperty(name: 'sourceRect', value: '${rect.left},${rect.top},${rect.width},${rect.height}')}),
      );
      newTiles.add(newTile);

      final oldGid = int.parse(uniqueId.substring(4));
      gidRemap[oldGid] = currentLocalId + 1; // +1 for firstGid
      
      currentLocalId++;
    }

    // Create the unified Tileset
    final newTileset = Tileset(
      name: atlasName,
      firstGid: 1,
      tileWidth: map.tileWidth, 
      tileHeight: map.tileHeight,
      tileCount: currentLocalId, // Count covers up to the last used grid cell
      columns: result.tileGridCols,
      image: TiledImage(source: '$atlasName.png', width: result.atlasWidth, height: result.atlasHeight),
    )..tiles = newTiles;

    map.tilesets..clear()..add(newTileset);
    
    _remapMapGids(map, gidRemap);

    // Clean up
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
          // Sprites (tp_sprite) are ignored here, they don't get GIDs
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
    // We need to repack them to point to the new atlas
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
              
              // Load the original .tpacker
              final content = await repo.readFile(tpackerFile.uri);
              final project = TexturePackerProject.fromJson(jsonDecode(content));
              
              // Create REPACKED project
              final repackedProject = _repackTpackerProject(project, packResult, atlasFileName);
              
              // Save to destination
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

  /// Updates a TexturePackerProject to point to the newly generated atlas.
  TexturePackerProject _repackTpackerProject(
    TexturePackerProject original, 
    _UnifiedPackResult packResult, 
    String atlasFileName
  ) {
    // 1. Create a new SourceImageNode for the atlas
    final atlasSourceId = 'atlas_source';
    final newSourceRoot = SourceImageNode(
      id: 'root',
      name: 'root',
      type: SourceNodeType.folder,
      children: [
        SourceImageNode(
          id: atlasSourceId,
          name: '$atlasFileName.png',
          type: SourceNodeType.image,
          content: const SourceImageConfig(
            path: '', // Relative path to same folder effectively, or handled by name
            slicing: const TexturePackerProjectSlicingConfig(tileWidth: 1, tileHeight: 1, margin: 0, padding: 0),
          )
        )
      ]
    );

    // 2. Update definitions
    final newDefinitions = <String, PackerItemDefinition>{};
    
    // We only keep definitions for sprites that are in the pack result
    original.definitions.forEach((nodeId, def) {
      if (def is SpriteDefinition) {
        // Find this sprite in the packed result.
        // We need to know the 'name' associated with this nodeId to look it up in packResult.
        // BUT _UnifiedPackResult keys are the *names* (uniqueIds) passed in.
        // We need to find the name of the node in the original tree.
        final nodeName = _findNodeName(original.tree, nodeId);
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
        // Keep animations, folders, etc.
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

// Temporary alias to fix type error if SlicingConfig name differs in models.
// Assuming TexturePackerProjectSlicingConfig is SlicingConfig in your project.
typedef TexturePackerProjectSlicingConfig = SlicingConfig;
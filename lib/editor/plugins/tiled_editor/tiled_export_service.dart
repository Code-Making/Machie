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

import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
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

  int _getCleanGid(int gid) => gid & _gidMask;
  int _getGidFlags(int gid) => gid & _flagMask;

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

    TiledMap mapToExport = _deepCopyMap(map);

    await _processFlowGraphDependencies(mapToExport, resolver, destinationFolderUri);

    if (packInAtlas) {
      final assetsToPack = await _collectUnifiedAssets(mapToExport, resolver);

      if (assetsToPack.isNotEmpty) {
        talker.info('Collected ${assetsToPack.length} unique graphical assets to pack.');
        
        final packResult = await _packUnifiedAtlasGrid(assetsToPack, map.tileWidth, map.tileHeight);
        talker.info('Atlas packing complete. Size: ${packResult.atlasWidth}x${packResult.atlasHeight}, Cols: ${packResult.columns}');
        
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

        // Process linked .tpacker files
        await _processTexturePackerDependencies(mapToExport, resolver, packResult, atlasFileName, destinationFolderUri);

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
      await _copyAndRelinkAssets(mapToExport, resolver, destinationFolderUri);
    }
    
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
  
  Future<_UnifiedPackResult> _packUnifiedAtlasGrid(Set<_UnifiedAssetSource> assets, int tileWidth, int tileHeight) async {
    final sortedAssets = assets.toList()..sort((a, b) {
       if (a.height != b.height) return b.height.compareTo(a.height);
       if (a.width != b.width) return b.width.compareTo(a.width);
       return a.uniqueId.compareTo(b.uniqueId);
    });

    double totalArea = 0;
    for(var a in sortedAssets) totalArea += (a.width * a.height);
    
    int potSize = _nextPowerOfTwo(sqrt(totalArea).ceil());
    if (potSize < 256) potSize = 256;
    
    int maxAssetWidth = sortedAssets.isEmpty ? 0 : sortedAssets.map((e) => e.width).reduce(max);
    if (potSize < maxAssetWidth) potSize = _nextPowerOfTwo(maxAssetWidth);

    int columns = potSize ~/ tileWidth;
    if (columns < 1) {
      potSize = _nextPowerOfTwo(tileWidth * sortedAssets.length);
      columns = potSize ~/ tileWidth;
    }

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
      
      while (!placed) {
        ensureRows(r + hCells); 
        for (int c = 0; c <= columns - wCells; c++) {
          if (checkFit(c, r, wCells, hCells)) {
            markOccupied(c, r, wCells, hCells);
            
            final px = (c * tileWidth).toDouble();
            final py = (r * tileHeight).toDouble();
            
            packedRects[asset.uniqueId] = ui.Rect.fromLTWH(px, py, asset.width.toDouble(), asset.height.toDouble());
            
            idToGid[asset.uniqueId] = (r * columns) + c + 1;
            
            placed = true;
            break;
          }
        }
        if (!placed) r++;
      }
    }

    int totalRows = grid.length;
    int neededHeight = totalRows * tileHeight;
    int potHeight = _nextPowerOfTwo(neededHeight);

    while (potHeight > potSize * 2) {
      potSize *= 2;
      columns = potSize ~/ tileWidth;
      rows = (sortedAssets.length / columns).ceil();
      neededHeight = rows * tileHeight;
      potHeight = _nextPowerOfTwo(neededHeight);
    }

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
    final newTiles = <Tile>[];
    
    final sortedKeys = result.idToGid.keys.toList()..sort();

    for (final uniqueId in sortedKeys) {
        final newGid = result.idToGid[uniqueId]!;
        final localId = newGid - 1;

        newTiles.add(Tile(
            localId: localId,
            properties: CustomProperties({
                'atlas_id': StringProperty(name: 'atlas_id', value: uniqueId),
            }),
        ));
    }
    newTiles.sort((a, b) => a.localId.compareTo(b.localId));
    
    final oldTilesets = List<Tileset>.from(map.tilesets);

    int safeColumns = 1;
    if (map.tileWidth > 0) {
      safeColumns = max(1, result.atlasWidth ~/ map.tileWidth);
    }

    final newTileset = Tileset(
      name: atlasName,
      firstGid: 1,
      tileWidth: map.tileWidth,
      tileHeight: map.tileHeight,
      tileCount: result.columns * (result.atlasHeight ~/ map.tileHeight),
      columns: safeColumns,
      image: TiledImage(source: '$atlasName.png', width: result.atlasWidth, height: result.atlasHeight),
    )..tiles = newTiles;

    _performSafeRemap(map, oldTilesets, result.idToGid, result.packedRects);

    map.tilesets..clear()..add(newTileset);
  }

  void _performSafeRemap(
    TiledMap map, 
    List<Tileset> oldTilesets, 
    Map<String, int> keyToNewGid,
    Map<String, ui.Rect> keyToRect,
  ) {
    Tileset? findTileset(int gid) {
      for (var i = oldTilesets.length - 1; i >= 0; i--) {
        if (oldTilesets[i].firstGid != null && oldTilesets[i].firstGid! <= gid) {
          return oldTilesets[i];
        }
      }
      return null;
    }

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
                layer.tileData![y][x] = Gid.fromInt(0);
              }
            }
          }
        }
      } 
      else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
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

  Future<void> _processTexturePackerDependencies(TiledMap map, TiledAssetResolver resolver, _UnifiedPackResult packResult, String atlasName, String destinationFolderUri) async {
      final talker = _ref.read(talkerProvider);
      final repo = resolver.repo;
      final tpAtlasesProp = map.properties['tp_atlases'];
      if (tpAtlasesProp is! StringProperty || tpAtlasesProp.value.isEmpty) {
        return;
      }

      final originalTpackerPaths = tpAtlasesProp.value.split(',').map((e) => e.trim()).toList();
      final newTpackerFileNames = <String>[];

      for(final path in originalTpackerPaths) {
          try {
              final canonicalKey = repo.resolveRelativePath(resolver.tmxPath, path);
              final file = await repo.fileHandler.resolvePath(repo.rootUri, canonicalKey);
              if (file == null) {
                  talker.warning('Could not find linked .tpacker file: $path');
                  continue;
              }

              final content = await repo.readFile(file.uri);
              final originalProject = TexturePackerProject.fromJson(jsonDecode(content));

              final newSourceImage = SourceImageNode(
                  id: 'unified_atlas',
                  name: atlasName,
                  type: SourceNodeType.image,
                  content: SourceImageConfig(
                      path: '$atlasName.png',
                      slicing: const SlicingConfig(tileWidth: 1, tileHeight: 1, margin: 0, padding: 0),
                  ),
              );

              final newDefinitions = <String, PackerItemDefinition>{};
              originalProject.definitions.forEach((nodeId, def) {
                  if (def is SpriteDefinition) {
                      final node = _findNodeInTree(originalProject.tree, nodeId);
                      if (node != null) {
                          final key = 'sprite_${node.name}';
                          final rect = packResult.packedRects[key];
                          if (rect != null) {
                              newDefinitions[nodeId] = SpriteDefinition(
                                  sourceImageId: newSourceImage.id, 
                                  gridRect: GridRect(x: rect.left.toInt(), y: rect.top.toInt(), width: rect.width.toInt(), height: rect.height.toInt()),
                              );
                          }
                      }
                  } else {
                      newDefinitions[nodeId] = def;
                  }
              });

              final newProject = TexturePackerProject(
                  sourceImagesRoot: SourceImageNode(
                      id: 'root',
                      name: 'root',
                      type: SourceNodeType.folder,
                      children: [newSourceImage],
                  ), 
                  tree: originalProject.tree, // Keep hierarchy
                  definitions: newDefinitions,
              );
              
              final newFileName = 'export_${p.basename(path)}';
              newTpackerFileNames.add(newFileName);
              
              await repo.createDocumentFile(
                  destinationFolderUri, 
                  newFileName,
                  initialContent: jsonEncode(newProject.toJson()),
                  overwrite: true,
              );

          } catch (e, st) {
              talker.handle(e, st, 'Failed to process .tpacker dependency: $path');
          }
      }

      // Update map property to point to new tpacker files
      map.properties.byName['tp_atlases'] = StringProperty(
          name: 'tp_atlases',
          value: newTpackerFileNames.join(','),
      );
  }
  
  PackerItemNode? _findNodeInTree(PackerItemNode node, String id) {
      if (node.id == id) return node;
      for (final child in node.children) {
          final found = _findNodeInTree(child, id);
          if (found != null) return found;
      }
      return null;
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

  TiledMap _deepCopyMap(TiledMap original) {
    final writer = TmxWriter(original);
    final tmxString = writer.toTmx();
    return TileMapParser.parseTmx(tmxString);
  }
}
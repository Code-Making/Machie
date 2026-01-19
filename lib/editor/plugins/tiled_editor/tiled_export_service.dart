// lib/editor/plugins/tiled_editor/tiled_export_service.dart

import 'dart.async';
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

// FIX 1: Added SourceImageNode and SourceNodeType to the import's show clause.
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart' show TexturePackerProject, SourceImageNode, SourceNodeType;
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

    // Process dependencies based on export format BEFORE asset packing/copying.
    await _processFlowGraphDependencies(mapToExport, resolver, destinationFolderUri, asJson: asJson);
    
    if (packInAtlas) {
      final assetsToPack = await _collectUnifiedAssets(mapToExport, resolver);

      if (assetsToPack.isNotEmpty) {
        talker.info('Collected ${assetsToPack.length} unique graphical assets to pack.');
        
        final packResult = await _packUnifiedAtlas(assetsToPack, atlasFileName);
        talker.info('Atlas packing complete. Final dimensions: ${packResult.atlasWidth}x${packResult.atlasHeight}');
        
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
      // If not packing, copy all dependencies and relink paths.
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
            sourceRect: ui.Rect.fromLTWH(rect.left.toDouble(), rect.top.toDouble(), rect.width.toDouble(), rect.height.toDouble()),
          ));
        } else {
           talker.warning('Could not find source image "$imageSource" for GID $gid during export.');
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

    for(final layer in map.layers) {
      if (layer is ImageLayer && layer.image.source != null) {
        final image = resolver.getImage(layer.image.source);
        if (image != null) {
          assets.add(_UnifiedAssetSource(
            uniqueId: 'image_layer_${layer.id}_${layer.image.source}',
            sourceImage: image,
            sourceRect: ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble())
          ));
        } else {
          talker.warning('Could not find source image "${layer.image.source}" for Image Layer "${layer.name}" during export.');
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

  void _remapAndFinalizeMap(TiledMap map, _UnifiedPackResult result, String atlasName) {
    final newTiles = <Tile>[];
    final gidRemap = <int, int>{};
    
    int currentLocalId = 0;
    final sortedKeys = result.packedRects.keys.toList()..sort();

    for (final uniqueId in sortedKeys) {
      if (uniqueId.startsWith('gid_')) {
        final rect = result.packedRects[uniqueId]!;
        final newTile = Tile(
          localId: currentLocalId,
          properties: CustomProperties({'sourceRect': StringProperty(name: 'sourceRect', value: '${rect.left},${rect.top},${rect.width},${rect.height}')}),
        );
        newTiles.add(newTile);

        final oldGid = int.parse(uniqueId.substring(4));
        gidRemap[oldGid] = currentLocalId + 1;
        currentLocalId++;
      }
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
    
    _remapMapGids(map, gidRemap);
    
    final prop = map.properties['tp_atlases'];
    if (prop is StringProperty) {
        final newAtlasName = '$atlasName.json';
        map.properties.byName['tp_atlases'] = StringProperty(name: 'tp_atlases', value: newAtlasName);
    }
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
              }
            }
          }
        }
      } 
      else if (layer is ObjectGroup) {
        for (final object in layer.objects) {
          if (object.gid != null) {
            final newGid = gidRemap[object.gid];
            if (newGid != null) object.gid = newGid;
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
      frames[uniqueId] = {
        "frame": {"x": rect.left.toInt(), "y": rect.top.toInt(), "w": rect.width.toInt(), "h": rect.height.toInt()},
        "rotated": false, "trimmed": false,
        "spriteSourceSize": {"x": 0, "y": 0, "w": rect.width.toInt(), "h": rect.height.toInt()},
        "sourceSize": {"w": rect.width.toInt(), "h": rect.height.toInt()},
      };
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
  
  Future<void> _processFlowGraphDependencies(TiledMap mapToExport, TiledAssetResolver resolver, String destinationFolderUri, {bool asJson = false}) async {
    final talker = _ref.read(talkerProvider);
    final repo = resolver.repo;
    
    for (final layer in mapToExport.layers) {
      if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          final prop = obj.properties['flowGraph'];
          if (prop is StringProperty && prop.value.isNotEmpty) {
            if (asJson) {
              try {
                final fgCanonicalKey = repo.resolveRelativePath(resolver.tmxPath, prop.value);
                final fgFile = await repo.fileHandler.resolvePath(repo.rootUri, fgCanonicalKey);
                if (fgFile == null) continue;
                
                final content = await repo.readFile(fgFile.uri);
                final graph = FlowGraph.deserialize(content);
                final fgPath = repo.fileHandler.getPathForDisplay(fgFile.uri, relativeTo: repo.rootUri);
                final fgResolver = FlowGraphAssetResolver(resolver.rawAssets, repo, fgPath);
                final exportName = p.basenameWithoutExtension(fgFile.name);

                await _ref.read(flowExportServiceProvider).export(
                  graph: graph, resolver: fgResolver, destinationFolderUri: destinationFolderUri,
                  fileName: exportName, embedSchema: true,
                );
                obj.properties.byName['flowGraph'] = StringProperty(name: 'flowGraph', value: '$exportName.json');
              } catch (e) {
                talker.warning('Failed to export Flow Graph dependency "${prop.value}": $e');
              }
            } else {
              obj.properties.byName['flowGraph'] = StringProperty(name: 'flowGraph', value: p.basename(prop.value));
            }
          }
        }
      }
    }
  }

  // FIX 2: REWRITTEN to use object reconstruction instead of assigning to final fields.
  Future<void> _copyAndRelinkAssets(TiledMap mapToExport, TiledAssetResolver resolver, String destinationFolderUri) async {
    final repo = resolver.repo;
    final talker = _ref.read(talkerProvider);
    final allDependencies = <String>{};

    for (final tileset in mapToExport.tilesets) {
      if (tileset.source != null) allDependencies.add(repo.resolveRelativePath(resolver.tmxPath, tileset.source!));
      if (tileset.image?.source != null) {
        final contextPath = tileset.source != null ? repo.resolveRelativePath(resolver.tmxPath, tileset.source!) : resolver.tmxPath;
        allDependencies.add(repo.resolveRelativePath(contextPath, tileset.image!.source!));
      }
    }
    for (final layer in mapToExport.layers) {
      if (layer is ImageLayer && layer.image.source != null) allDependencies.add(repo.resolveRelativePath(resolver.tmxPath, layer.image.source!));
      if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          final fgProp = obj.properties['flowGraph'];
          if (fgProp is StringProperty && fgProp.value.isNotEmpty) allDependencies.add(repo.resolveRelativePath(resolver.tmxPath, fgProp.value));
        }
      }
    }
    final tpProp = mapToExport.properties['tp_atlases'];
    if (tpProp is StringProperty && tpProp.value.isNotEmpty) {
      tpProp.value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty)
          .forEach((path) => allDependencies.add(repo.resolveRelativePath(resolver.tmxPath, path)));
    }

    final indirectDependencies = <String>{};
    for (final depPath in allDependencies) {
      if (depPath.toLowerCase().endsWith('.tpacker')) {
        try {
          final file = await repo.fileHandler.resolvePath(repo.rootUri, depPath);
          if (file == null) continue;
          final content = await repo.readFile(file.uri);
          final tpackerProject = TexturePackerProject.fromJson(jsonDecode(content));
          
          void collectImagePaths(SourceImageNode node) {
            if (node.type == SourceNodeType.image && node.content != null && node.content!.path.isNotEmpty) {
              indirectDependencies.add(repo.resolveRelativePath(depPath, node.content!.path));
            }
            node.children.forEach(collectImagePaths);
          }
          collectImagePaths(tpackerProject.sourceImagesRoot);
        } catch(e) {
          talker.warning('Could not parse .tpacker to find indirect dependencies: $depPath');
        }
      }
    }
    allDependencies.addAll(indirectDependencies);

    for (final path in allDependencies) {
      try {
        final file = await repo.fileHandler.resolvePath(repo.rootUri, path);
        if (file != null) await repo.copyDocumentFile(file, destinationFolderUri);
      } catch (e) {
        talker.warning('Failed to copy dependency "$path" to destination.');
      }
    }

    final newTilesets = <Tileset>[];
    for(final ts in mapToExport.tilesets) {
        newTilesets.add(
            Tileset(
                name: ts.name,
                class_: ts.class_,
                firstGid: ts.firstGid,
                tileWidth: ts.tileWidth,
                tileHeight: ts.tileHeight,
                spacing: ts.spacing,
                margin: ts.margin,
                tileCount: ts.tileCount,
                columns: ts.columns,
                objectAlignment: ts.objectAlignment,
                tileRenderSize: ts.tileRenderSize,
                fillMode: ts.fillMode,
                // Make path relative by taking basename and set source to null to embed.
                source: null,
                image: ts.image == null ? null : TiledImage(source: p.basename(ts.image!.source!), width: ts.image!.width, height: ts.image!.height),
                properties: ts.properties,
                tiles: ts.tiles,
                wangSets: ts.wangSets
            )
        );
    }
    mapToExport.tilesets..clear()..addAll(newTilesets);


    for(final layer in mapToExport.layers) {
        if (layer is ImageLayer && layer.image.source != null) {
            final oldImage = layer.image;
            layer.image = TiledImage(source: p.basename(oldImage.source!), width: oldImage.width, height: oldImage.height);
        }
    }
    
    final newTpAtlasPaths = (mapToExport.properties['tp_atlases'] as StringProperty?)?.value
      .split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).map((path) => p.basename(path)).join(', ') ?? '';
    if (newTpAtlasPaths.isNotEmpty) mapToExport.properties.byName['tp_atlases'] = StringProperty(name: 'tp_atlases', value: newTpAtlasPaths);
    
    await _relinkTpackerDependencies(allDependencies, repo, destinationFolderUri);
  }

  // FIX 3: REWRITTEN to use a recursive copyWith pattern.
  Future<void> _relinkTpackerDependencies(Set<String> dependencies, ProjectRepository repo, String destinationFolderUri) async {
    for (final depPath in dependencies) {
      if (depPath.toLowerCase().endsWith('.tpacker')) {
        final fileName = p.basename(depPath);
        final destFile = await repo.fileHandler.resolvePath(destinationFolderUri, fileName);
        if (destFile == null) continue;

        final content = await repo.readFile(destFile.uri);
        final tpackerProject = TexturePackerProject.fromJson(jsonDecode(content));

        final newRoot = _recursivelyRelinkTpackerNodes(tpackerProject.sourceImagesRoot);
        final newProject = tpackerProject.copyWith(sourceImagesRoot: newRoot);

        await repo.createDocumentFile(
          destinationFolderUri,
          fileName,
          initialContent: jsonEncode(newProject.toJson()),
          overwrite: true,
        );
      }
    }
  }

  /// Helper that recursively rebuilds the node tree with updated paths.
  SourceImageNode _recursivelyRelinkTpackerNodes(SourceImageNode node) {
    SourceImageConfig? newContent;
    if (node.type == SourceNodeType.image && node.content != null && node.content!.path.isNotEmpty) {
      newContent = node.content!.copyWith(path: p.basename(node.content!.path));
    }

    return node.copyWith(
      content: newContent ?? node.content,
      children: node.children.map(_recursivelyRelinkTpackerNodes).toList(),
    );
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
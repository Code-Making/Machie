// FILE: lib/editor/plugins/unified_export/unified_export_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:tiled/tiled.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xml/xml.dart';

import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/tiled_editor/tiled_asset_resolver.dart';
import 'package:machine/editor/plugins/tiled_editor/project_tsx_provider.dart';
import 'package:machine/editor/plugins/tiled_editor/tmj_writer.dart';
import 'package:machine/editor/plugins/tiled_editor/tmx_writer.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/utils/texture_packer_algo.dart';
import 'package:machine/editor/plugins/flow_graph/models/flow_graph_models.dart';

import 'unified_export_models.dart';
import '../../../asset_cache/asset_models.dart';

final unifiedExportServiceProvider = Provider((ref) => UnifiedExportService(ref));

class UnifiedExportService {
  final Ref _ref;
  UnifiedExportService(this._ref);

  Future<DependencyNode> scanDependencies(
    String rootUri, 
    ProjectRepository repo, 
    TiledAssetResolver resolver
  ) async {
    final visited = <String>{};
    return _scanRecursive(rootUri, repo, resolver, visited);
  }

  Future<DependencyNode> _scanRecursive(
    String uri, 
    ProjectRepository repo, 
    TiledAssetResolver resolver,
    Set<String> visited
  ) async {
    if (visited.contains(uri)) return _createNode(uri, [], visited: true);
    visited.add(uri);

    final ext = p.extension(uri).toLowerCase();
    final children = <DependencyNode>[];
    
    final relativePath = repo.fileHandler.getPathForDisplay(uri, relativeTo: repo.rootUri);

    try {
      if (ext == '.tmx') {
        final content = await repo.readFile(uri);
        final tsxProvider = ProjectTsxProvider(repo, repo.fileHandler.getParentUri(uri));
        final tsxProviders = await ProjectTsxProvider.parseFromTmx(content, tsxProvider.getProvider);
        final map = TileMapParser.parseTmx(content, tsxList: tsxProviders);

        for (final ts in map.tilesets) {
          final imgSource = ts.image?.source;
          if (imgSource != null) {
            final assetUri = repo.resolveRelativePath(relativePath, imgSource);
            children.add(await _scanRecursive(assetUri, repo, resolver, visited));
          }
        }
        
        void scanProperties(CustomProperties props) async {
          final fgProp = props['flowGraph'];
          if (fgProp is StringProperty && fgProp.value.isNotEmpty) {
             final assetUri = repo.resolveRelativePath(relativePath, fgProp.value);
             children.add(await _scanRecursive(assetUri, repo, resolver, visited));
          }
          final tpProp = props['tp_atlases'];
          if (tpProp is StringProperty && tpProp.value.isNotEmpty) {
            for(var path in tpProp.value.split(',')) {
               final assetUri = repo.resolveRelativePath(relativePath, path.trim());
               children.add(await _scanRecursive(assetUri, repo, resolver, visited));
            }
          }
        }
        
        scanProperties(map.properties);
        for(var layer in map.layers) {
          scanProperties(layer.properties);
          if (layer is ObjectGroup) {
            for(var obj in layer.objects) scanProperties(obj.properties);
          }
        }

      } else if (ext == '.tpacker') {
        final content = await repo.readFile(uri);
        final project = TexturePackerProject.fromJson(jsonDecode(content));
        
        void scanSource(SourceImageNode node) async {
          if (node.type == SourceNodeType.image && node.content != null) {
             final assetUri = repo.resolveRelativePath(relativePath, node.content!.path);
             children.add(await _scanRecursive(assetUri, repo, resolver, visited));
          }
          for(var c in node.children) scanSource(c);
        }
        scanSource(project.sourceImagesRoot);

      } else if (ext == '.fg') {
        // Flow graph scanning logic if needed
      }
    } catch (e) {
      print("Scan error on $uri: $e");
    }

    return _createNode(uri, children);
  }

  DependencyNode _createNode(String uri, List<DependencyNode> children, {bool visited = false}) {
    final ext = p.extension(uri).toLowerCase();
    ExportNodeType type = ExportNodeType.unknown;
    if (ext == '.tmx') type = ExportNodeType.tmx;
    else if (ext == '.tpacker') type = ExportNodeType.tpacker;
    else if (ext == '.fg') type = ExportNodeType.flowGraph;
    else if (['.png', '.jpg', '.jpeg'].contains(ext)) type = ExportNodeType.image;

    return DependencyNode(
      sourcePath: uri, 
      destinationPath: uri,
      type: type,
      children: children,
      included: !visited,
    );
  }

  Future<ExportResult> buildAtlas(
    DependencyNode rootNode,
    TiledAssetResolver resolver,
    {int maxAtlasSize = 2048, bool stripUnused = true}
  ) async {
    final slices = <PackableSlice>[];
    final repo = resolver.repo;
    final projectRoot = repo.rootUri;

    final processedUris = <String>{};
    
    Future<void> processNode(DependencyNode node) async {
      if (processedUris.contains(node.sourcePath) || !node.included) return;
      processedUris.add(node.sourcePath);

      final relativePath = repo.fileHandler.getPathForDisplay(node.sourcePath, relativeTo: projectRoot);

      if (node.type == ExportNodeType.tpacker) {
        final content = await repo.readFile(node.sourcePath);
        final proj = TexturePackerProject.fromJson(jsonDecode(content));
        
        void collectSprites(PackerItemNode itemNode) {
          if (itemNode.type == PackerItemType.sprite) {
            final def = proj.definitions[itemNode.id];
            if (def is SpriteDefinition) {
              final sourceConfig = _findSourceInTpacker(proj.sourceImagesRoot, def.sourceImageId);
              if (sourceConfig != null) {
                // Ensure asset is loaded
                // In a real scenario, we might need to pre-load these if they aren't in TiledAssetResolver
                // Assuming resolver has them for now or we skip
                final imgPath = repo.resolveRelativePath(relativePath, sourceConfig.path);
                final imgAsset = resolver.rawAssets[imgPath]; 
                
                if (imgAsset is ImageAssetData) {
                   final sliceRect = _calculateTpackerRect(sourceConfig, def.gridRect);
                   slices.add(PackableSlice(
                     id: itemNode.name, // Sprite Name
                     sourceImage: imgAsset.image,
                     sourceRect: sliceRect,
                     originalName: itemNode.name,
                   ));
                }
              }
            }
          }
          for(var c in itemNode.children) collectSprites(c);
        }
        collectSprites(proj.tree);

      } else if (node.type == ExportNodeType.tmx) {
        final content = await repo.readFile(node.sourcePath);
        final tsxProvider = ProjectTsxProvider(repo, repo.fileHandler.getParentUri(node.sourcePath));
        final tsxProviders = await ProjectTsxProvider.parseFromTmx(content, tsxProvider.getProvider);
        final map = TileMapParser.parseTmx(content, tsxList: tsxProviders);

        for (final tileset in map.tilesets) {
          if (tileset.image?.source == null) continue;
          
          final tsPath = tileset.source != null 
              ? repo.resolveRelativePath(relativePath, tileset.source!)
              : relativePath;
              
          final imgPath = repo.resolveRelativePath(tsPath, tileset.image!.source!);
          final imgAsset = resolver.rawAssets[imgPath];

          if (imgAsset is ImageAssetData) {
             final cols = tileset.columns ?? 1;
             final count = tileset.tileCount ?? 0;
             final tsName = tileset.name ?? 'ts_${tileset.image!.source}';
             
             for(int i=0; i<count; i++) {
               final x = (i % cols) * (tileset.tileWidth! + tileset.spacing) + tileset.margin;
               final y = (i ~/ cols) * (tileset.tileHeight! + tileset.spacing) + tileset.margin;
               
               // Create a unique ID for this tile slice: "TilesetName_LocalID"
               // We handle potential naming collisions by prepending map/tileset context if needed, 
               // but for now relying on tileset name.
               final sliceId = "${tsName}_$i";
               
               // Check if we already have this slice (deduplication)
               if (!slices.any((s) => s.id == sliceId)) {
                 slices.add(PackableSlice(
                   id: sliceId,
                   sourceImage: imgAsset.image,
                   sourceRect: ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), tileset.tileWidth!.toDouble(), tileset.tileHeight!.toDouble()),
                   originalName: sliceId,
                   isGridTile: true,
                   originalGid: tileset.firstGid! + i, 
                 ));
               }
             }
          }
        }
      }

      for (var c in node.children) await processNode(c);
    }

    await processNode(rootNode);

    // Sort slices by ID to ensure deterministic output
    slices.sort((a, b) => a.id.compareTo(b.id));

    final packerItems = slices.map((s) => PackerInputItem(
      width: s.sourceRect.width, 
      height: s.sourceRect.height, 
      data: s
    )).toList();

    final packer = MaxRectsPacker(padding: 2);
    final packedResult = packer.pack(packerItems);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    final packedRects = <String, ui.Rect>{};

    for(final item in packedResult.items) {
      final slice = item.data as PackableSlice;
      final destRect = ui.Rect.fromLTWH(item.x, item.y, item.width, item.height);
      canvas.drawImageRect(slice.sourceImage, slice.sourceRect, destRect, paint);
      packedRects[slice.id] = destRect;
    }

    final picture = recorder.endRecording();
    final atlasImage = await picture.toImage(packedResult.width.toInt(), packedResult.height.toInt());
    final pngBytes = (await atlasImage.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();

    // Prepare JSON metadata
    final frames = <String, dynamic>{};
    
    // Sort keys again for JSON stability
    final sortedKeys = packedRects.keys.toList()..sort();
    
    for(final id in sortedKeys) {
      final rect = packedRects[id]!;
      frames[id] = {
        "frame": {"x": rect.left.toInt(), "y": rect.top.toInt(), "w": rect.width.toInt(), "h": rect.height.toInt()},
        "rotated": false,
        "trimmed": false,
        "spriteSourceSize": {"x": 0, "y": 0, "w": rect.width.toInt(), "h": rect.height.toInt()},
        "sourceSize": {"w": rect.width.toInt(), "h": rect.height.toInt()}
      };
    }

    final meta = {
      "app": "Machine Unified Exporter",
      "version": "1.0",
      "image": "atlas.png",
      "size": {"w": packedResult.width.toInt(), "h": packedResult.height.toInt()},
      "scale": "1"
    };

    return ExportResult(
      atlases: [AtlasPage(
        width: packedResult.width.toInt(), 
        height: packedResult.height.toInt(), 
        pngBytes: pngBytes, 
        packedRects: packedRects
      )], 
      atlasMetaJson: {"frames": frames, "meta": meta},
      gidRemapTable: {}, // Will be populated dynamically per map during write
    );
  }

  Future<void> writeExport(
    DependencyNode rootNode,
    ExportResult exportData,
    String destinationUri,
    ProjectRepository repo,
    {bool exportAsJson = true}
  ) async {
    final processed = <String>{};
    final atlasFileName = "atlas.png";
    final atlasJsonName = "atlas.json";

    // Write Atlas Image and Metadata
    final atlasPage = exportData.atlases.first;
    await repo.createDocumentFile(
      destinationUri, 
      atlasFileName, 
      initialBytes: atlasPage.pngBytes, 
      overwrite: true
    );
    await repo.createDocumentFile(
      destinationUri, 
      atlasJsonName, 
      initialContent: jsonEncode(exportData.atlasMetaJson), 
      overwrite: true
    );

    // Prepare the unified Tileset that represents the Atlas
    // We create a "virtual" tileset where every tile is explicitly defined with its rect in the atlas.
    final atlasTileset = _createAtlasTileset(exportData, atlasFileName);

    Future<void> writeNode(DependencyNode node) async {
      if (processed.contains(node.sourcePath) || !node.included) return;
      processed.add(node.sourcePath);

      final originalName = p.basenameWithoutExtension(node.sourcePath);
      final newExt = exportAsJson ? '.json' : p.extension(node.sourcePath);
      final newName = "$originalName$newExt";

      if (node.type == ExportNodeType.tmx) {
        // 1. Read and Parse Original Map
        final content = await repo.readFile(node.sourcePath);
        final parentUri = repo.fileHandler.getParentUri(node.sourcePath);
        final tsxProvider = ProjectTsxProvider(repo, parentUri);
        final tsxProviders = await ProjectTsxProvider.parseFromTmx(content, tsxProvider.getProvider);
        
        // Deep copy via write/parse to ensure we don't mutate cache
        final originalMap = TileMapParser.parseTmx(content, tsxList: tsxProviders);
        final mapToExport = _deepCopyMap(originalMap);

        // 2. Build GID Remap Table for this specific map
        // We need to map [Old Gid] -> [Atlas Gid]
        final gidRemap = <int, int>{};
        
        for (final tileset in mapToExport.tilesets) {
           final firstGid = tileset.firstGid ?? 1;
           final tsName = tileset.name ?? 'ts_${tileset.image?.source}';
           final tileCount = tileset.tileCount ?? 0;
           
           for (int i = 0; i < tileCount; i++) {
             final oldGid = firstGid + i;
             final sliceId = "${tsName}_$i";
             
             // Find where this slice ended up in the Atlas Tileset
             // The Atlas Tileset tiles are ordered based on the sorted keys in buildAtlas
             final newTile = atlasTileset.tiles.firstWhereOrNull((t) => 
               t.properties['originalId']?.value == sliceId
             );
             
             if (newTile != null) {
               // The GID in the map will be: AtlasFirstGid (1) + Tile.localId
               gidRemap[oldGid] = 1 + newTile.localId;
             }
           }
        }

        // 3. Remap Layers and Objects
        _remapGids(mapToExport, gidRemap);

        // 4. Replace Tilesets
        mapToExport.tilesets.clear();
        mapToExport.tilesets.add(atlasTileset);
        
        // 5. Serialize and Write
        final String resultContent = exportAsJson 
            ? TmjWriter(mapToExport).toTmj()
            : TmxWriter(mapToExport).toTmx();
            
        await repo.createDocumentFile(
          destinationUri, 
          newName, 
          initialContent: resultContent, 
          overwrite: true
        );

      } else if (node.type == ExportNodeType.flowGraph) {
         // TODO: Implement FlowGraph rewrite to point to exported assets if necessary
      }

      for(var c in node.children) await writeNode(c);
    }

    await writeNode(rootNode);
  }

  Tileset _createAtlasTileset(ExportResult exportData, String atlasImageName) {
    final packedRects = exportData.atlases.first.packedRects;
    final sortedKeys = packedRects.keys.toList()..sort();
    
    final newTiles = <Tile>[];
    int localId = 0;

    for (final id in sortedKeys) {
      final rect = packedRects[id]!;
      // We store the original ID in properties to help mapping later
      // and the source rect for engines that support it
      final tile = Tile(localId: localId);
      tile.properties.add(StringProperty(name: 'originalId', value: id));
      tile.properties.add(StringProperty(name: 'sourceRect', value: '${rect.left},${rect.top},${rect.width},${rect.height}'));
      newTiles.add(tile);
      localId++;
    }

    final atlasWidth = exportData.atlases.first.width;
    final atlasHeight = exportData.atlases.first.height;

    return Tileset(
      name: 'Atlas',
      firstGid: 1,
      tileWidth: 16, // Nominal, individual tiles have specific rects if needed
      tileHeight: 16,
      tileCount: newTiles.length,
      columns: 0, // Image collection style
      image: TiledImage(source: atlasImageName, width: atlasWidth, height: atlasHeight),
      tiles: newTiles,
    );
  }

  void _remapGids(TiledMap map, Map<int, int> gidRemap) {
    for (final layer in map.layers) {
      if (layer is TileLayer && layer.tileData != null) {
        for (final row in layer.tileData!) {
          for (final gid in row) {
            if (gid.tile != 0 && gidRemap.containsKey(gid.tile)) {
               // We need to construct a new GID preserving flags
               final newTileId = gidRemap[gid.tile]!;
               // Tiled package Gid class is immutable-ish for the tile ID usually? 
               // Actually the Gid object has 'tile' field which is int.
               // But usually we replace the Gid object in the matrix.
               
               // Create a Gid object with the new tile ID and old flags
               // Note: 'tiled' package Gid constructor takes ID including flags, 
               // or we can use Gid(tile, flags). 
               // Looking at tiled package source, Gid(int tile, Flips flips).
               
               // We must write back to the row. The row is a List<Gid>.
               // row[x] = Gid(newTileId, gid.flips);
               // Wait, Dart 'for-in' loop variable 'gid' is a copy/reference. 
               // We need index access to modify the list.
            }
          }
        }
        
        // Proper iteration for modification
        for (int y = 0; y < layer.tileData!.length; y++) {
          for (int x = 0; x < layer.tileData![y].length; x++) {
             final gid = layer.tileData![y][x];
             if (gid.tile != 0 && gidRemap.containsKey(gid.tile)) {
               layer.tileData![y][x] = Gid(gidRemap[gid.tile]!, gid.flips);
             }
          }
        }
        
      } else if (layer is ObjectGroup) {
        for (final obj in layer.objects) {
          if (obj.gid != null && gidRemap.containsKey(obj.gid)) {
            obj.gid = gidRemap[obj.gid!];
          }
          
          // Also handle 'tp_sprite' property if it maps to an atlas frame
          final spriteProp = obj.properties['tp_sprite'];
          if (spriteProp is StringProperty) {
            // If the sprite name matches an ID in our atlas
            // We need to find the GID for that ID.
            // But gidRemap is int->int. 
            // We might need a separate lookup for sprite names if they aren't based on GIDs.
            // For now assuming existing logic where objects use GIDs or standard tiles.
          }
        }
      }
    }
  }
  
  TiledMap _deepCopyMap(TiledMap original) {
    // Quick and dirty deep copy via serialization
    final writer = TmxWriter(original);
    final tmxString = writer.toTmx();
    return TileMapParser.parseTmx(tmxString);
  }

  SourceImageConfig? _findSourceInTpacker(SourceImageNode node, String id) {
    if (node.id == id && node.content != null) return node.content;
    for(var c in node.children) {
      final found = _findSourceInTpacker(c, id);
      if (found != null) return found;
    }
    return null;
  }

  ui.Rect _calculateTpackerRect(SourceImageConfig config, GridRect grid) {
    final s = config.slicing;
    final left = s.margin + grid.x * (s.tileWidth + s.padding);
    final top = s.margin + grid.y * (s.tileHeight + s.padding);
    final width = grid.width * s.tileWidth + (grid.width - 1) * s.padding;
    final height = grid.height * s.tileHeight + (grid.height - 1) * s.padding;
    return ui.Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble());
  }
}
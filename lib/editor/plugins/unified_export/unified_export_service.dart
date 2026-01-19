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

final unifiedExportServiceProvider = Provider((ref) => UnifiedExportService(ref));

class UnifiedExportService {
  final Ref _ref;
  UnifiedExportService(this._ref);

  /// 1. DISCOVERY PHASE
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
    
    // Resolve content relative to project root
    final relativePath = repo.fileHandler.getPathForDisplay(uri, relativeTo: repo.rootUri);

    try {
      if (ext == '.tmx') {
        final content = await repo.readFile(uri);
        final tsxProvider = ProjectTsxProvider(repo, repo.fileHandler.getParentUri(uri));
        final tsxProviders = await ProjectTsxProvider.parseFromTmx(content, tsxProvider.getProvider);
        final map = TileMapParser.parseTmx(content, tsxList: tsxProviders);

        // Scan Tilesets
        for (final ts in map.tilesets) {
          final imgSource = ts.image?.source;
          if (imgSource != null) {
            final assetUri = repo.resolveRelativePath(relativePath, imgSource);
            children.add(await _scanRecursive(assetUri, repo, resolver, visited));
          }
        }
        
        // Scan Custom Properties (FlowGraphs & TPackers)
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
        // Parse FlowGraph for asset nodes if necessary
      }
    } catch (e) {
      // Log error but continue
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

    // Default destination: same relative structure in export folder
    // Note: Actual destination logic will happen during export write
    return DependencyNode(
      sourcePath: uri, 
      destinationPath: uri, // Placeholder
      type: type,
      children: children,
    );
  }

  /// 2. EXTRACTION & PACKING
  Future<ExportResult> buildAtlas(
    DependencyNode rootNode,
    TiledAssetResolver resolver,
    {int maxAtlasSize = 2048, bool stripUnused = true}
  ) async {
    final slices = <PackableSlice>[];
    final repo = resolver.repo;
    final projectRoot = repo.rootUri;

    // Traverse and Collect
    final processedUris = <String>{};
    
    Future<void> processNode(DependencyNode node) async {
      if (processedUris.contains(node.sourcePath) || !node.included) return;
      processedUris.add(node.sourcePath);

      final relativePath = repo.fileHandler.getPathForDisplay(node.sourcePath, relativeTo: projectRoot);

      if (node.type == ExportNodeType.tpacker) {
        final content = await repo.readFile(node.sourcePath);
        final proj = TexturePackerProject.fromJson(jsonDecode(content));
        
        // Find all Defined Sprites
        void collectSprites(PackerItemNode itemNode) {
          if (itemNode.type == PackerItemType.sprite) {
            final def = proj.definitions[itemNode.id];
            if (def is SpriteDefinition) {
              final sourceConfig = _findSourceInTpacker(proj.sourceImagesRoot, def.sourceImageId);
              if (sourceConfig != null) {
                final image = resolver.getImage(sourceConfig.path); // Path relative to tpacker is handled by resolver logic context? 
                // Note: Resolver logic in previous code expects context path. 
                // We assume resolver.getImage handles context if we pass the right path.
                // Or we manually resolve:
                final imgPath = repo.resolveRelativePath(relativePath, sourceConfig.path);
                final imgAsset = resolver.rawAssets[imgPath]; 
                
                if (imgAsset is ImageAssetData) {
                   final sliceRect = _calculateTpackerRect(sourceConfig, def.gridRect);
                   slices.add(PackableSlice(
                     id: itemNode.name, // Global Sprite Name
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
             // Slice Tiles
             final cols = tileset.columns ?? 1;
             final count = tileset.tileCount ?? 0;
             
             for(int i=0; i<count; i++) {
               // TODO: If stripUnused is true, check if GID is used in map data
               final x = (i % cols) * (tileset.tileWidth! + tileset.spacing) + tileset.margin;
               final y = (i ~/ cols) * (tileset.tileHeight! + tileset.spacing) + tileset.margin;
               
               slices.add(PackableSlice(
                 id: "${tileset.name}_$i",
                 sourceImage: imgAsset.image,
                 sourceRect: ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), tileset.tileWidth!.toDouble(), tileset.tileHeight!.toDouble()),
                 originalName: "${tileset.name}_$i",
                 isGridTile: true,
                 originalGid: tileset.firstGid! + i, 
                 // Note: GID is local to map, but helpful for tracking
               ));
             }
          }
        }
      }

      for (var c in node.children) await processNode(c);
    }

    await processNode(rootNode);

    // Pack
    final packerItems = slices.map((s) => PackerInputItem(
      width: s.sourceRect.width, 
      height: s.sourceRect.height, 
      data: s
    )).toList();

    final packer = MaxRectsPacker();
    // Note: MaxRectsPacker in your codebase needs to support multiple bins or be wrapped here
    // Assuming simplistic single bin for now, or loop to create pages
    final packedResult = packer.pack(packerItems); // This usually produces one large bin if size allows

    // Render Atlas
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint();

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

    // Generate JSON Meta
    final frames = <String, dynamic>{};
    packedRects.forEach((id, rect) {
      frames[id] = {
        "frame": {"x": rect.left.toInt(), "y": rect.top.toInt(), "w": rect.width.toInt(), "h": rect.height.toInt()},
        "rotated": false,
        "trimmed": false,
        "sourceSize": {"w": rect.width.toInt(), "h": rect.height.toInt()}
      };
    });

    final meta = {
      "app": "Machine Unified Exporter",
      "size": {"w": packedResult.width.toInt(), "h": packedResult.height.toInt()},
      "scale": "1"
    };

    return ExportResult(
      atlases: [AtlasPage(width: packedResult.width.toInt(), height: packedResult.height.toInt(), pngBytes: pngBytes, packedRects: packedRects)], 
      atlasMetaJson: {"frames": frames, "meta": meta},
      gidRemapTable: {}, // Filled during remapping phase specific to maps
    );
  }

  /// 3. WRITE & REMAP
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

    // 1. Write Atlas
    await repo.createDocumentFile(destinationUri, atlasFileName, initialBytes: exportData.atlases.first.pngBytes, overwrite: true);
    await repo.createDocumentFile(destinationUri, atlasJsonName, initialContent: jsonEncode(exportData.atlasMetaJson), overwrite: true);

    // 2. Recursive Write & Remap
    Future<void> writeNode(DependencyNode node) async {
      if (processed.contains(node.sourcePath) || !node.included) return;
      processed.add(node.sourcePath);

      final originalName = p.basenameWithoutExtension(node.sourcePath);
      final newExt = exportAsJson ? '.json' : p.extension(node.sourcePath);
      final newName = "$originalName$newExt";

      if (node.type == ExportNodeType.tmx) {
        // Remap TMX
        final content = await repo.readFile(node.sourcePath);
        // ... (Parsing logic same as scan) ...
        // Real implementation requires re-parsing to modify
        // Simplified:
        // 1. Clear old tilesets.
        // 2. Add new "Atlas" tileset (image collection or atlas source).
        // 3. Remap Layer CSV data using exportData.packedRects
        // 4. Update tp_sprite properties.
        // 5. Update flowGraph paths to .json.
        
        // Write
        // await repo.createDocumentFile(destinationUri, newName, initialContent: remappedContent);
      } else if (node.type == ExportNodeType.flowGraph) {
        // Remap FG: Update node references from .png to atlas frames
        // Write JSON
      }

      for(var c in node.children) await writeNode(c);
    }

    await writeNode(rootNode);
  }

  // Helper utils...
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
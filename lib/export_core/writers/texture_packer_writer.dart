import 'dart:convert';
import 'dart:typed_data';
import 'package:machine/editor/plugins/texture_packer/texture_packer_models.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import '../packer/packer_models.dart';
import '../models.dart';
import 'writer_interface.dart';

class TexturePackerWriter implements AssetWriter {
  final ProjectRepository repo;
  
  TexturePackerWriter(this.repo);

  @override
  String get extension => 'json';

  @override
  Future<Uint8List> rewrite(
    String projectRelativePath,
    Uint8List fileContent,
    PackedAtlasResult atlasResult,
  ) async {
    // 1. Parse original .tpacker file to get names and structure
    final projectJson = jsonDecode(utf8.decode(fileContent));
    final project = TexturePackerProject.fromJson(projectJson);

    final frames = <String, dynamic>{};
    final animations = <String, dynamic>{};

    // 2. Helper to traverse source nodes to find paths
    SourceImageConfig? findSourceConfig(String id) {
      SourceImageConfig? traverse(SourceImageNode node) {
        if (node.id == id && node.type == SourceNodeType.image) return node.content;
        for (final child in node.children) {
          final res = traverse(child);
          if (res != null) return res;
        }
        return null;
      }
      return traverse(project.sourceImagesRoot);
    }

    // 3. Traverse Items and lookup new coordinates
    void processNode(PackerItemNode node) {
      if (node.type == PackerItemType.sprite) {
        final def = project.definitions[node.id];
        if (def is SpriteDefinition) {
          final sourceConfig = findSourceConfig(def.sourceImageId);
          if (sourceConfig != null) {
            
            final imagePath = repo.resolveRelativePath(projectRelativePath, sourceConfig.path);
            
            // Reconstruct the ID used in Phase 1
            // Note: We need to replicate the exact rect calculation logic here
            final s = sourceConfig.slicing;
            final g = def.gridRect;
            final x = s.margin + g.x * (s.tileWidth + s.padding);
            final y = s.margin + g.y * (s.tileHeight + s.padding);
            final w = g.width * s.tileWidth + (g.width - 1) * s.padding;
            final h = g.height * s.tileHeight + (g.height - 1) * s.padding;

            final id = ExportableAssetId(
              sourcePath: imagePath,
              x: x, y: y, width: w, height: h,
            );

            if (atlasResult.lookup.containsKey(id)) {
              final loc = atlasResult.lookup[id]!;
              final rect = loc.packedRect;
              
              frames[node.name] = {
                "frame": {"x": rect.left.toInt(), "y": rect.top.toInt(), "w": rect.width.toInt(), "h": rect.height.toInt()},
                "rotated": loc.rotated,
                "trimmed": false,
                "spriteSourceSize": {"x": 0, "y": 0, "w": rect.width.toInt(), "h": rect.height.toInt()},
                "sourceSize": {"w": rect.width.toInt(), "h": rect.height.toInt()},
              };
            }
          }
        }
      } else if (node.type == PackerItemType.animation) {
        // Collect frame names
        final frameNames = node.children
            .where((c) => c.type == PackerItemType.sprite)
            .map((c) => c.name)
            .toList();
        if (frameNames.isNotEmpty) {
          animations[node.name] = frameNames;
        }
        // Recursion for nested
        for(var c in node.children) processNode(c);
      } else {
        for(var c in node.children) processNode(c);
      }
    }

    processNode(project.tree);

    // 4. Construct Final JSON
    final atlasWidth = atlasResult.pages[0].width;
    final atlasHeight = atlasResult.pages[0].height;
    
    final outputJson = {
      "frames": frames,
      "animations": animations,
      "meta": {
        "app": "Machine Editor",
        "version": "1.0",
        "image": "atlas_0.png", // Hardcoded for single page for now
        "format": "RGBA8888",
        "size": {"w": atlasWidth, "h": atlasHeight},
        "scale": "1"
      }
    };

    return utf8.encode(const JsonEncoder.withIndent('  ').convert(outputJson));
  }
}
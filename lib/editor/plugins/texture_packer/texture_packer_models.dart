import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

/// Enum defining the types of items in the output hierarchy.
enum PackerItemType { folder, sprite, animation }

/// Enum defining types for source images (grouping vs actual file).
enum SourceNodeType { folder, image }

// -----------------------------------------------------------------------------
//region Slicing and Source Image Configuration
// -----------------------------------------------------------------------------

/// Defines the grid parameters for slicing a source image.
@immutable
class SlicingConfig {
  final int tileWidth;
  final int tileHeight;
  final int margin;
  final int padding;

  const SlicingConfig({
    this.tileWidth = 16,
    this.tileHeight = 16,
    this.margin = 0,
    this.padding = 0,
  });

  factory SlicingConfig.fromJson(Map<String, dynamic> json) {
    return SlicingConfig(
      tileWidth: json['tileWidth'] ?? 16,
      tileHeight: json['tileHeight'] ?? 16,
      margin: json['margin'] ?? 0,
      padding: json['padding'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'tileWidth': tileWidth,
        'tileHeight': tileHeight,
        'margin': margin,
        'padding': padding,
      };

  SlicingConfig copyWith({
    int? tileWidth,
    int? tileHeight,
    int? margin,
    int? padding,
  }) {
    return SlicingConfig(
      tileWidth: tileWidth ?? this.tileWidth,
      tileHeight: tileHeight ?? this.tileHeight,
      margin: margin ?? this.margin,
      padding: padding ?? this.padding,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SlicingConfig &&
          runtimeType == other.runtimeType &&
          tileWidth == other.tileWidth &&
          tileHeight == other.tileHeight &&
          margin == other.margin &&
          padding == other.padding;

  @override
  int get hashCode => Object.hash(tileWidth, tileHeight, margin, padding);
}

/// Represents the data for a source image leaf node.
@immutable
class SourceImageConfig {
  final String path;
  final SlicingConfig slicing;

  const SourceImageConfig({
    required this.path,
    this.slicing = const SlicingConfig(),
  });

  factory SourceImageConfig.fromJson(Map<String, dynamic> json) {
    return SourceImageConfig(
      path: json['path'],
      slicing: SlicingConfig.fromJson(json['slicing'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'slicing': slicing.toJson(),
      };

  SourceImageConfig copyWith({String? path, SlicingConfig? slicing}) {
    return SourceImageConfig(
      path: path ?? this.path,
      slicing: slicing ?? this.slicing,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceImageConfig &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          slicing == other.slicing;

  @override
  int get hashCode => Object.hash(path, slicing);
}

/// Represents a node in the SOURCE IMAGE tree structure.
@immutable
class SourceImageNode {
  final String id;
  final String name;
  final SourceNodeType type;
  final List<SourceImageNode> children;
  
  /// Only present if type == SourceNodeType.image
  final SourceImageConfig? content;

  SourceImageNode({
    String? id,
    required this.name,
    required this.type,
    this.children = const [],
    this.content,
  }) : id = id ?? const Uuid().v4();

  factory SourceImageNode.fromJson(Map<String, dynamic> json) {
    return SourceImageNode(
      id: json['id'],
      name: json['name'],
      type: SourceNodeType.values.byName(json['type']),
      children: (json['children'] as List? ?? [])
          .map((childJson) => SourceImageNode.fromJson(childJson))
          .toList(),
      content: json['content'] != null 
          ? SourceImageConfig.fromJson(json['content']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'children': children.map((child) => child.toJson()).toList(),
        if (content != null) 'content': content!.toJson(),
      };

  SourceImageNode copyWith({
    String? name,
    SourceNodeType? type,
    List<SourceImageNode>? children,
    SourceImageConfig? content,
  }) {
    return SourceImageNode(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      children: children ?? this.children,
      content: content ?? this.content,
    );
  }
}

//endregion

// -----------------------------------------------------------------------------
//region Item Definitions (The actual data for sprites and animations)
// -----------------------------------------------------------------------------

@immutable
class GridRect {
  final int x;
  final int y;
  final int width;
  final int height;

  const GridRect({
    required this.x,
    required this.y,
    this.width = 1,
    this.height = 1,
  });

  factory GridRect.fromJson(Map<String, dynamic> json) => GridRect(
        x: json['x'],
        y: json['y'],
        width: json['width'] ?? 1,
        height: json['height'] ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };
}

@immutable
abstract class PackerItemDefinition {
  const PackerItemDefinition();
  
  Map<String, dynamic> toJson();

  static PackerItemDefinition? fromJson(PackerItemType type, Map<String, dynamic>? json) {
    if (json == null) return null;
    switch (type) {
      case PackerItemType.sprite:
        return SpriteDefinition.fromJson(json);
      case PackerItemType.animation:
        return AnimationDefinition.fromJson(json);
      case PackerItemType.folder:
      default:
        return null;
    }
  }
}

/// Defines a single sprite by referencing a source image ID and a grid rectangle.
class SpriteDefinition extends PackerItemDefinition {
  /// Reference to a [SourceImageNode.id] where type is image.
  final String sourceImageId; 
  final GridRect gridRect;

  const SpriteDefinition({
    required this.sourceImageId,
    required this.gridRect,
  });

  factory SpriteDefinition.fromJson(Map<String, dynamic> json) {
    return SpriteDefinition(
      // Support migration from old 'index' based if necessary (logic needs to handle conversion elsewhere)
      // For strictly new model:
      sourceImageId: json['sourceImageId'] ?? '',
      gridRect: GridRect.fromJson(json['gridRect']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'sourceImageId': sourceImageId,
        'gridRect': gridRect.toJson(),
      };
}

/// Defines an animation configuration.
/// 
/// Note: Frame data is no longer stored here. 
/// Frames are the children [PackerItemNode]s of the node containing this definition.
class AnimationDefinition extends PackerItemDefinition {
  final double speed; // in frames per second

  const AnimationDefinition({
    this.speed = 10.0,
  });

  factory AnimationDefinition.fromJson(Map<String, dynamic> json) {
    return AnimationDefinition(
      speed: json['speed']?.toDouble() ?? 10.0,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'speed': speed,
      };
}

//endregion

// -----------------------------------------------------------------------------
//region Hierarchy and Main Project Structure
// -----------------------------------------------------------------------------

/// Represents a node in the OUTPUT hierarchical tree structure (Folders, Animations, Sprites).
@immutable
class PackerItemNode {
  final String id;
  final String name;
  final PackerItemType type;
  final List<PackerItemNode> children;

  PackerItemNode({
    String? id,
    required this.name,
    required this.type,
    this.children = const [],
  }) : id = id ?? const Uuid().v4();

  factory PackerItemNode.fromJson(Map<String, dynamic> json) {
    return PackerItemNode(
      id: json['id'],
      name: json['name'],
      type: PackerItemType.values.byName(json['type']),
      children: (json['children'] as List? ?? [])
          .map((childJson) => PackerItemNode.fromJson(childJson))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'children': children.map((child) => child.toJson()).toList(),
      };

  PackerItemNode copyWith({
    String? name,
    PackerItemType? type,
    List<PackerItemNode>? children,
  }) {
    return PackerItemNode(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      children: children ?? this.children,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PackerItemNode &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// The root data model for a `.tpacker` file.
@immutable
class TexturePackerProject {
  /// The root of the Source Image tree (Input files).
  final SourceImageNode sourceImagesRoot;
  
  /// The root of the Packer Item tree (Output sprites/animations).
  final PackerItemNode tree;
  
  /// Definitions map (Node ID -> Definition Data).
  final Map<String, PackerItemDefinition> definitions;

  const TexturePackerProject({
    required this.sourceImagesRoot,
    required this.tree,
    this.definitions = const {},
  });
  
  /// Creates an empty, initial project state.
  factory TexturePackerProject.fresh() {
    return TexturePackerProject(
      sourceImagesRoot: SourceImageNode(name: 'root', type: SourceNodeType.folder, id: 'root'),
      tree: PackerItemNode(name: 'root', type: PackerItemType.folder, id: 'root'),
    );
  }

  factory TexturePackerProject.fromJson(Map<String, dynamic> json) {
    // Deserialize Output Tree
    final tree = PackerItemNode.fromJson(json['tree']);
    
    // Deserialize Source Image Tree
    SourceImageNode sourceRoot;
    if (json['sourceImagesRoot'] != null) {
      sourceRoot = SourceImageNode.fromJson(json['sourceImagesRoot']);
    } else {
      // Migration from old List<SourceImageConfig> if needed
      // For now, we return fresh root if not found to ensure non-null
      sourceRoot = SourceImageNode(name: 'root', type: SourceNodeType.folder, id: 'root');
    }

    final Map<String, PackerItemDefinition> defs = {};
    if (json['definitions'] != null) {
      final Map<String, dynamic> rawDefs = json['definitions'];
      
      // Helper to find node type by ID from the parsed tree
      PackerItemType? findType(String id) {
        PackerItemNode? find(PackerItemNode node) {
          if (node.id == id) return node;
          for (final child in node.children) {
            final found = find(child);
            if (found != null) return found;
          }
          return null;
        }
        return find(tree)?.type;
      }
      
      rawDefs.forEach((id, defJson) {
        final type = findType(id);
        if (type != null) {
          final def = PackerItemDefinition.fromJson(type, defJson);
          if (def != null) {
            defs[id] = def;
          }
        }
      });
    }

    return TexturePackerProject(
      sourceImagesRoot: sourceRoot,
      tree: tree,
      definitions: defs,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceImagesRoot': sourceImagesRoot.toJson(),
        'tree': tree.toJson(),
        'definitions': definitions.map((key, value) => MapEntry(key, value.toJson())),
      };
      
  TexturePackerProject copyWith({
    SourceImageNode? sourceImagesRoot,
    PackerItemNode? tree,
    Map<String, PackerItemDefinition>? definitions,
  }) {
    return TexturePackerProject(
      sourceImagesRoot: sourceImagesRoot ?? this.sourceImagesRoot,
      tree: tree ?? this.tree,
      definitions: definitions ?? this.definitions,
    );
  }
}
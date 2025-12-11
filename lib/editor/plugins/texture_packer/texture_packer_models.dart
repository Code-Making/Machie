import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

/// Enum defining the types of items in the hierarchy.
enum PackerItemType { folder, sprite, animation }

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
  int get hashCode =>
      Object.hash(tileWidth, tileHeight, margin, padding);
}

/// Represents a source spritesheet image and its slicing configuration.
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

//endregion

// -----------------------------------------------------------------------------
//region Item Definitions (The actual data for sprites and animations)
// -----------------------------------------------------------------------------

/// A simple rectangle class for grid coordinates.
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

/// Abstract base class for the data associated with a PackerItemNode.
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

/// Defines a single sprite by referencing a source image and a grid rectangle.
class SpriteDefinition extends PackerItemDefinition {
  final int sourceImageIndex;
  final GridRect gridRect;

  const SpriteDefinition({
    required this.sourceImageIndex,
    required this.gridRect,
  });

  factory SpriteDefinition.fromJson(Map<String, dynamic> json) {
    return SpriteDefinition(
      sourceImageIndex: json['sourceImageIndex'],
      gridRect: GridRect.fromJson(json['gridRect']),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'sourceImageIndex': sourceImageIndex,
        'gridRect': gridRect.toJson(),
      };
}

/// Defines an animation by an ordered list of sprite node IDs and a speed.
class AnimationDefinition extends PackerItemDefinition {
  final List<String> frameIds;
  final double speed; // in frames per second

  const AnimationDefinition({
    this.frameIds = const [],
    this.speed = 10.0,
  });

  factory AnimationDefinition.fromJson(Map<String, dynamic> json) {
    return AnimationDefinition(
      frameIds: List<String>.from(json['frameIds'] ?? []),
      speed: json['speed']?.toDouble() ?? 10.0,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'frameIds': frameIds,
        'speed': speed,
      };
}

//endregion

// -----------------------------------------------------------------------------
//region Hierarchy and Main Project Structure
// -----------------------------------------------------------------------------

/// Represents a node in the hierarchical tree structure.
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
  final List<SourceImageConfig> sourceImages;
  final PackerItemNode tree;
  final Map<String, PackerItemDefinition> definitions;

  const TexturePackerProject({
    this.sourceImages = const [],
    required this.tree,
    this.definitions = const {},
  });
  
  /// Creates an empty, initial project state.
  factory TexturePackerProject.fresh() {
    return TexturePackerProject(
      tree: PackerItemNode(name: 'root', type: PackerItemType.folder, id: 'root'),
    );
  }

  factory TexturePackerProject.fromJson(Map<String, dynamic> json) {
    final tree = PackerItemNode.fromJson(json['tree']);
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
      sourceImages: (json['sourceImages'] as List? ?? [])
          .map((e) => SourceImageConfig.fromJson(e))
          .toList(),
      tree: tree,
      definitions: defs,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceImages': sourceImages.map((e) => e.toJson()).toList(),
        'tree': tree.toJson(),
        'definitions': definitions.map((key, value) => MapEntry(key, value.toJson())),
      };
      
  TexturePackerProject copyWith({
    List<SourceImageConfig>? sourceImages,
    PackerItemNode? tree,
    Map<String, PackerItemDefinition>? definitions,
  }) {
    return TexturePackerProject(
      sourceImages: sourceImages ?? this.sourceImages,
      tree: tree ?? this.tree,
      definitions: definitions ?? this.definitions,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TexturePackerProject &&
          runtimeType == other.runtimeType &&
          const ListEquality().equals(sourceImages, other.sourceImages) &&
          tree == other.tree &&
          const MapEquality().equals(definitions, other.definitions);

  @override
  int get hashCode => Object.hash(
    const ListEquality().hash(sourceImages),
    tree,
    const MapEquality().hash(definitions),
  );
}

//endregion
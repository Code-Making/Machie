// lib/asset_cache/asset_models.dart
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/project/project_repository.dart';
import '../project/project_models.dart';
import 'package:machine/data/file_handler/file_handler.dart';

/// A sealed class representing the state of a cached asset.
@immutable
abstract class AssetData {
  const AssetData();
  
  bool get hasError => this is ErrorAssetData;
}

abstract class AssetLoader<T extends AssetData> {
  /// Returns true if this loader can handle the file (e.g. based on extension).
  bool canLoad(ProjectDocumentFile file);

  /// Loads and decodes the asset.
  /// [ref] is provided to access other providers/services if needed.
  /// For dependent assets, this method is called *after* its dependencies
  /// (declared via IDependentAssetLoader) have been successfully loaded.
  Future<T> load(Ref ref, ProjectDocumentFile file, ProjectRepository repo);
}

/// A mixin for AssetLoaders that depend on other assets.
///
/// This allows the asset system to reactively reload this asset when one of
/// its dependencies changes.
mixin IDependentAssetLoader<T extends AssetData> on AssetLoader<T> {
  /// Parses the given file to discover its asset dependencies.
  ///
  /// Returns a set of project-relative URIs that this asset needs to load.
  /// This method is called before `load`.
  Future<Set<String>> getDependencies(Ref ref, ProjectDocumentFile file, ProjectRepository repo);
}

/// Represents an asset that failed to load.
class ErrorAssetData extends AssetData {
  final Object error;
  final StackTrace? stackTrace;
  const ErrorAssetData({required this.error, this.stackTrace});
}

class ImageAssetData extends AssetData {
  final ui.Image image;
  const ImageAssetData({required this.image});
}


/// Represents a single sprite's location within the Texture Packer ecosystem.
///
/// This does NOT represent the sprite in the exported atlas PNG, but rather
/// the logical mapping for the editor to render it correctly using the
/// original source images (virtual atlas).
class TexturePackerSpriteData {
  /// The unique name of the sprite (e.g. "character/idle_01").
  final String name;
  
  /// The source image containing this sprite.
  final ui.Image sourceImage;
  
  /// The region within [sourceImage] that defines this sprite.
  final Rect sourceRect;
  
  /// The logical position where this sprite would be in the packed atlas.
  /// Used for export coordinates or previewing the atlas layout.
  final Rect packedRect;
  
  /// Whether the sprite is rotated in the pack (not fully implemented in Phase 1).
  final bool rotated;

  TexturePackerSpriteData({
    required this.name,
    required this.sourceImage,
    required this.sourceRect,
    required this.packedRect,
    this.rotated = false,
  });
}

/// The result of loading a .tpacker file.
///
/// Acts as a "Virtual Atlas", allowing other editors (like Tiled) to lookup
/// sprites by name and get the necessary source image data to draw them
/// without requiring the atlas PNG to be physically generated on disk.
class TexturePackerAssetData extends AssetData {
  /// Map of sprite names to their data.
  final Map<String, TexturePackerSpriteData> frames;
  
  /// Map of animation names to list of sprite names.
  final Map<String, List<String>> animations;
  
  /// The calculated size of the full atlas if it were exported.
  final ui.Size metaSize;

  const TexturePackerAssetData({
    required this.frames,
    required this.animations,
    required this.metaSize,
  });
}
// NEW FILE: lib/editor/plugins/texture_packer/texture_packer_asset_resolver.dart

import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/tab_metadata_notifier.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/project/project_settings_notifier.dart';
import 'package:path/path.dart' as p;

/// A centralized authority for resolving paths within a Texture Packer project.
///
/// This class ensures that all path conversions from file-relative (inside the .tpacker)
/// to project-relative (for the asset cache) are done consistently and canonically.
class TexturePackerPathResolver {
  /// Use a POSIX-style context to guarantee forward slashes ('/') as separators,
  /// ensuring cross-platform consistency for asset keys.
  static final _pathContext = p.Context(style: p.Style.posix);

  final String _projectRelativeTpackerPath;
  late final String _tpackerDirectory;

  /// Creates a resolver for a specific .tpacker file.
  ///
  /// [_projectRelativeTpackerPath] is the path of the .tpacker file relative
  /// to the project root, e.g., "atlases/characters.tpacker".
  TexturePackerPathResolver(this._projectRelativeTpackerPath) {
    // If the path is just a filename, its directory is the root ('.').
    // Otherwise, get the directory name. This handles files in the root gracefully.
    _tpackerDirectory = _pathContext.dirname(_projectRelativeTpackerPath);
  }

  /// Converts a path relative to the .tpacker file into a canonical path
  /// relative to the project root.
  ///
  /// This is the single source of truth for generating asset cache keys.
  ///
  /// For example:
  /// - tpacker path: "data/atlases/game.tpacker"
  /// - file-relative asset path: "../images/player.png"
  /// - returns: "data/images/player.png"
  String resolve(String fileRelativeAssetPath) {
    // Join the directory of the tpacker file with the asset's relative path.
    // This correctly handles segments like '..'
    final combinedPath = _pathContext.join(_tpackerDirectory, fileRelativeAssetPath);

    // Normalize the path to resolve any redundant segments (e.g., './' or '/../').
    // This produces the final, canonical project-relative path.
    return _pathContext.normalize(combinedPath);
  }
}

class TexturePackerAssetResolver {
  final Map<String, AssetData> _assets;
  
  // It now holds an instance of our new helper class.
  final TexturePackerPathResolver _pathResolver;

  TexturePackerAssetResolver(this._assets, this._pathResolver);
  
  ui.Image? getImage(String? sourcePath) {
    if (sourcePath == null || sourcePath.isEmpty) return null;

    // STEP 1: Use the helper to resolve the path to a canonical key.
    final canonicalKey = _pathResolver.resolve(sourcePath);
    
    // STEP 2: Look up the asset using that key.
    final asset = _assets[canonicalKey];

    if (asset is ImageAssetData) {
      return asset.image;
    }
    
    // If the asset is not found or is an error, this correctly returns null.
    return null;
  }
}

// Update the provider to create and inject both the helper and the main resolver.
final texturePackerAssetResolverProvider = Provider.family.autoDispose<AsyncValue<TexturePackerAssetResolver>, String>((ref, tabId) {
  final assetMapAsync = ref.watch(assetMapProvider(tabId));
  final repo = ref.watch(projectRepositoryProvider);
  final project = ref.watch(currentProjectProvider);
  final metadata = ref.watch(tabMetadataProvider)[tabId];

  return assetMapAsync.whenData((assetMap) {
    if (repo == null || project == null || metadata == null) {
      throw Exception("Project context not available for TexturePackerAssetResolver");
    }
    
    final tpackerPath = repo.fileHandler.getPathForDisplay(metadata.file.uri, relativeTo: project.rootUri);
    
    // Create an instance of our new helper.
    final pathResolver = TexturePackerPathResolver(tpackerPath);

    // Provide both the asset map and the new helper to the main resolver.
    return TexturePackerAssetResolver(assetMap, pathResolver);
  });
});
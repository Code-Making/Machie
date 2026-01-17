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
  final ProjectRepository _repo;
  final String _tpackerProjectRelativePath;
  late final String _tpackerDirectory;

  TexturePackerAssetResolver(this._assets, this._repo, this._tpackerProjectRelativePath) {
    // The plugin-specific logic of getting the directory from a file path
    // now lives solely within the resolver that needs it.
    _tpackerDirectory = _repo.fileHandler.getPathForDisplay(
      _repo.fileHandler.getParentUri(_tpackerProjectRelativePath),
    );

    // Handle root case
    if (_tpackerDirectory == _tpackerProjectRelativePath) {
      _tpackerDirectory = '.';
    }
  }

  String _resolve(String fileRelativeAssetPath) {
    // Now we call the corrected, unambiguous FileHandler method.
    return _repo.fileHandler.resolveRelativePath(_tpackerDirectory, fileRelativeAssetPath);
  }
  
  ui.Image? getImage(String? sourcePath) {
    if (sourcePath == null || sourcePath.isEmpty) return null;

    final canonicalKey = _resolve(sourcePath);
    final asset = _assets[canonicalKey];

    if (asset is ImageAssetData) {
      return asset.image;
    }
    return null;
  }
}

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
    
    // The provider now constructs the resolver with the repository and the tpacker file path.
    return TexturePackerAssetResolver(assetMap, repo, tpackerPath);
  });
});
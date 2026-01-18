// FILE: lib/editor/plugins/texture_packer/texture_packer_asset_resolver.dart

import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/tab_metadata_notifier.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/project/project_settings_notifier.dart';

// START OF CHANGES

/// Resolves asset paths and provides access to loaded asset data for the Texture Packer UI.
class TexturePackerAssetResolver {
  final Map<String, AssetData> _assets;
  final ProjectRepository _repo;
  final String _tpackerPath; // The project-relative path of the .tpacker file.

  TexturePackerAssetResolver(this._assets, this._repo, this._tpackerPath);
  
  /// Gets a loaded [ui.Image] for a given source path.
  ///
  /// The [sourcePath] is the raw, relative path as stored in the .tpacker file
  /// (e.g., "../images/player.png"). The resolver handles converting this to a
  /// canonical key to look up in the asset map.
  ui.Image? getImage(String? sourcePath) {
    if (sourcePath == null || sourcePath.isEmpty) return null;

    // Use the stored tpacker file path as the context to resolve the relative asset path.
    final canonicalKey = _repo.resolveRelativePath(_tpackerPath, sourcePath);
    final asset = _assets[canonicalKey];

    if (asset is ImageAssetData) {
      return asset.image;
    }
    return null;
  }
}

/// Provides an instance of [TexturePackerAssetResolver] for a given tab.
///
/// This provider handles wiring up the asset map and project context, so UI
/// widgets can simply ask the resolver for assets without needing to know
/// about the underlying data structures or path logic.
final texturePackerAssetResolverProvider = Provider.family.autoDispose<AsyncValue<TexturePackerAssetResolver>, String>((ref, tabId) {
  final assetMapAsync = ref.watch(assetMapProvider(tabId));
  final repo = ref.watch(projectRepositoryProvider);
  final project = ref.watch(currentProjectProvider);
  final metadata = ref.watch(tabMetadataProvider)[tabId];

  // The resolver is ready only when the asset map has finished loading.
  return assetMapAsync.whenData((assetMap) {
    if (repo == null || project == null || metadata == null) {
      throw Exception("Project context is not available for TexturePackerAssetResolver.");
    }
    
    // Determine the project-relative path for the .tpacker file.
    final tpackerPath = repo.fileHandler.getPathForDisplay(metadata.file.uri, relativeTo: project.rootUri);
    
    // Create the resolver with all necessary context.
    return TexturePackerAssetResolver(assetMap, repo, tpackerPath);
  });
});

// END OF CHANGES
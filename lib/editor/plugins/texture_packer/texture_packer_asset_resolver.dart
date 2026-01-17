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

class TexturePackerAssetResolver {
  final Map<String, AssetData> _assets;
  final ProjectRepository _repo;
  final String _tpackerDir;

  TexturePackerAssetResolver(this._assets, this._repo, String tpackerPath) 
    : _tpackerDir = p.dirname(tpackerPath);
  
  ui.Image? getImage(String? sourcePath) {
    if (sourcePath == null || sourcePath.isEmpty) return null;

    final canonicalKey = _repo.resolveRelativePath(_tpackerDir, sourcePath);
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
    return TexturePackerAssetResolver(assetMap, repo, tpackerPath);
  });
});
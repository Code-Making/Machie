// FILE: lib/editor/plugins/flow_graph/flow_graph_asset_resolver.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/tab_metadata_notifier.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/project/project_settings_notifier.dart';
import 'asset/flow_asset_models.dart';

class FlowGraphAssetResolver {
  final Map<String, AssetData> _assets;
  final ProjectRepository _repo;
  final String _fgPath; // project-relative path of the .fg file

  FlowGraphAssetResolver(this._assets, this._repo, this._fgPath);

  /// Resolves the linked schema data.
  FlowSchemaAssetData? getSchema(String? schemaRelativePath) {
    if (schemaRelativePath == null || schemaRelativePath.isEmpty) return null;
    
    final canonicalKey = _repo.resolveRelativePath(_fgPath, schemaRelativePath);
    final asset = _assets[canonicalKey];
    
    if (asset is FlowSchemaAssetData) {
      return asset;
    }
    return null;
  }
  
  // Future expansion: Resolve referenced Tiled Maps or Texture Packer files here
}

final flowGraphAssetResolverProvider = Provider.family.autoDispose<AsyncValue<FlowGraphAssetResolver>, String>((ref, tabId) {
  final assetMapAsync = ref.watch(assetMapProvider(tabId));
  final repo = ref.watch(projectRepositoryProvider);
  final project = ref.watch(currentProjectProvider);
  final metadata = ref.watch(tabMetadataProvider)[tabId];

  return assetMapAsync.whenData((assetMap) {
    if (repo == null || project == null || metadata == null) {
      throw Exception("Project context is not available for FlowGraphAssetResolver.");
    }
    
    final fgPath = repo.fileHandler.getPathForDisplay(metadata.file.uri, relativeTo: project.rootUri);
    return FlowGraphAssetResolver(assetMap, repo, fgPath);
  });
});
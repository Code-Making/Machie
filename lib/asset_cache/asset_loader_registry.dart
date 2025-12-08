import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/editor/plugins/editor_plugin_registry.dart';
import '../data/repositories/project/project_repository.dart';
import '../project/project_models.dart';
import 'core_asset_loaders.dart';

/// Provider that aggregates loaders from all registered EditorPlugins.
final assetLoaderRegistryProvider = Provider<AssetLoaderRegistry>((ref) {
  final plugins = ref.watch(activePluginsProvider);
  final loaders = plugins.expand((plugin) => plugin.assetLoaders).toList();
  // Add core loaders (like generic Image loader) here if they aren't in a plugin
  loaders.add(CoreImageAssetLoader()); 
  return AssetLoaderRegistry(loaders);
});

class AssetLoaderRegistry {
  final List<AssetLoader> _loaders;

  AssetLoaderRegistry(this._loaders);

  /// Finds the first loader that claims it can handle this file.
  AssetLoader? getLoader(ProjectDocumentFile file) {
    for (final loader in _loaders) {
      if (loader.canLoad(file)) {
        return loader;
      }
    }
    return null;
  }
}

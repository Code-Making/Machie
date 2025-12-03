// FILE: lib/project/services/project_asset_service.dart

import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/file_handler/file_handler.dart';
import '../../data/repositories/project/project_repository.dart';
import '../../editor/models/asset_models.dart';
import '../../editor/plugins/editor_plugin_registry.dart';
import '../../logs/logs_provider.dart';
import 'live_asset_registry_service.dart';

/// Provider for the stateless asset *loader*. Internal detail.
final _projectAssetLoaderServiceProvider =
    Provider.autoDispose<ProjectAssetLoaderService>((ref) {
  return ProjectAssetLoaderService(ref);
});

/// Provider family that loads an asset from disk and handles its lifecycle.
final diskAssetProvider =
    FutureProvider.autoDispose.family<AssetData, DocumentFile>((ref, assetFile) {
  // ... (Cache invalidation logic remains the same)
  final sub = ref.listen(fileOperationStreamProvider, (_, asyncEvent) {
    final event = asyncEvent.valueOrNull;
    if (event == null) return;
    bool shouldInvalidate = false;
    if ((event is FileDeleteEvent && event.deletedFile.uri == assetFile.uri) ||
        (event is FileRenameEvent && event.oldFile.uri == assetFile.uri)) {
      shouldInvalidate = true;
    }
    if (shouldInvalidate) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(() => sub.close());

  final loaderService = ref.watch(_projectAssetLoaderServiceProvider);
  return loaderService.load(assetFile);
});

/// The primary, public-facing provider that all consumers should use.
final effectiveAssetProvider =
    Provider.autoDispose.family<AsyncValue<AssetData>, DocumentFile>((ref, assetFile) {

  // Watch the entire live asset map.
  final liveAssets = ref.watch(liveAssetRegistryProvider);

  // Check if our specific asset is in the live map.
  final liveAsset = liveAssets[assetFile.uri];

  if (liveAsset != null) {
    // If it's live, return its state immediately, wrapped in AsyncData.
    // This is synchronous and highly efficient.
    return AsyncData(liveAsset);
  } else {
    // If not live, fall back to watching the disk-based FutureProvider.
    return ref.watch(diskAssetProvider(assetFile));
  }
});


// --- SERVICE IMPLEMENTATION ---

class ProjectAssetLoaderService {
  // ... (This class remains exactly the same as the previous version)
  final Ref _ref;
  late final Map<String, List<AssetDataProvider<AssetData>>> _providersByExtension;

  ProjectAssetLoaderService(this._ref) {
    _initializeProviders();
  }

  void _initializeProviders() {
    // ...
    final talker = _ref.read(talkerProvider);
    final allPlugins = _ref.read(activePluginsProvider);
    final providerMap = <String, List<AssetDataProvider<AssetData>>>{};
    for (final plugin in allPlugins) {
      for (final entry in plugin.assetDataProviders.entries) {
        final extension = entry.key.startsWith('.') ? entry.key : '.${entry.key}';
        providerMap.putIfAbsent(extension, () => []).add(entry.value);
      }
    }
    _providersByExtension = Map.unmodifiable(providerMap);
  }

  Future<AssetData> load(DocumentFile assetFile) async {
    try {
      final extension = p.extension(assetFile.name).toLowerCase();
      final providers = _providersByExtension[extension];

      if (providers == null || providers.isEmpty) {
        throw UnsupportedError('No provider for extension "$extension".');
      }

      final provider = providers.first;
      final bytes = await _ref.read(projectRepositoryProvider)!.fileHandler.readFileAsBytes(assetFile.uri);
      return await provider.parse(bytes, assetFile);
    } catch (e) {
      rethrow;
    }
  }
}
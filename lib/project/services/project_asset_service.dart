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

// --- SERVICE PROVIDER ---

/// A provider for the stateless asset *loader*. This is an internal detail.
final _projectAssetLoaderServiceProvider =
    Provider.autoDispose<ProjectAssetLoaderService>((ref) {
  return ProjectAssetLoaderService(ref);
});

// --- PUBLIC PROVIDERS ---

/// A provider family that loads an asset from disk and manages its lifecycle.
/// It is stateless from the caller's perspective but uses Riverpod's autoDispose
/// mechanism for caching and automatic disposal.
final diskAssetProvider =
    FutureProvider.autoDispose.family<AssetData, DocumentFile>((ref, assetFile) {
  
  // Set up cache invalidation.
  final sub = ref.listen(fileOperationStreamProvider, (_, asyncEvent) {
    final event = asyncEvent.valueOrNull;
    if (event == null) return;

    bool shouldInvalidate = false;
    if ((event is FileDeleteEvent && event.deletedFile.uri == assetFile.uri) ||
        (event is FileRenameEvent && event.oldFile.uri == assetFile.uri)) {
      shouldInvalidate = true;
    }
    // Future: Handle FileModifyEvent here as well.

    if (shouldInvalidate) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(() => sub.close());
  
  // Delegate loading to the stateless loader service.
  final loaderService = ref.watch(_projectAssetLoaderServiceProvider);
  return loaderService.load(assetFile);
});

/// The primary, public-facing provider that all consumers should use.
/// It intelligently returns the "live" version of an asset if it's being edited,
/// otherwise it falls back to the disk-based version.
final effectiveAssetProvider =
    Provider.autoDispose.family<AsyncValue<AssetData>, DocumentFile>((ref, assetFile) {
  final liveAssetRegistry = ref.watch(liveAssetRegistryProvider);
  final liveAssetNotifier = liveAssetRegistry.get(assetFile);

  if (liveAssetNotifier != null) {
    // If live, watch the notifier and return its state wrapped in AsyncData.
    final liveState = ref.watch(liveAssetNotifier);
    return AsyncData(liveState);
  } else {
    // If not live, watch the disk-based provider.
    return ref.watch(diskAssetProvider(assetFile));
  }
});


// --- SERVICE IMPLEMENTATION ---

/// A stateless service that can load and parse a file from disk using the
/// appropriate plugin-provided [AssetDataProvider].
class ProjectAssetLoaderService {
  final Ref _ref;
  late final Map<String, List<AssetDataProvider<AssetData>>> _providersByExtension;

  ProjectAssetLoaderService(this._ref) {
    _initializeProviders();
  }

  void _initializeProviders() {
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

  /// Loads and parses a single asset from disk, returning it wrapped in an AssetData subclass.
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
      // Re-throw to let the FutureProvider handle it and return AsyncError.
      rethrow;
    }
  }
}
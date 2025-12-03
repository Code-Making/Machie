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


/// A provider that serves the "effective" version of an asset.
///
/// It first checks the [LiveAssetRegistryService] to see if an editor has
/// "claimed" the asset for live editing.
/// - If YES, it watches the live [StateNotifier] for real-time updates.
/// - If NO, it falls back to the [ProjectAssetService] to load the static,
///   disk-cached version of the asset.
///
/// All parts of the app should use this provider to ensure they are always
/// viewing the most up-to-date version of an asset.
final effectiveAssetProvider =
    FutureProvider.autoDispose.family<AssetData, DocumentFile>((ref, assetFile) async {
  // 1. Check if there is a "live" version of this asset.
  final liveAssetRegistry = ref.watch(liveAssetRegistryProvider);
  final liveAssetNotifier = liveAssetRegistry.get(assetFile);

  if (liveAssetNotifier != null) {
    // If it's live, watch the notifier for real-time updates.
    // We use ref.watch on the notifier itself to rebuild when its state changes.
    return ref.watch(liveAssetNotifier.select((value) => value));
  } else {
    // If not live, fall back to the ProjectAssetService to load from disk.
    // Since this is a FutureProvider, we can directly await the result.
    final assetService = ref.watch(projectAssetServiceProvider);
    return await assetService.load(assetFile);
  }
});



/// A provider for the stateless asset *loader*.
/// This service's only job is to know how to load an asset from disk, without caching.
final projectAssetServiceProvider =
    Provider.autoDispose<ProjectAssetService>((ref) {
  return ProjectAssetService(ref);
});

/// A stateless service that can load and parse a file from disk using the
/// appropriate plugin-provided [AssetDataProvider].
class ProjectAssetService {
  final Ref _ref;

  late final Map<String, List<AssetDataProvider<AssetData>>>
      _assetProvidersByExtension;

  ProjectAssetService(this._ref) {
    _initializeProviders();
  }

  void _initializeProviders() {
    // ... (This logic remains the same as before)
    final talker = _ref.read(talkerProvider);
    final allPlugins = _ref.read(activePluginsProvider);
    final providerMap = <String, List<AssetDataProvider<AssetData>>>{};

    for (final plugin in allPlugins) {
      for (final entry in plugin.assetDataProviders.entries) {
        final extension =
            entry.key.startsWith('.') ? entry.key : '.${entry.key}';
        providerMap.putIfAbsent(extension, () => []).add(entry.value);
      }
    }
    _assetProvidersByExtension = Map.unmodifiable(providerMap);
  }

  /// Loads and parses a single asset from disk, returning it wrapped in an AssetData subclass.
  Future<AssetData> load(DocumentFile assetFile) async {
    try {
      final extension = p.extension(assetFile.name).toLowerCase();
      final providers = _assetProvidersByExtension[extension];

      if (providers == null || providers.isEmpty) {
        throw UnsupportedError('No provider for extension "$extension".');
      }

      // For simplicity, we'll use the first registered provider.
      // A more complex app could try multiple providers if the first fails.
      final provider = providers.first;

      final bytes =
          await _ref.read(projectRepositoryProvider)!.fileHandler.readFileAsBytes(assetFile.uri);
      final parsedData = await provider.parse(bytes, assetFile);
      return parsedData;
    } catch (e) {
      return ErrorAssetData(assetFile: assetFile, error: e);
    }
  }
}

/// A provider that serves the "effective" version of an asset.
///
/// This is the primary, public-facing provider that all consumers should use.
/// It automatically handles caching, invalidation, and live-editing overrides.
final effectiveAssetProvider =
    FutureProvider.autoDispose.family<AssetData, DocumentFile>((ref, assetFile) {

  // Set up cache invalidation by listening to file system events.
  final sub = ref.listen(fileOperationStreamProvider, (_, asyncEvent) {
    final event = asyncEvent.valueOrNull;
    if (event == null) return;

    bool shouldInvalidate = false;
    if (event is FileDeleteEvent && event.deletedFile.uri == assetFile.uri) {
      shouldInvalidate = true;
    } else if (event is FileRenameEvent && event.oldFile.uri == assetFile.uri) {
      shouldInvalidate = true;
    }
    // A future `FileModifyEvent` would also be handled here.

    if (shouldInvalidate) {
      ref.invalidateSelf();
    }
  });

  // Clean up the listener when the provider is disposed.
  ref.onDispose(() => sub.close());

  // Check the live registry first.
  final liveAssetRegistry = ref.watch(liveAssetRegistryProvider);
  final liveAssetNotifier = liveAssetRegistry.get(assetFile);

  if (liveAssetNotifier != null) {
    // If it's live, watch the notifier's state directly.
    // This creates a reactive link: when the notifier updates, this provider re-runs.
    return ref.watch(liveAssetNotifier);
  } else {
    // If not live, fall back to the stateless loader service.
    // The FutureProvider handles the async state (loading/data/error) for us.
    final assetService = ref.watch(projectAssetServiceProvider);
    return assetService.load(assetFile);
  }
});
// FILE: lib/project/services/live_asset_registry_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/file_handler/file_handler.dart';
import '../../editor/models/asset_models.dart';
import '../../logs/logs_provider.dart';
import 'project_asset_service.dart'; // We need this for the invalidate call

/// A project-scoped provider for the live asset registry.
final liveAssetRegistryProvider =
    Provider.autoDispose<LiveAssetRegistryService>((ref) {
  final service = LiveAssetRegistryService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// A service that manages a registry of "live" assets currently open for editing.
class LiveAssetRegistryService {
  final Ref _ref;
  final Map<String, LiveAsset<AssetData>> _liveAssets = {};

  LiveAssetRegistryService(this._ref);

  LiveAsset<T> claim<T extends AssetData>(T initialAssetData) {
    final uri = initialAssetData.assetFile.uri;
    if (_liveAssets.containsKey(uri)) {
      throw StateError('Asset at $uri is already claimed for live editing.');
    }

    final liveAsset = LiveAsset<T>(initialAssetData);
    _liveAssets[uri] = liveAsset;
    _ref.read(talkerProvider).info('Live Asset claimed: $uri');
    return liveAsset;
  }

  void release(DocumentFile assetFile) {
    final uri = assetFile.uri;
    if (_liveAssets.containsKey(uri)) {
      _liveAssets.remove(uri);
      _ref.read(talkerProvider).info('Live Asset released: $uri');

      // CORRECTED: Invalidate the effectiveAssetProvider for this specific file.
      // This tells Riverpod to destroy its state, forcing any listeners to
      // re-evaluate and switch back to the disk-based version.
      _ref.invalidate(effectiveAssetProvider(assetFile));
    }
  }

  LiveAsset<AssetData>? get(DocumentFile assetFile) {
    return _liveAssets[assetFile.uri];
  }

  void dispose() {
    _liveAssets.clear();
  }
}
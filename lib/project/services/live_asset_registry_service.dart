// FILE: lib/project/services/live_asset_registry_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/file_handler/file_handler.dart';
import '../../editor/models/asset_models.dart';
import '../../logs/logs_provider.dart';

/// A project-scoped provider for the live asset registry.
final liveAssetRegistryProvider =
    Provider.autoDispose<LiveAssetRegistryService>((ref) {
  final service = LiveAssetRegistryService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

/// A service that manages a registry of "live" assets currently open for editing.
///
/// This service allows an editor to "claim" an asset, providing a [LiveAsset]
/// notifier that can be updated. Other parts of the app can then listen to this
/// live version instead of the static, disk-cached version.
class LiveAssetRegistryService {
  final Ref _ref;

  /// The internal registry mapping a file's URI to its corresponding LiveAsset notifier.
  final Map<String, LiveAsset<AssetData>> _liveAssets = {};

  LiveAssetRegistryService(this._ref);

  /// "Claims" an asset for live editing.
  ///
  /// An editor calls this method when it opens an asset. The service creates
  /// a [LiveAsset] notifier, registers it, and returns it to the editor.
  /// Throws if the asset is already claimed.
  LiveAsset<T> claim<T extends AssetData>(T initialAssetData) {
    final uri = initialAssetData.assetFile.uri;
    if (_liveAssets.containsKey(uri)) {
      // This scenario should ideally be prevented by app logic (e.g., not opening the same file twice).
      throw StateError('Asset at $uri is already claimed for live editing.');
    }

    final liveAsset = LiveAsset<T>(initialAssetData);
    _liveAssets[uri] = liveAsset;
    _ref.read(talkerProvider).info('Live Asset claimed: $uri');
    return liveAsset;
  }

  /// Releases a "claimed" asset, returning it to a static state.
  ///
  /// An editor calls this in its dispose method.
  void release(DocumentFile assetFile) {
    final uri = assetFile.uri;
    if (_liveAssets.containsKey(uri)) {
      _liveAssets.remove(uri);
      _ref.read(talkerProvider).info('Live Asset released: $uri');
      
      // Invalidate the effective provider to force consumers to switch back
      // to the disk-based version.
      _ref.invalidate(effectiveAssetProvider(assetFile));
    }
  }

  /// Retrieves a live asset notifier if one is registered for the given file.
  /// Returns null if the asset is not currently "live".
  LiveAsset<AssetData>? get(DocumentFile assetFile) {
    return _liveAssets[assetFile.uri];
  }

  void dispose() {
    _liveAssets.clear();
  }
}
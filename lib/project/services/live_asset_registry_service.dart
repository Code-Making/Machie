// FILE: lib/project/services/live_asset_registry_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/file_handler/file_handler.dart';
import '../../editor/models/asset_models.dart';
import '../../logs/logs_provider.dart';

/// The provider for our new StateNotifier. It holds the state of all live assets.
final liveAssetRegistryProvider = StateNotifierProvider.autoDispose<
    LiveAssetRegistry, Map<String, AssetData>>((ref) {
  return LiveAssetRegistry(ref);
});

/// A StateNotifier that manages a map of "live" assets currently open for editing.
///
/// Instead of a complex service with "claim" methods, editors now simply "update"
/// this notifier's state. This is a more direct and idiomatic Riverpod pattern.
class LiveAssetRegistry extends StateNotifier<Map<String, AssetData>> {
  final Ref _ref;
  LiveAssetRegistry(this._ref) : super({});

  /// Called by an editor to register or update a live asset.
  void updateAsset(AssetData assetData) {
    final uri = assetData.assetFile.uri;
    state = {...state, uri: assetData};
    _ref.read(talkerProvider).info('Live Asset updated: $uri');
  }

  /// Called by an editor in its dispose method to release the asset.
  void releaseAsset(DocumentFile assetFile) {
    final uri = assetFile.uri;
    if (state.containsKey(uri)) {
      state = Map.from(state)..remove(uri);
      _ref.read(talkerProvider).info('Live Asset released: $uri');
    }
  }
}
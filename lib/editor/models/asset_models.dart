import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../../data/file_handler/file_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // <-- ADD IMPORT

/// The abstract base class for all loaded asset data.
///
/// It contains the common properties: the file it was loaded from and
/// a potential error state.
@immutable
abstract class AssetData {
  /// The DocumentFile instance for which this asset was loaded.
  final DocumentFile assetFile;

  /// The error or exception object if loading or parsing failed. Null on success.
  final Object? error;

  const AssetData({required this.assetFile, this.error});

  /// A convenience getter to check if the asset loading failed.
  bool get hasError => error != null;
}

/// A concrete implementation of [AssetData] for successfully loaded image assets.
class ImageAssetData extends AssetData {
  /// The successfully decoded image data.
  final ui.Image data;

  ImageAssetData({
    required DocumentFile assetFile,
    required this.data,
  }) : super(assetFile: assetFile);
}

/// A concrete implementation of [AssetData] for successfully loaded text assets.
class TextAssetData extends AssetData {
  /// The successfully decoded string content.
  final String data;

  TextAssetData({
    required DocumentFile assetFile,
    required this.data,
  }) : super(assetFile: assetFile);
}

/// A generic implementation of [AssetData] to represent a loading failure.
///
/// This allows consumers to handle errors consistently without needing to know
/// the specific type of asset that was expected.
class ErrorAssetData extends AssetData {
  ErrorAssetData({
    required DocumentFile assetFile,
    required Object error,
  }) : super(assetFile: assetFile, error: error);
}

/// A placeholder implementation of [AssetData] to represent the loading state.
///
/// This can be used by providers to signal to the UI that an asset is currently
/// being fetched, similar to Riverpod's `AsyncLoading`.
class LoadingAssetData extends AssetData {
  LoadingAssetData({required DocumentFile assetFile})
      : super(assetFile: assetFile);
}


/// Defines the contract for a class that can parse raw byte data
/// into a specific, concrete subclass of [AssetData].
abstract class AssetDataProvider<T extends AssetData> {
  /// Asynchronously parses the raw [bytes] of a file and wraps the result
  /// in a specific [AssetData] subclass (e.g., [ImageAssetData]).
  ///
  /// This method should throw an exception if parsing fails, which will be
  /// caught by the asset service.
  Future<T> parse(Uint8List bytes, DocumentFile assetFile);
}


/// A StateNotifier that holds an AssetData instance, allowing it to be
/// updated in real-time by an editor and watched by other consumers.
class LiveAsset<T extends AssetData> extends StateNotifier<T> {
  LiveAsset(super.initialState);

  /// Called by the owning editor to push a new version of the asset data.
  void update(T newState) {
    if (mounted) {
      state = newState;
    }
  }
}
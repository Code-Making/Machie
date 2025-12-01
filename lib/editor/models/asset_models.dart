import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../data/file_handler/file_handler.dart'; // <-- ADD THIS IMPORT

/// A wrapper for a loaded asset that clearly indicates success or failure.
///
/// This prevents returning null or throwing exceptions across service boundaries,
/// allowing callers to gracefully handle cases where an asset fails to load.
@immutable
class AssetData<T> {
  /// The successfully loaded and parsed asset data. Null if there was an error.
  final T? data;

  /// The error or exception object if loading or parsing failed. Null on success.
  final Object? error;

  /// The DocumentFile instance for which this asset was loaded.
  final DocumentFile assetFile;

  /// Creates a success result with the loaded asset [data].
  const AssetData.success(this.data, this.assetFile) : error = null;

  /// Creates an error result with the [error] object.
  const AssetData.error(this.error, this.assetFile) : data = null;

  /// A convenience getter to check if the asset loading failed.
  bool get hasError => error != null;
}

/// Defines the contract for a class that can parse raw byte data
/// into a specific, usable asset type [T].
///
/// Each plugin that introduces a new shareable asset type (like images,
/// 3D models, sound files, etc.) will provide an implementation of this
/// interface for each file extension it supports.
abstract class AssetDataProvider<T> {
  /// Asynchronously parses the raw [bytes] of a file into an object of type [T].
  ///
  /// This method should throw an exception if parsing fails, which will be
  /// caught by the `ProjectAssetCacheService` and wrapped in an [AssetData.error].
  Future<T> parse(Uint8List bytes);
}
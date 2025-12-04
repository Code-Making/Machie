// lib/asset_cache/asset_models.dart
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// A sealed class representing the state of a cached asset.
@immutable
sealed class AssetData {
  const AssetData();
}

/// Represents a successfully loaded and decoded image asset.
class ImageAssetData extends AssetData {
  final ui.Image image;
  const ImageAssetData({required this.image});
}

/// Represents an asset that failed to load.
class ErrorAssetData extends AssetData {
  final Object error;
  final StackTrace? stackTrace;
  const ErrorAssetData({required this.error, this.stackTrace});
}
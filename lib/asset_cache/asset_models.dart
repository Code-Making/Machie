// lib/asset_cache/asset_models.dart
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/project/project_repository.dart';
import '../project/project_models.dart';
import 'package:machine/data/file_handler/file_handler.dart';

/// A sealed class representing the state of a cached asset.
@immutable
abstract class AssetData {
  const AssetData();
  
  bool get hasError => this is ErrorAssetData;
}

abstract class AssetLoader<T extends AssetData> {
  /// Returns true if this loader can handle the file (e.g. based on extension).
  bool canLoad(ProjectDocumentFile file);

  /// Loads and decodes the asset.
  /// [ref] is provided to access other providers/services if needed.
  /// For dependent assets, this method is called *after* its dependencies
  /// (declared via IDependentAssetLoader) have been successfully loaded.
  Future<T> load(Ref ref, ProjectDocumentFile file, ProjectRepository repo);
}

/// A mixin for AssetLoaders that depend on other assets.
///
/// This allows the asset system to reactively reload this asset when one of
/// its dependencies changes.
mixin IDependentAssetLoader on AssetLoader<AssetData> {
  /// Parses the given file to discover its asset dependencies.
  ///
  /// Returns a set of project-relative URIs that this asset needs to load.
  /// This method is called before `load`.
  Future<Set<String>> getDependencies(Ref ref, ProjectDocumentFile file, ProjectRepository repo);
}

/// Represents an asset that failed to load.
class ErrorAssetData extends AssetData {
  final Object error;
  final StackTrace? stackTrace;
  const ErrorAssetData({required this.error, this.stackTrace});
}

class ImageAssetData extends AssetData {
  final ui.Image image;
  const ImageAssetData({required this.image});
}
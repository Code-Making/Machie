// lib/asset_cache/asset_models.dart
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/project/project_repository.dart';
import '../project/project_models.dart';

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
  Future<T> load(Ref ref, ProjectDocumentFile file, ProjectRepository repo);
}
/// Represents an asset that failed to load.
class ErrorAssetData extends AssetData {
  final Object error;
  final StackTrace? stackTrace;
  const ErrorAssetData({required this.error, this.stackTrace});
}
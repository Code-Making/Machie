import 'dart:ui' as ui;
import 'package:equatable/equatable.dart';

/// Uniquely identifies a specific slice of an image file.
class ExportableAssetId extends Equatable {
  final String sourcePath; // Project-relative path to the source image (e.g. "assets/dungeon.png")
  final int x;
  final int y;
  final int width;
  final int height;

  const ExportableAssetId({
    required this.sourcePath,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  @override
  List<Object?> get props => [sourcePath, x, y, width, height];

  @override
  String toString() => '$sourcePath [${x},${y} ${width}x${height}]';
}

/// The payload containing the actual image data needed for packing.
class ExportableAsset {
  final ExportableAssetId id;
  final ui.Image image; // The full source image (or a cropped version if optimized later)
  final ui.Rect sourceRect; // The specific area in the image to pack

  ExportableAsset({
    required this.id,
    required this.image,
    required this.sourceRect,
  });
}

/// Interface for any class that can scan a file and produce assets.
abstract class AssetProcessor {
  /// Returns true if this processor handles the given file extension/type.
  bool canHandle(String filePath);

  /// Scans the file, resolves dependencies, and returns all unique image slices used.
  Future<List<ExportableAsset>> collect(String projectRelativePath);
}
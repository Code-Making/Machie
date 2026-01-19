import 'dart:ui' as ui;
import 'dart:typed_data';
import '../models.dart'; // From Phase 1

/// Where a specific asset ended up in the atlas.
class AtlasLocation {
  final int pageIndex; // Which atlas page (image) contains this asset
  final ui.Rect packedRect; // The X,Y,W,H in the destination atlas
  final bool rotated; // If rotation was applied (usually false for tilemaps)

  AtlasLocation({
    required this.pageIndex,
    required this.packedRect,
    this.rotated = false,
  });
}

/// A single generated atlas page (texture).
class AtlasPage {
  final int index;
  final int width;
  final int height;
  final Uint8List imageBytes; // The PNG bytes of the generated atlas
  final ui.Image? imageObject; // Kept for preview/debug, optional

  AtlasPage({
    required this.index,
    required this.width,
    required this.height,
    required this.imageBytes,
    this.imageObject,
  });
}

/// The final result of the packing process.
class PackedAtlasResult {
  /// The generated texture pages.
  final List<AtlasPage> pages;

  /// The lookup table: Input ID -> New Location.
  /// This is what the re-writers use to update GIDs and JSON paths.
  final Map<ExportableAssetId, AtlasLocation> lookup;

  PackedAtlasResult({
    required this.pages,
    required this.lookup,
  });
}
// FILE: lib/editor/plugins/tiled_editor/data/tiled_asset_providers.dart

import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../../../data/file_handler/file_handler.dart';
import '../../../models/asset_models.dart';

/// An asset provider that can parse a byte stream into an [ImageAssetData] object.
///
/// This is used by the Tiled plugin to handle tileset and image layer sources.
class TiledImageProvider implements AssetDataProvider<ImageAssetData> {
  @override
  Future<ImageAssetData> parse(
    Uint8List bytes,
    DocumentFile assetFile,
  ) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return ImageAssetData(
      assetFile: assetFile,
      data: frame.image,
    );
  }
}
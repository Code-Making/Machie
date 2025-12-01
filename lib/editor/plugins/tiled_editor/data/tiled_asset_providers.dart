import 'dart:typed_data';
import 'dart:ui' as ui;
import '../../../models/asset_models.dart';

/// An asset provider that can parse a byte stream into a `ui.Image` object.
///
/// This is used by the Tiled plugin to handle tileset and image layer sources.
class TiledImageProvider implements AssetDataProvider<ui.Image> {
  @override
  Future<ui.Image> parse(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}
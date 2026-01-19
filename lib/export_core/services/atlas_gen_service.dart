import 'dart:async';
import 'dart:ui' as ui; // Fixed: Aliased import
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../packer/packer_models.dart';
import '../packer/max_rects_packer.dart';

final atlasGenServiceProvider = Provider((ref) => AtlasGenService());

class AtlasGenService {
  Future<PackedAtlasResult> generateAtlas(
    List<ExportableAsset> assets, {
    int maxPageWidth = 2048,
    int maxPageHeight = 2048,
    int padding = 2,
  }) async {
    final packerInputs = assets.map((asset) => PackerInput(
      data: asset,
      width: asset.sourceRect.width.toInt(),
      height: asset.sourceRect.height.toInt(),
    )).toList();

    final packer = MaxRectsPacker(
      maxWidth: maxPageWidth,
      maxHeight: maxPageHeight,
      padding: padding,
    );
    
    final packedItems = packer.pack(packerInputs);

    final Map<int, List<PackerOutput>> pageMap = {};
    int maxPageIndex = 0;

    for (final item in packedItems) {
      pageMap.putIfAbsent(item.pageIndex, () => []).add(item);
      if (item.pageIndex > maxPageIndex) maxPageIndex = item.pageIndex;
    }

    final List<AtlasPage> generatedPages = [];
    final Map<ExportableAssetId, AtlasLocation> lookupMap = {};

    for (int i = 0; i <= maxPageIndex; i++) {
      if (!pageMap.containsKey(i)) continue;

      final itemsInPage = pageMap[i]!;
      final pageData = await _drawPage(itemsInPage, maxPageWidth, maxPageHeight);
      generatedPages.add(pageData);

      for (final item in itemsInPage) {
        final asset = item.data as ExportableAsset;
        lookupMap[asset.id] = AtlasLocation(
          pageIndex: i,
          packedRect: item.rect,
          rotated: false,
        );
      }
    }

    return PackedAtlasResult(pages: generatedPages, lookup: lookupMap);
  }

  Future<AtlasPage> _drawPage(List<PackerOutput> items, int width, int height) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    
    // Fixed: Use ui.Color and ui.BlendMode
    canvas.drawColor(const ui.Color(0x00000000), ui.BlendMode.src);

    // Fixed: Use ui.Paint and ui.FilterQuality
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.none;

    for (final item in items) {
      final asset = item.data as ExportableAsset;
      
      canvas.drawImageRect(
        asset.image, 
        asset.sourceRect, 
        item.rect, 
        paint
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception("Failed to encode atlas image");

    return AtlasPage(
      index: items.first.pageIndex,
      width: width,
      height: height,
      imageBytes: byteData.buffer.asUint8List(),
      imageObject: image,
    );
  }
}
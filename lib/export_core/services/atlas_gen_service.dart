import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../packer/packer_models.dart';
import '../packer/max_rects_packer.dart';

final atlasGenServiceProvider = Provider((ref) => AtlasGenService());

class AtlasGenService {
  /// Core function to turn a list of assets into generated Atlas data.
  Future<PackedAtlasResult> generateAtlas(
    List<ExportableAsset> assets, {
    int maxPageWidth = 2048,
    int maxPageHeight = 2048,
    int padding = 2,
  }) async {
    // 1. Prepare inputs for algorithm
    final packerInputs = assets.map((asset) => PackerInput(
      data: asset,
      width: asset.sourceRect.width.toInt(),
      height: asset.sourceRect.height.toInt(),
    )).toList();

    // 2. Run Packing Algorithm
    final packer = MaxRectsPacker(
      maxWidth: maxPageWidth,
      maxHeight: maxPageHeight,
      padding: padding,
    );
    
    // Note: this is synchronous math, usually fast enough for <1000 items. 
    // For massive sets, compute() could be used here.
    final packedItems = packer.pack(packerInputs);

    // 3. Organize by Page Index
    final Map<int, List<PackerOutput>> pageMap = {};
    int maxPageIndex = 0;

    for (final item in packedItems) {
      pageMap.putIfAbsent(item.pageIndex, () => []).add(item);
      if (item.pageIndex > maxPageIndex) maxPageIndex = item.pageIndex;
    }

    // 4. Draw Pages (Async Image Generation)
    final List<AtlasPage> generatedPages = [];
    final Map<ExportableAssetId, AtlasLocation> lookupMap = {};

    for (int i = 0; i <= maxPageIndex; i++) {
      if (!pageMap.containsKey(i)) continue; // Should not happen with current algo logic

      final itemsInPage = pageMap[i]!;
      
      // Calculate actual trimming size (optional optimization to not save empty space)
      // For now, we use the full POT size or a fixed size defined by maxPageWidth
      // but let's just stick to maxPageWidth for simplicity of UV calc.
      
      final pageData = await _drawPage(itemsInPage, maxPageWidth, maxPageHeight);
      generatedPages.add(pageData);

      // Populate lookup map
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
    
    // Transparent background
    canvas.drawColor(const Color(0x00000000), BlendMode.src);

    final paint = Paint()..filterQuality = FilterQuality.none; // Pixel Art crispness

    for (final item in items) {
      final asset = item.data as ExportableAsset;
      
      // Draw the slice from the source image to the destination rect
      canvas.drawImageRect(
        asset.image, 
        asset.sourceRect, 
        item.rect, 
        paint
      );
    }

    final picture = recorder.endRecording();
    
    // Convert to Image
    final image = await picture.toImage(width, height);
    
    // Convert to ByteData (PNG)
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception("Failed to encode atlas image");

    return AtlasPage(
      index: items.first.pageIndex,
      width: width,
      height: height,
      imageBytes: byteData.buffer.asUint8List(),
      imageObject: image, // Optional: Keep logic simple, allow garbage collection if not needed
    );
  }
}
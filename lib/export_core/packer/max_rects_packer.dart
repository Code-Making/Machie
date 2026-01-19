import 'dart:math' as math;
import 'dart:ui';

class PackerInput {
  final Object data; // The ExportableAsset
  final int width;
  final int height;

  PackerInput({required this.data, required this.width, required this.height});
}

class PackerOutput {
  final Object data;
  final int pageIndex;
  final Rect rect;

  PackerOutput({required this.data, required this.pageIndex, required this.rect});
}

class MaxRectsPacker {
  final int maxWidth;
  final int maxHeight;
  final int padding;

  // State for the current page being packed
  List<Rect> _freeRects = [];
  int _currentPageIndex = 0;
  
  // Results
  final List<PackerOutput> _packedItems = [];

  MaxRectsPacker({
    this.maxWidth = 2048,
    this.maxHeight = 2048,
    this.padding = 2,
  });

  List<PackerOutput> pack(List<PackerInput> items) {
    _packedItems.clear();
    _currentPageIndex = 0;
    _initPage();

    // Sort by height descending (heuristic for better packing)
    // We clone the list to not affect the original order reference if needed elsewhere
    final sortedItems = List<PackerInput>.from(items);
    sortedItems.sort((a, b) => b.height.compareTo(a.height));

    for (final item in sortedItems) {
      _packItem(item);
    }

    return _packedItems;
  }

  void _initPage() {
    _freeRects.clear();
    _freeRects.add(Rect.fromLTWH(0, 0, maxWidth.toDouble(), maxHeight.toDouble()));
  }

  void _packItem(PackerInput item) {
    final w = item.width + padding;
    final h = item.height + padding;

    Rect? bestNode;
    int bestShortSideFit = 0x7FFFFFFF;
    int bestNodeIndex = -1;

    // 1. Try to find a place in current page
    for (int i = 0; i < _freeRects.length; i++) {
      final free = _freeRects[i];
      if (free.width >= w && free.height >= h) {
        final leftoverHoriz = (free.width - w).abs().toInt();
        final leftoverVert = (free.height - h).abs().toInt();
        final shortSideFit = math.min(leftoverHoriz, leftoverVert);

        if (shortSideFit < bestShortSideFit) {
          bestNode = Rect.fromLTWH(free.left, free.top, w.toDouble(), h.toDouble());
          bestShortSideFit = shortSideFit;
          bestNodeIndex = i;
        }
      }
    }

    // 2. If valid, place it
    if (bestNode != null) {
      _placeRect(bestNode);
      _packedItems.add(PackerOutput(
        data: item.data,
        pageIndex: _currentPageIndex,
        // Remove padding from final output rect
        rect: Rect.fromLTWH(
          bestNode.left, 
          bestNode.top, 
          item.width.toDouble(), 
          item.height.toDouble()
        ),
      ));
    } else {
      // 3. If doesn't fit, create new page and retry
      _currentPageIndex++;
      _initPage();
      _packItem(item); // Recursive retry on empty page
    }
  }

  void _placeRect(Rect rect) {
    final count = _freeRects.length;
    for (int i = 0; i < count; i++) {
      if (_splitFreeNode(_freeRects[i], rect)) {
        _freeRects.removeAt(i);
        i--;
      }
    }
    _pruneFreeList();
  }

  bool _splitFreeNode(Rect freeNode, Rect usedNode) {
    if (!freeNode.overlaps(usedNode)) return false;

    if (usedNode.left < freeNode.right && usedNode.right > freeNode.left) {
      // New node at the top side of the used node
      if (usedNode.top > freeNode.top && usedNode.top < freeNode.bottom) {
        _freeRects.add(Rect.fromLTWH(
            freeNode.left, freeNode.top, freeNode.width, usedNode.top - freeNode.top));
      }
      // New node at the bottom side of the used node
      if (usedNode.bottom < freeNode.bottom) {
        _freeRects.add(Rect.fromLTWH(
            freeNode.left, usedNode.bottom, freeNode.width, freeNode.bottom - usedNode.bottom));
      }
    }

    if (usedNode.top < freeNode.bottom && usedNode.bottom > freeNode.top) {
      // New node at the left side of the used node
      if (usedNode.left > freeNode.left && usedNode.left < freeNode.right) {
        _freeRects.add(Rect.fromLTWH(
            freeNode.left, freeNode.top, usedNode.left - freeNode.left, freeNode.height));
      }
      // New node at the right side of the used node
      if (usedNode.right < freeNode.right) {
        _freeRects.add(Rect.fromLTWH(
            usedNode.right, freeNode.top, freeNode.right - usedNode.right, freeNode.height));
      }
    }
    return true;
  }

  void _pruneFreeList() {
    for (int i = 0; i < _freeRects.length; i++) {
      for (int j = i + 1; j < _freeRects.length; j++) {
        if (_isContained(_freeRects[i], _freeRects[j])) {
          _freeRects.removeAt(i);
          i--;
          break;
        }
        if (_isContained(_freeRects[j], _freeRects[i])) {
          _freeRects.removeAt(j);
          j--;
        }
      }
    }
  }

  bool _isContained(Rect a, Rect b) {
    return a.left >= b.left && a.top >= b.top && a.right <= b.right && a.bottom <= b.bottom;
  }
}
import 'dart:math';

class PackerInputItem<T> {
  final double width;
  final double height;
  final T data;

  PackerInputItem({
    required this.width,
    required this.height,
    required this.data,
  });
}

class PackerOutputItem<T> {
  final double x;
  final double y;
  final double width;
  final double height;
  final T data;

  PackerOutputItem({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.data,
  });
}

class TexturePackerResult<T> {
  final double width;
  final double height;
  final List<PackerOutputItem<T>> items;

  TexturePackerResult({
    required this.width,
    required this.height,
    required this.items,
  });
}

/// A simplified MaxRects packer implementation (Best Short Side Fit).
class MaxRectsPacker {
  final int maxWidth;
  final int maxHeight;
  final bool allowRotation;
  final int padding;

  final List<Rectangle<int>> _freeRects = [];
  
  MaxRectsPacker({
    this.maxWidth = 2048,
    this.maxHeight = 2048,
    this.allowRotation = false,
    this.padding = 0,
  });

  TexturePackerResult<T> pack<T>(List<PackerInputItem<T>> items) {
    // 1. Sort items by max side (heuristic for better fit)
    items.sort((a, b) => max(b.width, b.height).compareTo(max(a.width, a.height)));

    _freeRects.clear();
    _freeRects.add(Rectangle(0, 0, maxWidth, maxHeight));

    final List<PackerOutputItem<T>> packedItems = [];
    
    // Track actual bounds used
    double usedWidth = 0;
    double usedHeight = 0;

    for (final item in items) {
      final w = item.width.ceil() + padding;
      final h = item.height.ceil() + padding;
      
      final node = _findBestNode(w, h);
      
      if (node != null) {
        // Place the rect
        final int placedX = node.left;
        final int placedY = node.top;
        
        // Split free rects
        _splitFreeNode(Rectangle(placedX, placedY, w, h));
        
        // Remove padding from output
        packedItems.add(PackerOutputItem(
          x: placedX.toDouble(),
          y: placedY.toDouble(),
          width: item.width,
          height: item.height,
          data: item.data,
        ));

        usedWidth = max(usedWidth, placedX + w.toDouble());
        usedHeight = max(usedHeight, placedY + h.toDouble());
      } else {
        // Could not fit item. For now, we just skip it or throw.
        // In a production app, we might grow the atlas or start a second page.
        print('Warning: Could not fit item of size ${item.width}x${item.height} in atlas.');
      }
    }

    return TexturePackerResult(
      width: _nextPowerOfTwo(usedWidth),
      height: _nextPowerOfTwo(usedHeight),
      items: packedItems,
    );
  }

  Rectangle<int>? _findBestNode(int w, int h) {
    Rectangle<int>? bestNode;
    int bestShortSideFit = 0x7FFFFFFF;
    int bestLongSideFit = 0x7FFFFFFF;

    for (final freeRect in _freeRects) {
      // Try to place the rect in freeRect
      if (freeRect.width >= w && freeRect.height >= h) {
        final leftoverX = (freeRect.width - w).abs();
        final leftoverY = (freeRect.height - h).abs();
        final shortSideFit = min(leftoverX, leftoverY);
        final longSideFit = max(leftoverX, leftoverY);

        if (shortSideFit < bestShortSideFit || (shortSideFit == bestShortSideFit && longSideFit < bestLongSideFit)) {
          bestNode = Rectangle(freeRect.left, freeRect.top, w, h);
          bestShortSideFit = shortSideFit;
          bestLongSideFit = longSideFit;
        }
      }
      // Rotation logic would go here
    }
    return bestNode;
  }

  void _splitFreeNode(Rectangle<int> usedNode) {
    final List<Rectangle<int>> newFreeRects = [];
    
    for (final freeRect in _freeRects) {
      if (!_intersects(freeRect, usedNode)) {
        newFreeRects.add(freeRect);
        continue;
      }

      // New node at the top side of the used node
      if (usedNode.top < freeRect.top + freeRect.height && usedNode.top + usedNode.height > freeRect.top) {
        // New node at the right side of the used node
        if (usedNode.left > freeRect.left && usedNode.left < freeRect.left + freeRect.width) {
          newFreeRects.add(Rectangle(
            freeRect.left, 
            freeRect.top, 
            usedNode.left - freeRect.left, 
            freeRect.height
          ));
        }
        // New node at the left side of the used node
        if (usedNode.left + usedNode.width < freeRect.left + freeRect.width) {
          newFreeRects.add(Rectangle(
            usedNode.left + usedNode.width,
            freeRect.top,
            freeRect.left + freeRect.width - (usedNode.left + usedNode.width),
            freeRect.height
          ));
        }
      }

      if (usedNode.left < freeRect.left + freeRect.width && usedNode.left + usedNode.width > freeRect.left) {
        // New node at the bottom side of the used node
        if (usedNode.top > freeRect.top && usedNode.top < freeRect.top + freeRect.height) {
          newFreeRects.add(Rectangle(
            freeRect.left,
            freeRect.top,
            freeRect.width,
            usedNode.top - freeRect.top
          ));
        }
        // New node at the top side of the used node
        if (usedNode.top + usedNode.height < freeRect.top + freeRect.height) {
          newFreeRects.add(Rectangle(
            freeRect.left,
            usedNode.top + usedNode.height,
            freeRect.width,
            freeRect.top + freeRect.height - (usedNode.top + usedNode.height)
          ));
        }
      }
    }
    
    _freeRects.clear();
    // Prune tiny rects or contained rects
    for(final rect in newFreeRects) {
      // Simple containment check optimization could go here
      _freeRects.add(rect);
    }
  }

  bool _intersects(Rectangle<int> a, Rectangle<int> b) {
    return a.left < b.left + b.width &&
           a.left + a.width > b.left &&
           a.top < b.top + b.height &&
           a.top + a.height > b.top;
  }

  double _nextPowerOfTwo(double v) {
    int val = v.ceil();
    int power = 1;
    while (power < val) power *= 2;
    return power.toDouble();
  }
}
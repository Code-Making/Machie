// lib/plugins/glitch_editor/glitch_editor_math.dart
import 'package:flutter/material.dart';

/// Transforms a point from a widget's local coordinate space to the
/// coordinate space of the source image, accounting for `BoxFit.contain`.
Offset transformPointToImageCoordinates({
  required Offset localPoint,
  required Size widgetSize,
  required Size imageSize,
}) {
  final fittedSizes = applyBoxFit(BoxFit.contain, imageSize, widgetSize);
  final destinationRect = Alignment.center.inscribe(fittedSizes.destination, Rect.fromLTWH(0, 0, widgetSize.width, widgetSize.height));

  // Calculate the scale factor between the displayed image and the original image.
  final scale = fittedSizes.destination.width / fittedSizes.source.width;

  // Translate the point from the widget's coordinates to the displayed image's coordinates.
  final pointInFittedImage = localPoint - destinationRect.topLeft;

  // Scale the point up to the original image's coordinate system.
  return pointInFittedImage / scale;
}
// lib/plugins/glitch_editor/glitch_editor_math.dart
import 'package:flutter/material.dart';

/// Transforms a point from the widget's local coordinate space to the
/// original image's coordinate space, accounting for `BoxFit.contain`.
Offset transformWidgetPointToImagePoint(
  Offset localPoint, {
  required Size widgetSize,
  required Size imageSize,
}) {
  // Calculate the sizes of the image as it's fitted within the widget
  final fittedSizes = applyBoxFit(BoxFit.contain, imageSize, widgetSize);
  final sourceSize = fittedSizes.source;
  final destinationSize = fittedSizes.destination;

  // Calculate the scale factor
  final scale = destinationSize.width / sourceSize.width;

  // Calculate the offset of the scaled image within the widget (it's centered)
  final double dx = (widgetSize.width - destinationSize.width) / 2.0;
  final double dy = (widgetSize.height - destinationSize.height) / 2.0;
  final Offset canvasOffset = Offset(dx, dy);

  // Transform the point
  return (localPoint - canvasOffset) / scale;
}
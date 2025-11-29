import 'dart:ui' as ui;

class ImageLoadResult {
  final ui.Image? image;
  final String? error;
  final String path;

  ImageLoadResult({this.image, this.error, required this.path});

  bool get hasError => error != null;
}
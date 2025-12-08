import 'dart:ui' as ui;
import 'asset_models.dart';
import 'asset_loader_registry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/editor/plugins/editor_plugin_registry.dart';
import '../data/repositories/project/project_repository.dart';
import '../project/project_models.dart';

class ImageAssetData extends AssetData {
  final ui.Image image;
  const ImageAssetData({required this.image});
}

class CoreImageAssetLoader implements AssetLoader<ImageAssetData> {
  static const _extensions = {'png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp'};

  @override
  bool canLoad(ProjectDocumentFile file) {
    final ext = file.name.split('.').lastOrNull?.toLowerCase();
    return ext != null && _extensions.contains(ext);
  }

  @override
  Future<ImageAssetData> load(Ref ref, ProjectDocumentFile file, ProjectRepository repo) async {
    final bytes = await repo.readFileAsBytes(file.uri);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return ImageAssetData(image: frame.image);
  }
}
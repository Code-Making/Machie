import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/app/app_notifier.dart'; // Fixed import

final exportAssetLoaderProvider = Provider((ref) => ExportAssetLoaderService(ref));

class ExportAssetLoaderService {
  final Ref _ref;
  final Map<String, ui.Image> _cache = {};

  ExportAssetLoaderService(this._ref);

  ProjectRepository get _repo => _ref.read(projectRepositoryProvider)!;
  String get _rootUri => _ref.read(currentProjectProvider)!.rootUri;

  Future<ui.Image?> loadImage(String relativePath) async {
    if (_cache.containsKey(relativePath)) return _cache[relativePath];

    try {
      final file = await _repo.fileHandler.resolvePath(_rootUri, relativePath);
      if (file == null) return null;

      final bytes = await _repo.readFileAsBytes(file.uri);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      
      _cache[relativePath] = frame.image;
      return frame.image;
    } catch (e) {
      return null;
    }
  }

  void clearCache() {
    _cache.clear();
  }
}
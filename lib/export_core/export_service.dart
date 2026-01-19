import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/app/app_notifier.dart';
import 'models.dart';
import 'services/atlas_gen_service.dart';
import 'export_collection_service.dart';
import 'writers/tiled_writer.dart';
import 'writers/texture_packer_writer.dart';
import 'writers/flow_graph_writer.dart';

final exportServiceProvider = Provider((ref) => ExportService(ref));

class ExportService {
  final Ref _ref;

  ExportService(this._ref);

  Future<void> runExportJob({
    required List<String> sourceFilePaths, // Project-relative paths
    required String outputFolder, // Project-relative path
    int maxSize = 2048,
    int padding = 2,
  }) async {
    final repo = _ref.read(projectRepositoryProvider)!;
    final projectRoot = _ref.read(currentProjectProvider)!.rootUri;
    
    // --- PHASE 1: COLLECTION ---
    print("Export Phase 1: Collecting...");
    final collectionService = _ref.read(exportCollectionServiceProvider);
    final assets = await collectionService.collectAssets(sourceFilePaths);
    
    if (assets.isEmpty) {
      throw Exception("No assets found to export.");
    }

    // --- PHASE 2: PACKING ---
    print("Export Phase 2: Packing ${assets.length} assets...");
    final atlasGen = _ref.read(atlasGenServiceProvider);
    final packedResult = await atlasGen.generateAtlas(
      assets, 
      maxPageWidth: maxSize, 
      maxPageHeight: maxSize, 
      padding: padding
    );

    // --- PHASE 3: WRITING ---
    print("Export Phase 3: Writing...");
    
    // 3a. Write Atlas Image(s)
    // Ensure output folder exists
    // Note: repo.createDocumentFile automatically handles creation usually, 
    // but explicit folder creation logic might be needed depending on file handler impl.
    
    for (final page in packedResult.pages) {
      await repo.createDocumentFile(
        repo.resolveRelativePath(projectRoot, outputFolder),
        'atlas_${page.index}.png',
        initialBytes: page.imageBytes,
        overwrite: true,
      );
    }

    // 3b. Rewrite Source Files
    final tiledWriter = TiledAssetWriter(repo, projectRoot);
    final packerWriter = TexturePackerWriter(repo);

    for (final path in sourceFilePaths) {
      // Load source
      final file = await repo.fileHandler.resolvePath(projectRoot, path);
      if (file == null) continue;
      final content = await repo.readFileAsBytes(file.uri);

      Uint8List? newContent;
      String? newExt;

      if (path.endsWith('.tmx')) {
        newContent = await tiledWriter.rewrite(path, content, packedResult);
        newExt = tiledWriter.extension;
      } else if (path.endsWith('.tpacker')) {
        newContent = await packerWriter.rewrite(path, content, packedResult);
        newExt = packerWriter.extension;
  } else if (path.endsWith('.fg')) { // <--- ADD THIS BLOCK
    newContent = await flowWriter.rewrite(path, content, packedResult);
    newExt = flowWriter.extension;
  }
      if (newContent != null && newExt != null) {
        // Filename: "level1.tmx"
        final name = path.split('/').last.split('.').first;
        final outName = '$name.$newExt';
        
        await repo.createDocumentFile(
          repo.resolveRelativePath(projectRoot, outputFolder),
          outName,
          initialBytes: newContent,
          overwrite: true,
        );
      }
    }
    
    print("Export Complete.");
  }
}
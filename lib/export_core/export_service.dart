import 'dart:io';
import 'dart:typed_data'; // Fixed: TypedData import
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/app/app_notifier.dart'; // Fixed: currentProjectProvider
import 'models.dart';
import 'services/atlas_gen_service.dart';
import 'export_collection_service.dart';
import 'writers/tiled_writer.dart';
import 'writers/texture_packer_writer.dart';
import 'writers/flow_graph_writer.dart'; // Added import
import '../project/project_settings_notifier.dart';

final exportServiceProvider = Provider((ref) => ExportService(ref));

class ExportService {
  final Ref _ref;

  ExportService(this._ref);

  Future<void> runExportJob({
    required List<String> sourceFilePaths,
    required String outputFolder,
    int maxSize = 2048,
    int padding = 2,
  }) async {
    final repo = _ref.read(projectRepositoryProvider)!;
    final projectRoot = _ref.read(currentProjectProvider)!.rootUri;
    
    // --- PHASE 1: COLLECTION ---
    print("Export Phase 1: Collecting...");
    final collectionService = _ref.read(exportCollectionServiceProvider);
    final assets = await collectionService.collectAssets(sourceFilePaths);
    
    // Note: If only FlowGraphs are exported, assets might be empty, but that's valid.
    // If you want to enforce assets:
    // if (assets.isEmpty) throw Exception("No assets found to export.");

    // --- PHASE 2: PACKING ---
    // Only pack if we have assets
    final atlasGen = _ref.read(atlasGenServiceProvider);
    
    // If empty, generate empty result or handle gracefully
    final packedResult = assets.isNotEmpty 
        ? await atlasGen.generateAtlas(
            assets, 
            maxPageWidth: maxSize, 
            maxPageHeight: maxSize, 
            padding: padding
          )
        : null;

    // --- PHASE 3: WRITING ---
    print("Export Phase 3: Writing...");
    
    if (packedResult != null) {
      for (final page in packedResult.pages) {
        await repo.createDocumentFile(
          repo.resolveRelativePath(projectRoot, outputFolder),
          'atlas_${page.index}.png',
          initialBytes: page.imageBytes,
          overwrite: true,
        );
      }
    }

    final tiledWriter = TiledAssetWriter(repo, projectRoot);
    final packerWriter = TexturePackerWriter(repo);
    final flowWriter = FlowGraphWriter(); // Fixed: Defined variable

    for (final path in sourceFilePaths) {
      final file = await repo.fileHandler.resolvePath(projectRoot, path);
      if (file == null) continue;
      final content = await repo.readFileAsBytes(file.uri);

      Uint8List? newContent;
      String? newExt;

      if (packedResult != null) {
        // Writers that require the atlas result
        if (path.endsWith('.tmx')) {
          newContent = await tiledWriter.rewrite(path, content, packedResult);
          newExt = tiledWriter.extension;
        } else if (path.endsWith('.tpacker')) {
          newContent = await packerWriter.rewrite(path, content, packedResult);
          newExt = packerWriter.extension;
        }
      }
      
      // Flow graph might just update text references, passing packedResult even if null/unused for now
      if (path.endsWith('.fg') && packedResult != null) { 
        newContent = await flowWriter.rewrite(path, content, packedResult);
        newExt = flowWriter.extension;
      }

      if (newContent != null && newExt != null) {
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
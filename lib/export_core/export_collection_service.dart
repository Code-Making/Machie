import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/app/app_notifier.dart';
import 'models.dart';
import 'services/asset_loader_service.dart';
import 'processors/tiled_processor.dart';
import 'processors/texture_packer_processor.dart';
import 'processors/flow_graph_processor.dart';
import '../project/project_settings_notifier.dart';

final exportCollectionServiceProvider = Provider((ref) => ExportCollectionService(ref));

class ExportCollectionService {
  final Ref _ref;

  ExportCollectionService(this._ref);

  Future<List<ExportableAsset>> collectAssets(List<String> filePaths) async {
    final repo = _ref.read(projectRepositoryProvider)!;
    final loader = _ref.read(exportAssetLoaderProvider);
    final projectRoot = _ref.read(currentProjectProvider)!.rootUri;

    // Initialize Processors
    final processors = [
  TiledAssetProcessor(repo, loader, projectRoot),
  TexturePackerAssetProcessor(repo, loader, projectRoot),
  FlowGraphAssetProcessor(repo, projectRoot), // <--- ADD THIS
    ];

    // Use a Map keyed by ExportableAssetId to deduplicate
    final Map<ExportableAssetId, ExportableAsset> uniqueAssets = {};

    loader.clearCache();

    for (final path in filePaths) {
      for (final processor in processors) {
        if (processor.canHandle(path)) {
          final fileAssets = await processor.collect(path);
          
          for (final asset in fileAssets) {
            // Deduplication happens here automatically due to Equatable ID
            if (!uniqueAssets.containsKey(asset.id)) {
              uniqueAssets[asset.id] = asset;
            }
          }
          break; // File handled
        }
      }
    }

    return uniqueAssets.values.toList();
  }
}
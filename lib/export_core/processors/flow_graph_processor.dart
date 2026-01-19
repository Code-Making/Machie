import 'dart:convert';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/flow_graph/models/flow_graph_models.dart';
import 'package:machine/editor/plugins/flow_graph/models/flow_references.dart';
import '../models.dart';

class FlowGraphAssetProcessor implements AssetProcessor {
  final ProjectRepository repo;
  final String projectRoot;

  FlowGraphAssetProcessor(this.repo, this.projectRoot);

  @override
  bool canHandle(String filePath) => filePath.toLowerCase().endsWith('.fg');

  @override
  Future<List<ExportableAsset>> collect(String projectRelativePath) async {
    // Flow Graphs don't directly contribute pixels to the atlas.
    // However, we parse it here to ensure it's valid JSON before trying to write it later.
    
    final file = await repo.fileHandler.resolvePath(projectRoot, projectRelativePath);
    if (file == null) return [];

    // Validating we can parse it
    try {
      final content = await repo.readFile(file.uri);
      FlowGraph.deserialize(content);
    } catch (e) {
      print("Warning: Failed to parse Flow Graph during collection: $projectRelativePath");
    }

    return []; // No pixels to pack
  }
}
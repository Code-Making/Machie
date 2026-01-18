// FILE: lib/editor/plugins/flow_graph/services/flow_export_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/flow_graph/models/flow_graph_models.dart';
import 'package:machine/logs/logs_provider.dart';
import '../flow_graph_asset_resolver.dart';

final flowExportServiceProvider = Provider<FlowExportService>((ref) {
  return FlowExportService(ref);
});

class FlowExportService {
  final Ref _ref;

  FlowExportService(this._ref);

  Future<void> export({
    required FlowGraph graph,
    required FlowGraphAssetResolver resolver,
    required String destinationFolderUri,
    required String fileName,
    bool embedSchema = false,
  }) async {
    final talker = _ref.read(talkerProvider);
    final repo = _ref.read(projectRepositoryProvider)!;

    talker.info('Starting Flow Graph export for $fileName...');

    // 1. Validation via Resolver
    if (graph.schemaPath != null) {
      final schema = resolver.getSchema(graph.schemaPath);
      if (schema == null) {
        talker.warning('Exporting without schema: Schema at ${graph.schemaPath} could not be resolved.');
      } else {
        // Here we could validate all nodes against the schema before export
      }
    }

    // 2. Serialization (Phase 3 will add embedding/baking logic here)
    final content = graph.serialize();

    // 3. Save
    await repo.createDocumentFile(
      destinationFolderUri,
      '$fileName.json', // Export as standard JSON
      initialContent: content,
      overwrite: true,
    );

    talker.info('Flow Graph export completed.');
  }
}
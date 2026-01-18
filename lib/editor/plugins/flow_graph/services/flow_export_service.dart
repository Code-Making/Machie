// FILE: lib/editor/plugins/flow_graph/services/flow_export_service.dart

import 'dart:convert';
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

    Map<String, dynamic> exportData = jsonDecode(graph.serialize());

    // 1. Resolve and Bake Schema (if requested)
    if (graph.schemaPath != null) {
      final schema = resolver.getSchema(graph.schemaPath);
      
      if (schema == null) {
        talker.warning('Exporting: Schema at ${graph.schemaPath} could not be resolved via Asset System.');
      } else {
        if (embedSchema) {
          talker.info('Embedding schema definition into export.');
          // Convert schema definitions to JSON and inject into export
          final schemaJson = schema.nodeTypes.map((t) => {
            'type': t.type,
            'category': t.category,
            'inputs': t.inputs.map((i) => {
              'key': i.key, 
              'type': i.type.name
            }).toList(),
            'outputs': t.outputs.map((o) => {
              'key': o.key, 
              'type': o.type.name
            }).toList(),
            'properties': t.properties.map((p) => {
              'key': p.key, 
              'type': p.type.name, 
              'default': p.defaultValue
            }).toList(),
          }).toList();
          
          exportData['schema_definition'] = schemaJson;
          
          // Remove the relative path reference since we are embedding
          exportData.remove('schema'); 
        }
      }
    }

    // 2. Clean up Editor-only data (Viewport)
    // Game runtimes usually don't need the editor viewport position
    if (exportData.containsKey('viewport')) {
      exportData.remove('viewport');
    }

    // 3. Serialize Final JSON
    final finalContent = const JsonEncoder.withIndent('  ').convert(exportData);

    // 4. Save
    await repo.createDocumentFile(
      destinationFolderUri,
      '$fileName.json',
      initialContent: finalContent,
      overwrite: true,
    );

    talker.info('Flow Graph export completed: $fileName.json');
  }
}
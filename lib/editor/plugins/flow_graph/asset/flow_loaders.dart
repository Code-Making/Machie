// FILE: lib/editor/plugins/flow_graph/asset/flow_loaders.dart

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/asset_cache/asset_models.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import '../models/flow_graph_models.dart';
import '../models/flow_schema_models.dart';
import 'flow_asset_models.dart';

/// Loads .json files as Flow Schemas.
/// 
/// Note: In a real app, you might want a specific extension for schemas (e.g. .fgschema)
/// to avoid trying to load every JSON file as a schema. Here we assume specific naming or
/// we just try to parse valid schema structures.
class FlowSchemaLoader implements AssetLoader<FlowSchemaAssetData> {
  @override
  bool canLoad(ProjectDocumentFile file) {
    // We check for .json, but ideally we check if it looks like a schema content 
    // or rely on a specific naming convention.
    return file.name.endsWith('.json') && file.name.contains('schema'); 
  }

  @override
  Future<FlowSchemaAssetData> load(Ref ref, ProjectDocumentFile file, ProjectRepository repo) async {
    final content = await repo.readFile(file.uri);
    final jsonList = jsonDecode(content) as List;
    
    final nodeTypes = jsonList
        .map((e) => FlowNodeType.fromJson(e as Map<String, dynamic>))
        .toList();

    return FlowSchemaAssetData(nodeTypes);
  }
}

/// Loads .fg files and resolves their linked Schema.
class FlowGraphLoader implements AssetLoader<FlowGraphAssetData>, IDependentAssetLoader<FlowGraphAssetData> {
  @override
  bool canLoad(ProjectDocumentFile file) {
    return file.name.endsWith('.fg');
  }

  /// 1. Parse the .fg file superficially to find dependencies (the schema path).
  @override
  Future<Set<String>> getDependencies(Ref ref, ProjectDocumentFile file, ProjectRepository repo) async {
    try {
      final content = await repo.readFile(file.uri);
      final json = jsonDecode(content);
      
      if (json['schema'] != null) {
        // Resolve relative path: "./schema.json" or "../schemas/logic.json" relative to the .fg file
        final contextPath = repo.fileHandler.getPathForDisplay(file.uri, relativeTo: repo.rootUri);
        final parentPath = repo.fileHandler.getParentUri(file.uri); // This is absolute URI usually
        
        // We use the repo to calculate the absolute path of the dependency, then convert back to project relative
        // Actually, ProjectRepository.resolveRelativePath handles (ContextPath, RelativePath) -> ProjectRelativePath
        
        // ContextPath needs to be project-relative string of the folder containing .fg
        // We assume 'contextPath' returned by getPathForDisplay is project relative, e.g. "assets/graphs/my_graph.fg"
        // We need the folder: "assets/graphs"
        
        final relativeFolder = contextPath.contains('/') 
            ? contextPath.substring(0, contextPath.lastIndexOf('/'))
            : '';
            
        final dependencyUri = repo.resolveRelativePath(relativeFolder, json['schema']);
        return {dependencyUri};
      }
    } catch (e) {
      // If parsing fails here, we just return no dependencies and let load() handle the error or load partial data.
    }
    return {};
  }

  /// 2. Load the graph and combine with the pre-loaded (via getDependencies) schema.
  @override
  Future<FlowGraphAssetData> load(Ref ref, ProjectDocumentFile file, ProjectRepository repo) async {
    final content = await repo.readFile(file.uri);
    final graph = FlowGraph.deserialize(content);
    
    FlowSchemaAssetData? schemaData;

    if (graph.schemaPath != null) {
      final contextPath = repo.fileHandler.getPathForDisplay(file.uri, relativeTo: repo.rootUri);
      final relativeFolder = contextPath.contains('/') 
          ? contextPath.substring(0, contextPath.lastIndexOf('/'))
          : '';
          
      final schemaUri = repo.resolveRelativePath(relativeFolder, graph.schemaPath!);
      
      // We look up the schema in the AssetProvider. 
      // Because getDependencies returned this URI, the AssetNotifier should have already triggered a load for it.
      // We use ref.read (not watch) because this load() is called inside an AsyncNotifier build/update logic.
      final assetState = await ref.read(assetDataProvider(schemaUri).future);
      
      if (assetState is FlowSchemaAssetData) {
        schemaData = assetState;
      }
    }

    return FlowGraphAssetData(
      graph: graph,
      schema: schemaData,
    );
  }
}
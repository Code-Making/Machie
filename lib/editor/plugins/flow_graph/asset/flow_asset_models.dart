// FILE: lib/editor/plugins/flow_graph/asset/flow_asset_models.dart

import 'package:machine/asset_cache/asset_models.dart';
import '../models/flow_graph_models.dart';
import '../models/flow_schema_models.dart';

/// The result of loading a flow_schema.json file.
class FlowSchemaAssetData extends AssetData {
  final List<FlowNodeType> nodeTypes;
  
  // Quick lookup map for performance
  final Map<String, FlowNodeType> typeMap;

  FlowSchemaAssetData(this.nodeTypes) 
      : typeMap = {for (var t in nodeTypes) t.type: t};
}

/// The result of loading a .fg file.
class FlowGraphAssetData extends AssetData {
  final FlowGraph graph;
  
  /// The resolved schema data. 
  /// If the schema file is missing or failed to load, this might be null,
  /// but the graph itself is still valid (nodes will be "unknown").
  final FlowSchemaAssetData? schema;

  FlowGraphAssetData({
    required this.graph,
    this.schema,
  });
}
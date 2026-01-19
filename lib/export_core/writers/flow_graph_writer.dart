import 'dart:convert';
import 'dart:typed_data';
import 'package:machine/editor/plugins/flow_graph/models/flow_graph_models.dart';
import 'package:machine/editor/plugins/flow_graph/models/flow_references.dart';
import 'package:machine/editor/plugins/flow_graph/models/flow_schema_models.dart';
import '../packer/packer_models.dart';
import 'writer_interface.dart';

class FlowGraphWriter implements AssetWriter {
  @override
  String get extension => 'json'; // Exports to standard JSON

  @override
  Future<Uint8List> rewrite(
    String projectRelativePath,
    Uint8List fileContent,
    PackedAtlasResult atlasResult,
  ) async {
    final jsonString = utf8.decode(fileContent);
    final graph = FlowGraph.deserialize(jsonString);

    // We need to walk through nodes and properties to find TiledObjectReferences
    final newNodes = graph.nodes.map((node) {
      final newProps = Map<String, dynamic>.from(node.properties);
      
      // Iterate properties to find TiledObjectReference JSON structures
      for (final key in newProps.keys) {
        final value = newProps[key];
        
        // Check if this property looks like a TiledObjectReference
        // Structure: { "map": "path", "layerId": 1, "objectId": 1 }
        if (value is Map<String, dynamic> && value.containsKey('map') && value.containsKey('objectId')) {
          final ref = TiledObjectReference.fromJson(value);
          
          if (ref.sourceMapPath != null) {
            // Change extension from .tmx to .json (or whatever TiledWriter uses)
            // Ideally, we'd know the exact export name, but assuming standard replacement:
            final oldPath = ref.sourceMapPath!;
            String newPath = oldPath;
            
            if (oldPath.endsWith('.tmx')) {
              newPath = oldPath.replaceAll('.tmx', '.json');
            }
            
            // Re-serialize with new path
            newProps[key] = {
              ...value,
              'map': newPath,
            };
          }
        }
      }
      return node.copyWith(properties: newProps);
    }).toList();

    // Re-serialize the graph
    // We remove the Viewport data for the exported game file
    final exportData = {
      'nodes': newNodes.map((n) => n.toJson()).toList(),
      'connections': graph.connections.map((c) => c.toJson()).toList(),
      if (graph.schemaPath != null) 'schema': graph.schemaPath,
    };

    return utf8.encode(const JsonEncoder.withIndent('  ').convert(exportData));
  }
}
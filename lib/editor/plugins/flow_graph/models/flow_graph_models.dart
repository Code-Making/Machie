// FILE: lib/editor/plugins/flow_graph/models/flow_graph_models.dart

import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Represents a single connection wire between two nodes.
@immutable
class FlowConnection {
  final String outputNodeId;
  final String outputPortKey;
  final String inputNodeId;
  final String inputPortKey;

  const FlowConnection({
    required this.outputNodeId,
    required this.outputPortKey,
    required this.inputNodeId,
    required this.inputPortKey,
  });

  Map<String, dynamic> toJson() => {
        'outNode': outputNodeId,
        'outPort': outputPortKey,
        'inNode': inputNodeId,
        'inPort': inputPortKey,
      };

  factory FlowConnection.fromJson(Map<String, dynamic> json) {
    return FlowConnection(
      outputNodeId: json['outNode'],
      outputPortKey: json['outPort'],
      inputNodeId: json['inNode'],
      inputPortKey: json['inPort'],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowConnection &&
          runtimeType == other.runtimeType &&
          outputNodeId == other.outputNodeId &&
          outputPortKey == other.outputPortKey &&
          inputNodeId == other.inputNodeId &&
          inputPortKey == other.inputPortKey;

  @override
  int get hashCode => Object.hash(outputNodeId, outputPortKey, inputNodeId, inputPortKey);
}

/// Represents an instance of a node in the graph.
class FlowNode {
  final String id;
  final String type;
  final Offset position;
  final Map<String, dynamic> properties;
  final Map<String, dynamic> customData;

  FlowNode({
    required this.id,
    required this.type,
    required this.position,
    this.properties = const {},
    this.customData = const {},
  });

  FlowNode copyWith({
    String? id,
    String? type,
    Offset? position,
    Map<String, dynamic>? properties,
    Map<String, dynamic>? customData,
  }) {
    return FlowNode(
      id: id ?? this.id,
      type: type ?? this.type,
      position: position ?? this.position,
      properties: properties ?? Map.from(this.properties),
      customData: customData ?? Map.from(this.customData),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'x': position.dx,
        'y': position.dy,
        'properties': properties,
        if (customData.isNotEmpty) 'customData': customData,
      };

  factory FlowNode.fromJson(Map<String, dynamic> json) {
    return FlowNode(
      id: json['id'] ?? const Uuid().v4(),
      type: json['type'],
      position: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      properties: Map<String, dynamic>.from(json['properties'] ?? {}),
      customData: Map<String, dynamic>.from(json['customData'] ?? {}),
    );
  }
}

/// The root object for a Flow Graph file.
class FlowGraph {
  final List<FlowNode> nodes;
  final List<FlowConnection> connections;
  
  final Offset viewportPosition;
  final double viewportScale;
  final String? schemaPath;

  const FlowGraph({
    required this.nodes,
    required this.connections,
    this.viewportPosition = Offset.zero,
    this.viewportScale = 1.0,
    this.schemaPath,
  });

  String serialize() {
    final map = {
      if (schemaPath != null) 'schema': schemaPath,
      'nodes': nodes.map((n) => n.toJson()).toList(),
      'connections': connections.map((c) => c.toJson()).toList(),
      'viewport': {
        'x': viewportPosition.dx,
        'y': viewportPosition.dy,
        'zoom': viewportScale,
      }
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  factory FlowGraph.deserialize(String jsonString) {
    if (jsonString.trim().isEmpty) {
      // CORRECTED: Return mutable lists (removed const)
      return FlowGraph(
        nodes: <FlowNode>[], 
        connections: <FlowConnection>[]
      );
    }

    final json = jsonDecode(jsonString);
    
    final viewportJson = json['viewport'] ?? {};
    final viewportPos = Offset(
      (viewportJson['x'] as num? ?? 0).toDouble(),
      (viewportJson['y'] as num? ?? 0).toDouble(),
    );
    final viewportZoom = (viewportJson['zoom'] as num? ?? 1.0).toDouble();

    return FlowGraph(
      schemaPath: json['schema'],
      nodes: (json['nodes'] as List?)
              ?.map((e) => FlowNode.fromJson(e))
              .toList() ??
          <FlowNode>[], // Ensure fallback is a mutable list
      connections: (json['connections'] as List?)
              ?.map((e) => FlowConnection.fromJson(e))
              .toList() ??
          <FlowConnection>[], // Ensure fallback is a mutable list
      viewportPosition: viewportPos,
      viewportScale: viewportZoom,
    );
  }
}
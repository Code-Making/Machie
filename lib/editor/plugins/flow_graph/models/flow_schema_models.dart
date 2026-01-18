// FILE: lib/editor/plugins/flow_graph/models/flow_schema_models.dart

import 'package:flutter/material.dart';

enum FlowPortType {
  execution, // White flow arrow
  string,
  number,
  boolean,
  vector2,
  tiledObject, // Special type for passing Tiled object references
  any,
}

enum FlowPropertyType {
  string,
  integer,
  float,
  bool,
  select, // Dropdown
  color,
  tiledObjectRef, // The inspector widget for picking a Tiled Object
}

/// Defines a specific port on a node type (Input or Output).
class FlowPortDefinition {
  final String key;
  final String label;
  final FlowPortType type;
  final Color? customColor;

  const FlowPortDefinition({
    required this.key,
    required this.label,
    required this.type,
    this.customColor,
  });

  factory FlowPortDefinition.fromJson(Map<String, dynamic> json) {
    return FlowPortDefinition(
      key: json['key'],
      label: json['name'] ?? json['key'], // Fallback if schema uses 'name'
      type: _parsePortType(json['type']),
      customColor: json['color'] != null ? _parseColor(json['color']) : null,
    );
  }

  static FlowPortType _parsePortType(String? type) {
    return FlowPortType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => FlowPortType.any,
    );
  }
}

/// Defines an editable property shown in the node's body or inspector.
class FlowPropertyDefinition {
  final String key;
  final String label;
  final FlowPropertyType type;
  final dynamic defaultValue;
  final List<String>? options; // For 'select' type

  const FlowPropertyDefinition({
    required this.key,
    required this.label,
    required this.type,
    this.defaultValue,
    this.options,
  });

  factory FlowPropertyDefinition.fromJson(Map<String, dynamic> json) {
    return FlowPropertyDefinition(
      key: json['key'],
      label: json['name'] ?? json['key'],
      type: _parsePropertyType(json['type']),
      defaultValue: json['default'],
      options: (json['options'] as List?)?.map((e) => e.toString()).toList(),
    );
  }

  static FlowPropertyType _parsePropertyType(String? type) {
    return FlowPropertyType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => FlowPropertyType.string,
    );
  }
}

/// Defines a Node Type available in the editor.
class FlowNodeType {
  final String type; // Unique ID (e.g. "MathAdd", "TiledEvent")
  final String label; // Display name (e.g. "Add Number")
  final String category; // For palette grouping
  final String description;
  final List<FlowPortDefinition> inputs;
  final List<FlowPortDefinition> outputs;
  final List<FlowPropertyDefinition> properties;

  const FlowNodeType({
    required this.type,
    required this.label,
    required this.category,
    this.description = '',
    this.inputs = const [],
    this.outputs = const [],
    this.properties = const [],
  });

  factory FlowNodeType.fromJson(Map<String, dynamic> json) {
    return FlowNodeType(
      type: json['type'],
      label: json['label'] ?? json['type'],
      category: json['category'] ?? 'General',
      description: json['description'] ?? '',
      inputs: (json['inputs'] as List?)
              ?.map((e) => FlowPortDefinition.fromJson(e))
              .toList() ??
          [],
      outputs: (json['outputs'] as List?)
              ?.map((e) => FlowPortDefinition.fromJson(e))
              .toList() ??
          [],
      properties: (json['properties'] as List?)
              ?.map((e) => FlowPropertyDefinition.fromJson(e))
              .toList() ??
          [],
    );
  }
}

/// Helper for Hex colors in schema (e.g. "#FF0000")
Color _parseColor(String hex) {
  hex = hex.replaceAll('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  return Color(int.parse(hex, radix: 16));
}
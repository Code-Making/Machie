// FILE: lib/editor/plugins/flow_graph/flow_graph_parameter_parser.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'models/flow_schema_models.dart';

@immutable
class FlowGraphParameter {
  final String name;
  final FlowPortType type;

  const FlowGraphParameter({required this.name, required this.type});
}

class FlowGraphParameterParser {
  static List<FlowGraphParameter> parse(String jsonContent) {
    if (jsonContent.trim().isEmpty) {
      return [];
    }
    
    try {
      final json = jsonDecode(jsonContent);
      final nodes = json['nodes'] as List?;
      if (nodes == null) {
        return [];
      }

      final parameters = <FlowGraphParameter>[];
      for (final node in nodes) {
        final type = node['type'] as String?;
        if (type != null && type.startsWith('core_input_')) {
          final properties = node['properties'] as Map<String, dynamic>?;
          final name = properties?['name'] as String?;

          if (name != null && name.isNotEmpty) {
            FlowPortType paramType;
            switch(type) {
              case 'core_input_string':
                paramType = FlowPortType.string;
                break;
              case 'core_input_number':
                paramType = FlowPortType.number;
                break;
              case 'core_input_boolean':
                paramType = FlowPortType.boolean;
                break;
              case 'core_input_tiled_object':
                paramType = FlowPortType.tiledObject;
                break;
              default:
                continue; // Skip unknown input types
            }
            parameters.add(FlowGraphParameter(name: name, type: paramType));
          }
        }
      }
      return parameters;
    } catch (e) {
      // Parsing can fail if JSON is invalid, return empty list.
      return [];
    }
  }
}
// FILE: lib/editor/plugins/flow_graph/core_nodes.dart

import 'models/flow_schema_models.dart';

List<FlowNodeType> getCoreFlowNodes() {
  return [
    // === INPUT NODES (The Graph's Public API) ===
    FlowNodeType(
      type: 'core_input_string',
      label: 'Input (String)',
      category: 'Input',
      description: 'Defines a string input parameter for this graph.',
      outputs: const [
        FlowPortDefinition(key: 'value', label: 'Value', type: FlowPortType.string),
      ],
      properties: const [
        FlowPropertyDefinition(key: 'name', label: 'Name', type: FlowPropertyType.string, defaultValue: 'myString'),
      ],
    ),
    FlowNodeType(
      type: 'core_input_number',
      label: 'Input (Number)',
      category: 'Input',
      description: 'Defines a number input parameter for this graph.',
      outputs: const [
        FlowPortDefinition(key: 'value', label: 'Value', type: FlowPortType.number),
      ],
      properties: const [
        FlowPropertyDefinition(key: 'name', label: 'Name', type: FlowPropertyType.string, defaultValue: 'myNumber'),
      ],
    ),
    FlowNodeType(
      type: 'core_input_boolean',
      label: 'Input (Boolean)',
      category: 'Input',
      description: 'Defines a boolean input parameter for this graph.',
      outputs: const [
        FlowPortDefinition(key: 'value', label: 'Value', type: FlowPortType.boolean),
      ],
      properties: const [
        FlowPropertyDefinition(key: 'name', label: 'Name', type: FlowPropertyType.string, defaultValue: 'myBoolean'),
      ],
    ),
    FlowNodeType(
      type: 'core_input_tiled_object',
      label: 'Input (Tiled Object)',
      category: 'Input',
      description: 'Defines a Tiled Object reference input for this graph.',
      outputs: const [
        FlowPortDefinition(key: 'value', label: 'Object', type: FlowPortType.tiledObject),
      ],
      properties: const [
        FlowPropertyDefinition(key: 'name', label: 'Name', type: FlowPropertyType.string, defaultValue: 'myObjectRef'),
      ],
    ),

    // === CONSTANT NODES ===
    FlowNodeType(
      type: 'core_constant_string',
      label: 'Constant (String)',
      category: 'Constants',
      description: 'Provides a constant string value.',
      outputs: const [
        FlowPortDefinition(key: 'value', label: 'Value', type: FlowPortType.string),
      ],
      properties: const [
        FlowPropertyDefinition(key: 'value', label: 'Value', type: FlowPropertyType.string, defaultValue: ''),
      ],
    ),
    FlowNodeType(
      type: 'core_constant_number',
      label: 'Constant (Number)',
      category: 'Constants',
      description: 'Provides a constant number value.',
      outputs: const [
        FlowPortDefinition(key: 'value', label: 'Value', type: FlowPortType.number),
      ],
      properties: const [
        FlowPropertyDefinition(key: 'value', label: 'Value', type: FlowPropertyType.float, defaultValue: 0.0),
      ],
    ),
    FlowNodeType(
      type: 'core_constant_boolean',
      label: 'Constant (Boolean)',
      category: 'Constants',
      description: 'Provides a constant boolean value.',
      outputs: const [
        FlowPortDefinition(key: 'value', label: 'Value', type: FlowPortType.boolean),
      ],
      properties: const [
        FlowPropertyDefinition(key: 'value', label: 'Value', type: FlowPropertyType.bool, defaultValue: false),
      ],
    ),

    // === UTILITY NODES ===
    FlowNodeType(
      type: 'core_comment',
      label: 'Comment',
      category: 'Utility',
      description: 'A comment node for documenting the graph.',
      properties: const [
        FlowPropertyDefinition(key: 'text', label: 'Text', type: FlowPropertyType.string, defaultValue: 'Comment text...'),
      ],
    ),
  ];
}
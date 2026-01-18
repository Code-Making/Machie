// FILE: lib/editor/plugins/flow_graph/flow_graph_settings_model.dart

import 'package:machine/editor/plugins/editor_plugin_registry.dart';

class FlowGraphSettings extends PluginSettings {
  int backgroundColorValue;
  int gridColorValue;
  double gridSpacing;
  double gridThickness;

  FlowGraphSettings({
    this.backgroundColorValue = 0xFF1E1E1E,
    this.gridColorValue = 0x0DFFFFFF, // Approx 5% opacity white
    this.gridSpacing = 20.0,
    this.gridThickness = 1.0,
  });

  @override
  void fromJson(Map<String, dynamic> json) {
    backgroundColorValue = json['backgroundColorValue'] ?? 0xFF1E1E1E;
    gridColorValue = json['gridColorValue'] ?? 0x0DFFFFFF;
    gridSpacing = (json['gridSpacing'] ?? 20.0).toDouble();
    gridThickness = (json['gridThickness'] ?? 1.0).toDouble();
  }

  @override
  Map<String, dynamic> toJson() => {
        'backgroundColorValue': backgroundColorValue,
        'gridColorValue': gridColorValue,
        'gridSpacing': gridSpacing,
        'gridThickness': gridThickness,
      };

  FlowGraphSettings copyWith({
    int? backgroundColorValue,
    int? gridColorValue,
    double? gridSpacing,
    double? gridThickness,
  }) {
    return FlowGraphSettings(
      backgroundColorValue: backgroundColorValue ?? this.backgroundColorValue,
      gridColorValue: gridColorValue ?? this.gridColorValue,
      gridSpacing: gridSpacing ?? this.gridSpacing,
      gridThickness: gridThickness ?? this.gridThickness,
    );
  }

  @override
  FlowGraphSettings clone() {
    return FlowGraphSettings(
      backgroundColorValue: backgroundColorValue,
      gridColorValue: gridColorValue,
      gridSpacing: gridSpacing,
      gridThickness: gridThickness,
    );
  }
}
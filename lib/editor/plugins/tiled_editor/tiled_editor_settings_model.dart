import 'package:flutter/material.dart';
import 'package:machine/editor/plugins/editor_plugin_registry.dart';

class TiledEditorSettings extends PluginSettings {
  int gridColorValue;
  double gridThickness;
  String schemaFileName; // New field

  TiledEditorSettings({
    this.gridColorValue = 0x33FFFFFF,
    this.gridThickness = 1.0,
    this.schemaFileName = 'ecs_schema.json', // Default value
  });

  @override
  void fromJson(Map<String, dynamic> json) {
    gridColorValue = json['gridColorValue'] ?? 0x33FFFFFF;
    gridThickness = json['gridThickness'] ?? 1.0;
    schemaFileName = json['schemaFileName'] ?? 'ecs_schema.json';
  }

  @override
  Map<String, dynamic> toJson() => {
        'gridColorValue': gridColorValue,
        'gridThickness': gridThickness,
        'schemaFileName': schemaFileName,
      };

  TiledEditorSettings copyWith({
    int? gridColorValue,
    double? gridThickness,
    String? schemaFileName,
  }) {
    return TiledEditorSettings(
      gridColorValue: gridColorValue ?? this.gridColorValue,
      gridThickness: gridThickness ?? this.gridThickness,
      schemaFileName: schemaFileName ?? this.schemaFileName,
    );
  }

  @override
  TiledEditorSettings clone() {
    return TiledEditorSettings(
      gridColorValue: gridColorValue,
      gridThickness: gridThickness,
      schemaFileName: schemaFileName,
    );
  }
}
import 'package:flutter/material.dart';
import 'package:machine/editor/plugins/editor_plugin_registry.dart';

class TiledEditorSettings extends PluginSettings {
  int gridColorValue;
  double gridThickness;

  TiledEditorSettings({
    this.gridColorValue = 0x33FFFFFF, // Default: White with 20% opacity
    this.gridThickness = 1.0,
  });

  @override
  void fromJson(Map<String, dynamic> json) {
    gridColorValue = json['gridColorValue'] ?? 0x33FFFFFF;
    gridThickness = json['gridThickness'] ?? 1.0;
  }

  @override
  Map<String, dynamic> toJson() => {
        'gridColorValue': gridColorValue,
        'gridThickness': gridThickness,
      };

  TiledEditorSettings copyWith({
    int? gridColorValue,
    double? gridThickness,
  }) {
    return TiledEditorSettings(
      gridColorValue: gridColorValue ?? this.gridColorValue,
      gridThickness: gridThickness ?? this.gridThickness,
    );
  }

  @override
  TiledEditorSettings clone() {
    return TiledEditorSettings(
      gridColorValue: gridColorValue,
      gridThickness: gridThickness,
    );
  }
}
import 'package:flutter/material.dart';
import 'package:machine/editor/plugins/editor_plugin_registry.dart';

class TexturePackerSettings extends PluginSettings {
  int checkerBoardColor1;
  int checkerBoardColor2;
  int gridColor;
  double gridThickness;
  double defaultAnimationSpeed;

  TexturePackerSettings({
    this.checkerBoardColor1 = 0xFF404040, // Dark grey
    this.checkerBoardColor2 = 0xFF505050, // Lighter grey
    this.gridColor = 0x66FFFFFF, // White with approx 40% opacity
    this.gridThickness = 1.0,
    this.defaultAnimationSpeed = 10.0,
  });

  @override
  void fromJson(Map<String, dynamic> json) {
    checkerBoardColor1 = json['checkerBoardColor1'] ?? 0xFF404040;
    checkerBoardColor2 = json['checkerBoardColor2'] ?? 0xFF505050;
    gridColor = json['gridColor'] ?? 0x66FFFFFF;
    gridThickness = (json['gridThickness'] ?? 1.0).toDouble();
    defaultAnimationSpeed = (json['defaultAnimationSpeed'] ?? 10.0).toDouble();
  }

  @override
  Map<String, dynamic> toJson() => {
        'checkerBoardColor1': checkerBoardColor1,
        'checkerBoardColor2': checkerBoardColor2,
        'gridColor': gridColor,
        'gridThickness': gridThickness,
        'defaultAnimationSpeed': defaultAnimationSpeed,
      };

  TexturePackerSettings copyWith({
    int? checkerBoardColor1,
    int? checkerBoardColor2,
    int? gridColor,
    double? gridThickness,
    double? defaultAnimationSpeed,
  }) {
    return TexturePackerSettings(
      checkerBoardColor1: checkerBoardColor1 ?? this.checkerBoardColor1,
      checkerBoardColor2: checkerBoardColor2 ?? this.checkerBoardColor2,
      gridColor: gridColor ?? this.gridColor,
      gridThickness: gridThickness ?? this.gridThickness,
      defaultAnimationSpeed: defaultAnimationSpeed ?? this.defaultAnimationSpeed,
    );
  }

  @override
  TexturePackerSettings clone() {
    return copyWith();
  }
}
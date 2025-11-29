// FILE: lib/settings/settings_models.dart

import 'package:flutter/material.dart';

abstract class MachineSettings {
  Map<String, dynamic> toJson();
  void fromJson(Map<String, dynamic> json);
  MachineSettings clone();
}

class AppSettings {
  final Map<Type, MachineSettings> pluginSettings;
  // CHANGED: Key is String (plugin ID), not Type
  final Map<String, MachineSettings> explorerPluginSettings;

  AppSettings({
    required this.pluginSettings,
    required this.explorerPluginSettings,
  });

  AppSettings copyWith({
    Map<Type, MachineSettings>? pluginSettings,
    Map<String, MachineSettings>? explorerPluginSettings,
  }) {
    return AppSettings(
      pluginSettings: pluginSettings ?? this.pluginSettings,
      explorerPluginSettings:
          explorerPluginSettings ?? this.explorerPluginSettings,
    );
  }
}

class GeneralSettings extends MachineSettings {
  bool hideAppBarInFullScreen;
  bool hideTabBarInFullScreen;
  bool hideBottomToolbarInFullScreen;
  ThemeMode themeMode;
  int accentColorValue;
  bool showHiddenFiles;

  GeneralSettings({
    this.hideAppBarInFullScreen = true,
    this.hideTabBarInFullScreen = true,
    this.hideBottomToolbarInFullScreen = true,
    this.themeMode = ThemeMode.dark,
    this.accentColorValue = 0xFFF44336,
    this.showHiddenFiles = false,
  });

  @override
  void fromJson(Map<String, dynamic> json) {
    hideAppBarInFullScreen = json['hideAppBarInFullScreen'] ?? true;
    hideTabBarInFullScreen = json['hideTabBarInFullScreen'] ?? true;
    hideBottomToolbarInFullScreen =
        json['hideBottomToolbarInFullScreen'] ?? true;
    accentColorValue = json['accentColorValue'] ?? 0xFFF44336;
    themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == json['themeMode'],
      orElse: () => ThemeMode.dark,
    );
    showHiddenFiles = json['showHiddenFiles'] ?? false;
  }

  @override
  Map<String, dynamic> toJson() => {
    'hideAppBarInFullScreen': hideAppBarInFullScreen,
    'hideTabBarInFullScreen': hideTabBarInFullScreen,
    'hideBottomToolbarInFullScreen': hideBottomToolbarInFullScreen,
    'accentColorValue': accentColorValue,
    'themeMode': themeMode.name,
    'showHiddenFiles': showHiddenFiles,
  };

  GeneralSettings copyWith({
    bool? hideAppBarInFullScreen,
    bool? hideTabBarInFullScreen,
    bool? hideBottomToolbarInFullScreen,
    ThemeMode? themeMode,
    int? accentColorValue,
    bool? showHiddenFiles,
  }) {
    return GeneralSettings(
      hideAppBarInFullScreen:
          hideAppBarInFullScreen ?? this.hideAppBarInFullScreen,
      hideTabBarInFullScreen:
          hideTabBarInFullScreen ?? this.hideTabBarInFullScreen,
      hideBottomToolbarInFullScreen:
          hideBottomToolbarInFullScreen ?? this.hideBottomToolbarInFullScreen,
      themeMode: themeMode ?? this.themeMode,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
    );
  }

  @override
  GeneralSettings clone() {
    return GeneralSettings(
      hideAppBarInFullScreen: hideAppBarInFullScreen,
      hideTabBarInFullScreen: hideTabBarInFullScreen,
      hideBottomToolbarInFullScreen: hideBottomToolbarInFullScreen,
      themeMode: themeMode,
      accentColorValue: accentColorValue,
      showHiddenFiles: showHiddenFiles,
    );
  }
}

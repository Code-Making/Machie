// lib/settings/settings_models.dart
import 'package:flutter/material.dart'; // Import for ThemeMode

// NEW: A common abstract base class for all settings objects in the app.
abstract class MachineSettings {
  Map<String, dynamic> toJson();
  void fromJson(Map<String, dynamic> json);
}

class AppSettings {
  // REFACTOR: The map now holds the common base class type.
  final Map<Type, MachineSettings> pluginSettings;

  AppSettings({required this.pluginSettings});

  AppSettings copyWith({Map<Type, MachineSettings>? pluginSettings}) {
    return AppSettings(pluginSettings: pluginSettings ?? this.pluginSettings);
  }
}

// REFACTOR: GeneralSettings now extends the common base class directly.
class GeneralSettings extends MachineSettings {
  bool hideAppBarInFullScreen;
  bool hideTabBarInFullScreen;
  bool hideBottomToolbarInFullScreen;
  // NEW: Theme properties
  ThemeMode themeMode;
  int accentColorValue;
  bool showHiddenFiles; // <-- ADDED


  GeneralSettings({
    this.hideAppBarInFullScreen = true,
    this.hideTabBarInFullScreen = true,
    this.hideBottomToolbarInFullScreen = true,
    // NEW: Default values
    this.themeMode = ThemeMode.dark,
    this.accentColorValue = 0xFFF44336, // Default Red
    this.showHiddenFiles = false, // <-- ADDED (default to false)
  });

  @override
  void fromJson(Map<String, dynamic> json) {
    hideAppBarInFullScreen = json['hideAppBarInFullScreen'] ?? true;
    hideTabBarInFullScreen = json['hideTabBarInFullScreen'] ?? true;
    hideBottomToolbarInFullScreen =
        json['hideBottomToolbarInFullScreen'] ?? true;
    // NEW: Deserialize theme properties
    accentColorValue = json['accentColorValue'] ?? 0xFFF44336;
    themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == json['themeMode'],
      orElse: () => ThemeMode.dark, // Safe fallback
    );
    showHiddenFiles = json['showHiddenFiles'] ?? false; // <-- ADDED
  }

  @override
  Map<String, dynamic> toJson() => {
    'hideAppBarInFullScreen': hideAppBarInFullScreen,
    'hideTabBarInFullScreen': hideTabBarInFullScreen,
    'hideBottomToolbarInFullScreen': hideBottomToolbarInFullScreen,
    // NEW: Serialize theme properties
    'accentColorValue': accentColorValue,
    'themeMode': themeMode.name,
    'showHiddenFiles': showHiddenFiles, // <-- ADDED
  };

  GeneralSettings copyWith({
    bool? hideAppBarInFullScreen,
    bool? hideTabBarInFullScreen,
    bool? hideBottomToolbarInFullScreen,
    // NEW: Add to copyWith
    ThemeMode? themeMode,
    int? accentColorValue,
    bool? showHiddenFiles, // <-- ADDED
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
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles, // <-- ADDED
    );
  }
}

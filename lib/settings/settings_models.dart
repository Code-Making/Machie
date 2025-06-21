// lib/settings/settings_models.dart
import '../editor/plugins/plugin_models.dart';

// REFACTOR: This class is now defined in this file.
class AppSettings {
  final Map<Type, PluginSettings> pluginSettings;

  AppSettings({required this.pluginSettings});

  AppSettings copyWith({Map<Type, PluginSettings>? pluginSettings}) {
    return AppSettings(pluginSettings: pluginSettings ?? this.pluginSettings);
  }
}

// NEW: A settings class for general app behavior, not tied to a plugin.
class GeneralSettings extends PluginSettings {
  bool hideAppBarInFullScreen;
  bool hideTabBarInFullScreen;
  bool hideBottomToolbarInFullScreen;

  GeneralSettings({
    this.hideAppBarInFullScreen = true,
    this.hideTabBarInFullScreen = true,
    this.hideBottomToolbarInFullScreen = true,
  });

  @override
  void fromJson(Map<String, dynamic> json) {
    hideAppBarInFullScreen = json['hideAppBarInFullScreen'] ?? true;
    hideTabBarInFullScreen = json['hideTabBarInFullScreen'] ?? true;
    hideBottomToolbarInFullScreen = json['hideBottomToolbarInFullScreen'] ?? true;
  }

  @override
  Map<String, dynamic> toJson() => {
        'hideAppBarInFullScreen': hideAppBarInFullScreen,
        'hideTabBarInFullScreen': hideTabBarInFullScreen,
        'hideBottomToolbarInFullScreen': hideBottomToolbarInFullScreen,
      };
      
  GeneralSettings copyWith({
    bool? hideAppBarInFullScreen,
    bool? hideTabBarInFullScreen,
    bool? hideBottomToolbarInFullScreen,
  }) {
    return GeneralSettings(
      hideAppBarInFullScreen: hideAppBarInFullScreen ?? this.hideAppBarInFullScreen,
      hideTabBarInFullScreen: hideTabBarInFullScreen ?? this.hideTabBarInFullScreen,
      hideBottomToolbarInFullScreen: hideBottomToolbarInFullScreen ?? this.hideBottomToolbarInFullScreen,
    );
  }
}
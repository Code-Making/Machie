// lib/settings/settings_models.dart
import '../editor/plugins/plugin_models.dart';

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
import '../../settings/settings_models.dart';
import '../project_settings_models.dart';

class LocalProjectSettings extends ProjectSettings {
  /// A dummy setting to demonstrate project-specific configuration.
  bool enableExperimentalFeature;

  LocalProjectSettings({this.enableExperimentalFeature = false});

  @override
  void fromJson(Map<String, dynamic> json) {
    enableExperimentalFeature = json['enableExperimentalFeature'] ?? false;
  }

  @override
  Map<String, dynamic> toJson() => {
    'enableExperimentalFeature': enableExperimentalFeature,
  };

  LocalProjectSettings copyWith({bool? enableExperimentalFeature}) {
    return LocalProjectSettings(
      enableExperimentalFeature:
          enableExperimentalFeature ?? this.enableExperimentalFeature,
    );
  }

  @override
  MachineSettings clone() {
    return LocalProjectSettings(
      enableExperimentalFeature: enableExperimentalFeature,
    );
  }
}

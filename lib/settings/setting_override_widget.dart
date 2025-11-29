import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/explorer/explorer_plugin_models.dart';
import 'package:machine/project/project_settings_notifier.dart';
import 'package:machine/settings/settings_models.dart';
import 'package:machine/settings/settings_notifier.dart';

class SettingOverrideWidget extends ConsumerWidget {
  final MachineSettings globalSetting;
  final Widget Function(
    BuildContext context,
    MachineSettings effectiveSetting,
    void Function(MachineSettings) onChanged,
  ) childBuilder;

  const SettingOverrideWidget({
    super.key,
    required this.globalSetting,
    required this.childBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectSettingsState = ref.watch(projectSettingsProvider);
    final globalAppSettings = ref.watch(settingsProvider);

    // This part remains the same, handling the "no project open" case.
    if (projectSettingsState == null) {
      return childBuilder(
        context,
        globalSetting,
        (newSettings) {
          if (newSettings is ExplorerPluginSettings) {
            final pluginId = globalAppSettings.explorerPluginSettings.entries
                .firstWhere(
                    (e) => e.value.runtimeType == newSettings.runtimeType)
                .key;
            ref
                .read(settingsProvider.notifier)
                .updateExplorerPluginSettings(pluginId, newSettings);
          } else {
            ref
                .read(settingsProvider.notifier)
                .updatePluginSettings(newSettings);
          }
        },
      );
    }

    final projectSettingsNotifier = ref.read(projectSettingsProvider.notifier);
    
    // This logic to determine the state and callbacks is also unchanged and correct.
    bool isOverridden = false;
    MachineSettings? projectOverrideSetting;

    if (globalSetting is ExplorerPluginSettings) {
      final pluginId = globalAppSettings.explorerPluginSettings.entries
          .firstWhere((e) => e.value.runtimeType == globalSetting.runtimeType)
          .key;
      projectOverrideSetting =
          projectSettingsState.explorerPluginSettingsOverrides[pluginId];
      isOverridden = projectOverrideSetting != null;
    } else {
      projectOverrideSetting =
          projectSettingsState.pluginSettingsOverrides[globalSetting.runtimeType];
      isOverridden = projectOverrideSetting != null;
    }

    final MachineSettings effectiveSetting =
        isOverridden ? projectOverrideSetting! : globalSetting;

    final void Function(MachineSettings) onChanged = isOverridden
        ? projectSettingsNotifier.updateOverride
        : (newSettings) {
            if (newSettings is ExplorerPluginSettings) {
              final pluginId = globalAppSettings.explorerPluginSettings.entries
                  .firstWhere(
                      (e) => e.value.runtimeType == newSettings.runtimeType)
                  .key;
              ref
                  .read(settingsProvider.notifier)
                  .updateExplorerPluginSettings(pluginId, newSettings);
            } else {
              ref
                  .read(settingsProvider.notifier)
                  .updatePluginSettings(newSettings);
            }
          };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (isOverridden)
              Icon(
                Icons.push_pin,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
            const SizedBox(width: 4),
            Text(
              'Override for this project',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Checkbox(
              value: isOverridden,
              onChanged: (value) {
                if (value == true) {
                  // The widget now simply tells the notifier to create an override
                  // based on the current global setting. The notifier handles the cloning.
                  projectSettingsNotifier.updateOverride(globalSetting);
                } else {
                  projectSettingsNotifier.removeOverride(globalSetting);
                }
              },
            ),
          ],
        ),
        childBuilder(context, effectiveSetting, onChanged),
      ],
    );
  }
}
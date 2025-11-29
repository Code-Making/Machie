import 'package:flutter/material.dart';

import 'local_project_settings.dart';

class LocalProjectSettingsUI extends StatelessWidget {
  final LocalProjectSettings settings;
  final void Function(LocalProjectSettings) onChanged;

  const LocalProjectSettingsUI({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Enable Experimental Feature'),
          subtitle: const Text(
              'This is a setting specific to Local Folder projects.'),
          value: settings.enableExperimentalFeature,
          onChanged: (newValue) {
            onChanged(
              settings.copyWith(enableExperimentalFeature: newValue),
            );
          },
        ),
      ],
    );
  }
}
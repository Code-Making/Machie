// FILE: lib/editor/plugins/termux_terminal/widgets/termux_settings_widget.dart

import 'package:flutter/material.dart';
import '../termux_terminal_models.dart';

class TermuxSettingsWidget extends StatelessWidget {
  final TermuxTerminalSettings settings;
  final ValueChanged<TermuxTerminalSettings> onChanged;

  const TermuxSettingsWidget({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            initialValue: settings.fontSize.toString(),
            decoration: const InputDecoration(
              labelText: 'Font Size',
              helperText: 'Recommended: 12.0 to 16.0',
            ),
            keyboardType: TextInputType.number,
            onChanged: (val) {
              final size = double.tryParse(val);
              if (size != null && size > 0) {
                onChanged(settings.copyWith(fontSize: size));
              }
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: settings.termuxWorkDir,
            decoration: const InputDecoration(
              labelText: 'Default Working Directory',
              helperText: 'The directory where new terminals will start.',
            ),
            onChanged: (val) => onChanged(settings.copyWith(termuxWorkDir: val.trim())),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: settings.shellCommand,
            decoration: const InputDecoration(
              labelText: 'Shell Executable',
              helperText: 'e.g., bash, zsh, fish',
            ),
            onChanged: (val) => onChanged(settings.copyWith(shellCommand: val.trim())),
          ),
          SwitchListTile(
            title: const Text('Use Dark Theme'),
            value: settings.useDarkTheme,
            onChanged: (val) => onChanged(settings.copyWith(useDarkTheme: val)),
          ),
        ],
      ),
    );
  }
}
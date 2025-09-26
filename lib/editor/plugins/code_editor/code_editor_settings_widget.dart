import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/settings_notifier.dart';
import 'code_themes.dart';
import 'code_editor_models.dart';

class CodeEditorSettingsUI extends ConsumerStatefulWidget {
  final CodeEditorSettings settings;

  const CodeEditorSettingsUI({super.key, required this.settings});

  @override
  ConsumerState<CodeEditorSettingsUI> createState() =>
      _CodeEditorSettingsUIState();
}

class _CodeEditorSettingsUIState extends ConsumerState<CodeEditorSettingsUI> {
  late CodeEditorSettings _currentSettings;

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
  }

  @override
  Widget build(BuildContext context) {
    final double currentFontHeightValue = _currentSettings.fontHeight ?? 0.9;
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Word Wrap'),
          value: _currentSettings.wordWrap,
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(wordWrap: value)),
        ),
                // --- NEW FONT HEIGHT SLIDER ---
        Text('Line Height: ${currentFontHeightValue < 1.0 ? "Default" : currentFontHeightValue.toStringAsFixed(2)}'),
        Slider(
          value: currentFontHeightValue,
          min: 0.9, // The "default" or null value
          max: 2.0,
          divisions: 11, // (2.0 - 0.9) / 0.1 = 11 steps
          label: currentFontHeightValue < 1.0 ? "Default" : currentFontHeightValue.toStringAsFixed(2),
          onChanged: (value) {
            if (value < 1.0) {
              // If the user slides below 1.0, we set the fontHeight to null.
              _updateSettings(_currentSettings.copyWith(setFontHeightToNull: true));
            } else {
              // Otherwise, we update it with the new value.
              _updateSettings(_currentSettings.copyWith(fontHeight: value));
            }
          },
        ),
        Slider(
          value: _currentSettings.fontSize,
          min: 8,
          max: 24,
          divisions: 16,
          label: 'Font Size: ${_currentSettings.fontSize.round()}',
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(fontSize: value)),
        ),
        DropdownButtonFormField<String>(
          value: _currentSettings.fontFamily,
          items: const [
            DropdownMenuItem(
              value: 'JetBrainsMono',
              child: Text('JetBrains Mono'),
            ),
            DropdownMenuItem(value: 'FiraCode', child: Text('Fira Code')),
            DropdownMenuItem(value: 'RobotoMono', child: Text('Roboto Mono')),
          ],
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(fontFamily: value)),
        ),
        // NEW: Theme selection dropdown
        DropdownButtonFormField<String>(
          value: _currentSettings.themeName,
          decoration: const InputDecoration(labelText: 'Editor Theme'),
          items:
              CodeThemes.availableCodeThemes.keys.map((themeName) {
                return DropdownMenuItem(
                  value: themeName,
                  child: Text(themeName),
                );
              }).toList(),
          onChanged: (value) {
            if (value != null) {
              _updateSettings(_currentSettings.copyWith(themeName: value));
            }
          },
        ),
      ],
    );
  }

  void _updateSettings(CodeEditorSettings newSettings) {
    setState(() => _currentSettings = newSettings);
    ref.read(settingsProvider.notifier).updatePluginSettings(newSettings);
  }
}

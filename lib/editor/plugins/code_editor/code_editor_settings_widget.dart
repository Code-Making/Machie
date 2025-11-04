import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/settings_notifier.dart';
import 'code_editor_models.dart';
import 'logic/code_themes.dart';

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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Word Wrap
        SwitchListTile(
          title: const Text('Word Wrap'),
          value: _currentSettings.wordWrap,
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(wordWrap: value)),
        ),
        const Divider(),

        // Font Settings Section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            "Font & Display",
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SwitchListTile(
          title: const Text('Enable Font Ligatures'),
          subtitle: const Text(
            'Displays special characters like "=>" as a single symbol',
          ),
          value: _currentSettings.fontLigatures,
          onChanged:
              (value) => _updateSettings(
                _currentSettings.copyWith(fontLigatures: value),
              ),
        ),

        // Font Family
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Font Family'),
            initialValue: _currentSettings.fontFamily,
            items: const [
              DropdownMenuItem(value: 'FiraCode', child: Text('Fira Code')),
              DropdownMenuItem(
                value: 'JetBrainsMono',
                child: Text('JetBrains Mono'),
              ),
              DropdownMenuItem(value: 'RobotoMono', child: Text('Roboto Mono')),
            ],
            onChanged:
                (value) => _updateSettings(
                  _currentSettings.copyWith(fontFamily: value),
                ),
          ),
        ),
        const SizedBox(height: 16),

        // Font Size
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text('Font Size: ${_currentSettings.fontSize.round()}'),
        ),
        Slider(
          value: _currentSettings.fontSize,
          min: 8,
          max: 24,
          divisions: 16,
          label: _currentSettings.fontSize.round().toString(),
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(fontSize: value)),
        ),

        // Line Height
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'Line Height: ${currentFontHeightValue < 1.0 ? "Default" : currentFontHeightValue.toStringAsFixed(2)}',
          ),
        ),
        Slider(
          value: currentFontHeightValue,
          min: 0.9,
          max: 2.0,
          divisions: 11,
          label:
              currentFontHeightValue < 1.0
                  ? "Default"
                  : currentFontHeightValue.toStringAsFixed(2),
          onChanged: (value) {
            if (value < 1.0) {
              _updateSettings(
                _currentSettings.copyWith(setFontHeightToNull: true),
              );
            } else {
              _updateSettings(_currentSettings.copyWith(fontHeight: value));
            }
          },
        ),
        const Divider(),

        // Theme
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Editor Theme'),
            initialValue: _currentSettings.themeName,
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
        ),
      ],
    );
  }

  void _updateSettings(CodeEditorSettings newSettings) {
    setState(() => _currentSettings = newSettings);
    ref.read(settingsProvider.notifier).updatePluginSettings(newSettings);
  }
}

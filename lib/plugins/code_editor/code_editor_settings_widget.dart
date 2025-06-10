import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

import '../../app/app_notifier.dart';
import '../../data/file_handler/file_handler.dart';
import '../../project/project_models.dart';
import '../../session/session_models.dart';
import '../../session/session_service.dart';
import '../../settings/settings_notifier.dart';
import '../../settings/settings_models.dart';
import '../plugin_models.dart';
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
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Word Wrap'),
          value: _currentSettings.wordWrap,
          onChanged:
              (value) =>
                  _updateSettings(_currentSettings.copyWith(wordWrap: value)),
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
          items: CodeThemes.availableCodeThemes.keys.map((themeName) {
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
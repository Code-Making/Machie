// =========================================
// NEW FILE: lib/editor/plugins/llm_editor/llm_editor_settings_widget.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/editor/plugins/llm_editor/providers/llm_provider_factory.dart';
import 'package:machine/settings/settings_notifier.dart';

class LlmEditorSettingsUI extends ConsumerStatefulWidget {
  final LlmEditorSettings settings;
  const LlmEditorSettingsUI({super.key, required this.settings});

  @override
  ConsumerState<LlmEditorSettingsUI> createState() =>
      _LlmEditorSettingsUIState();
}

class _LlmEditorSettingsUIState extends ConsumerState<LlmEditorSettingsUI> {
  late LlmEditorSettings _currentSettings;
  late TextEditingController _apiKeyController;

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
    _apiKeyController = TextEditingController(
      text: _currentSettings.apiKeys[_currentSettings.selectedProviderId],
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }
  
  void _updateSettings(LlmEditorSettings newSettings) {
    setState(() => _currentSettings = newSettings);
    ref.read(settingsProvider.notifier).updatePluginSettings(newSettings);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'LLM Provider'),
          value: _currentSettings.selectedProviderId,
          items: allLlmProviders
              .map(
                (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              final newSettings = _currentSettings.copyWith(selectedProviderId: value);
              _updateSettings(newSettings);
              // Update the API key field to show the key for the new provider
              _apiKeyController.text = newSettings.apiKeys[value] ?? '';
            }
          },
        ),
        const SizedBox(height: 16),
        if (_currentSettings.selectedProviderId != 'dummy')
          TextFormField(
            controller: _apiKeyController,
            decoration: const InputDecoration(labelText: 'API Key'),
            obscureText: true,
            onChanged: (value) {
              final newApiKeys = Map<String, String>.from(_currentSettings.apiKeys);
              newApiKeys[_currentSettings.selectedProviderId] = value;
              _updateSettings(_currentSettings.copyWith(apiKeys: newApiKeys));
            },
          ),
      ],
    );
  }
}
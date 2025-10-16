// =========================================
// UPDATED: lib/editor/plugins/llm_editor/llm_editor_settings_widget.dart
// =========================================

import 'package:collection/collection.dart'; // Import for firstWhereOrNull
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
    // Get the provider instance for the currently selected ID.
    final selectedProvider = allLlmProviders.firstWhereOrNull(
      (p) => p.id == _currentSettings.selectedProviderId,
    );
    final availableModels = selectedProvider?.availableModels ?? [];

    // Ensure the currently selected model is valid, or default to the first available.
    String? currentModel = _currentSettings.selectedModelIds[_currentSettings.selectedProviderId];
    if (currentModel == null || !availableModels.contains(currentModel)) {
      currentModel = availableModels.firstOrNull;
    }

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
              // When provider changes, we need to select a default model for it if one isn't set.
              final newProvider = allLlmProviders.firstWhere((p) => p.id == value);
              final newModelIds = Map<String, String>.from(_currentSettings.selectedModelIds);
              if (!newModelIds.containsKey(value)) {
                newModelIds[value] = newProvider.availableModels.first;
              }

              final newSettings = _currentSettings.copyWith(
                selectedProviderId: value,
                selectedModelIds: newModelIds,
              );
              _updateSettings(newSettings);
              _apiKeyController.text = newSettings.apiKeys[value] ?? '';
            }
          },
        ),
        const SizedBox(height: 16),

        // NEW: Model Selection Dropdown
        if (availableModels.isNotEmpty)
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Model'),
            value: currentModel,
            items: availableModels
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                final newModelIds = Map<String, String>.from(_currentSettings.selectedModelIds);
                newModelIds[_currentSettings.selectedProviderId] = value;
                _updateSettings(_currentSettings.copyWith(selectedModelIds: newModelIds));
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
// import 'package:collection/collection.dart'; // Import for firstWhereOrNull

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/settings_notifier.dart';
import 'llm_editor_models.dart';
import 'providers/llm_provider_factory.dart';

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

  bool _isLoadingModels = true;
  List<LlmModelInfo> _availableModels = [];

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
    _apiKeyController = TextEditingController(
      text: _currentSettings.apiKeys[_currentSettings.selectedProviderId],
    );
    _fetchModels();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _fetchModels() async {
    if (!mounted) return;
    setState(() {
      _isLoadingModels = true;
      _availableModels = [];
    });

    final provider = ref.read(llmServiceProvider);
    final models = await provider.listModels();

    if (!mounted) return;

    // Auto-select the first model if the current selection is invalid
    final currentModel = _currentSettings.selectedModels[provider.id];
    if (models.isNotEmpty &&
        (currentModel == null || !models.contains(currentModel))) {
      final newModels = Map<String, LlmModelInfo?>.from(
        _currentSettings.selectedModels,
      );
      newModels[provider.id] = models.first;
      _updateSettings(
        _currentSettings.copyWith(selectedModels: newModels),
        triggerModelFetch: false,
      );
    }

    setState(() {
      _availableModels = models;
      _isLoadingModels = false;
    });
  }

  void _updateSettings(
    LlmEditorSettings newSettings, {
    bool triggerModelFetch = true,
  }) {
    setState(() => _currentSettings = newSettings);
    ref.read(settingsProvider.notifier).updatePluginSettings(newSettings);
    if (triggerModelFetch) {
      // Use a post-frame callback to ensure the provider has updated
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchModels();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // final selectedProvider = allLlmProviders.firstWhereOrNull(
    //   (p) => p.id == _currentSettings.selectedProviderId,
    // );

    // Find the full model info object for the selected model
    final LlmModelInfo? selectedModelInfo =
        _currentSettings.selectedModels[_currentSettings.selectedProviderId];

    return Column(
      children: [
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'LLM Provider'),
          value: _currentSettings.selectedProviderId,
          items:
              allLlmProviders
                  .map(
                    (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                  )
                  .toList(),
          onChanged: (value) {
            if (value != null) {
              final newSettings = _currentSettings.copyWith(
                selectedProviderId: value,
              );
              _updateSettings(newSettings); // This will trigger a fetch
              _apiKeyController.text = newSettings.apiKeys[value] ?? '';
            }
          },
        ),
        const SizedBox(height: 16),

        if (_isLoadingModels)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: LinearProgressIndicator(),
          )
        else if (_availableModels.isNotEmpty)
          DropdownButtonFormField<LlmModelInfo>(
            decoration: const InputDecoration(labelText: 'Model'),
            value: selectedModelInfo,
            items:
                _availableModels
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(m.displayName),
                      ),
                    )
                    .toList(),
            onChanged: (value) {
              if (value != null) {
                final newModels = Map<String, LlmModelInfo?>.from(
                  _currentSettings.selectedModels,
                );
                newModels[_currentSettings.selectedProviderId] = value;
                _updateSettings(
                  _currentSettings.copyWith(selectedModels: newModels),
                  triggerModelFetch: false,
                );
              }
            },
          )
        else
          ListTile(
            leading: Icon(Icons.warning_amber_rounded, color: Colors.orange),
            title: Text('No compatible models found.'),
            subtitle: Text('Check your API key or network connection.'),
          ),

        if (selectedModelInfo != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Token Limits'),
            subtitle: Text(
              'Input: ${selectedModelInfo.inputTokenLimit}, Output: ${selectedModelInfo.outputTokenLimit}',
            ),
          ),

        const SizedBox(height: 16),
        if (_currentSettings.selectedProviderId != 'dummy')
          TextFormField(
            controller: _apiKeyController,
            decoration: const InputDecoration(labelText: 'API Key'),
            obscureText: true,
            onChanged: (value) {
              final newApiKeys = Map<String, String>.from(
                _currentSettings.apiKeys,
              );
              newApiKeys[_currentSettings.selectedProviderId] = value;
              // No need to fetch models again, just update the key
              _updateSettings(
                _currentSettings.copyWith(apiKeys: newApiKeys),
                triggerModelFetch: false,
              );
            },
            // ADDED: Debounce API key check
            onEditingComplete: () {
              // Re-fetch models when the user finishes editing the API key
              _fetchModels();
            },
          ),
      ],
    );
  }
}

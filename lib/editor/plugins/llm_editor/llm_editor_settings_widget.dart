import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'llm_editor_models.dart';
import 'providers/llm_provider_factory.dart';

class LlmEditorSettingsUI extends ConsumerStatefulWidget {
  final LlmEditorSettings settings;
  final void Function(LlmEditorSettings) onChanged;

  const LlmEditorSettingsUI({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  ConsumerState<LlmEditorSettingsUI> createState() =>
      _LlmEditorSettingsUIState();
}

class _LlmEditorSettingsUIState extends ConsumerState<LlmEditorSettingsUI> {
  late TextEditingController _apiKeyController;
  bool _isLoadingModels = true;
  List<LlmModelInfo> _availableModels = [];

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(
      text: widget.settings.apiKeys[widget.settings.selectedProviderId],
    );
    _fetchModels();
  }

  @override
  void didUpdateWidget(covariant LlmEditorSettingsUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentProviderId = widget.settings.selectedProviderId;
    final oldProviderId = oldWidget.settings.selectedProviderId;
    final currentApiKey = widget.settings.apiKeys[currentProviderId];
    final oldApiKey = oldWidget.settings.apiKeys[oldProviderId];

    // If the provider or its API key has changed, we need to fetch new models.
    if (currentProviderId != oldProviderId || currentApiKey != oldApiKey) {
      // Update the text controller if the provider changed.
      if (currentProviderId != oldProviderId) {
        _apiKeyController.text = currentApiKey ?? '';
      }
      _fetchModels();
    }
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

    // Auto-select the first model if the current selection is invalid.
    final currentModel = widget.settings.selectedModels[provider.id];
    if (models.isNotEmpty &&
        (currentModel == null || !models.contains(currentModel))) {
      final newModels = Map<String, LlmModelInfo?>.from(
        widget.settings.selectedModels,
      );
      newModels[provider.id] = models.first;
      // Emit the change upwards.
      widget.onChanged(widget.settings.copyWith(selectedModels: newModels));
    }

    setState(() {
      _availableModels = models;
      _isLoadingModels = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // The source of truth is always `widget.settings`.
    final LlmModelInfo? selectedModelInfo =
        widget.settings.selectedModels[widget.settings.selectedProviderId];

    return Column(
      children: [
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'LLM Provider'),
          value: widget.settings.selectedProviderId,
          items: allLlmProviders
              .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              final newSettings =
                  widget.settings.copyWith(selectedProviderId: value);
              widget.onChanged(newSettings);
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
            items: _availableModels
                .map((m) => DropdownMenuItem(value: m, child: Text(m.displayName)))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                final newModels = Map<String, LlmModelInfo?>.from(
                  widget.settings.selectedModels,
                );
                newModels[widget.settings.selectedProviderId] = value;
                widget.onChanged(
                  widget.settings.copyWith(selectedModels: newModels),
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
        if (widget.settings.selectedProviderId != 'dummy')
          TextFormField(
            controller: _apiKeyController,
            decoration: const InputDecoration(labelText: 'API Key'),
            obscureText: true,
            onChanged: (value) {
              final newApiKeys = Map<String, String>.from(
                widget.settings.apiKeys,
              );
              newApiKeys[widget.settings.selectedProviderId] = value;
              widget.onChanged(
                widget.settings.copyWith(apiKeys: newApiKeys),
              );
            },
            onEditingComplete: () {
              // Re-fetch models when the user finishes editing the API key.
              _fetchModels();
            },
          ),
      ],
    );
  }
}
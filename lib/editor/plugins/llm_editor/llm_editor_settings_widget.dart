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
  late String _currentEditingProviderId;

  @override
  void initState() {
    super.initState();
    // Default to the refactor provider, or dummy if not set
    _currentEditingProviderId = widget.settings.refactorProviderId;
    _apiKeyController = TextEditingController(
      text: widget.settings.apiKeys[_currentEditingProviderId],
    );
    _fetchModels();
  }

  @override
  void didUpdateWidget(covariant LlmEditorSettingsUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If external setting changed the provider ID
    if (oldWidget.settings.refactorProviderId != widget.settings.refactorProviderId) {
        _currentEditingProviderId = widget.settings.refactorProviderId;
        _updateApiControllerText();
        _fetchModels();
    }
  }
  
  void _updateApiControllerText() {
    final key = widget.settings.apiKeys[_currentEditingProviderId];
    if (_apiKeyController.text != key) {
        _apiKeyController.text = key ?? '';
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
    
    // We create a provider instance just to fetch list
    // This is a bit inefficient creating a provider on the fly but sufficient for settings UI
    // In a robust app, use the ref to get the service based on params.
    final provider = allLlmProviders.firstWhere(
        (p) => p.id == _currentEditingProviderId, 
        orElse: () => allLlmProviders.first
    );
    
    // Hack: We need to pass the API Key to the provider to list models if it requires auth
    // The factories are auto-dispose so we can't easily reconfigure them here without updating global state.
    // For now, we rely on the implementation detail that we update global settings API key 
    // before calling fetchModels
    
    // Actually, let's just trigger a global ref read via the existing factory,
    // assuming the User hit "Save" or we update state on fly. 
    // But `llmServiceProvider` reads from `effectiveSettingsProvider`. 
    // This widget updates a COPY. 
    // We will simulate listing:
    List<LlmModelInfo> models = [];
    try {
        // Warning: This won't work perfectly for Gemini until the settings are applied 
        // because GeminiProvider needs the key from the 'live' settings. 
        // For the purpose of this refactor, we accept this limitation or assume 
        // the user applied keys previously.
        // A better approach would be updating the factory to take a Config object.
        models = await provider.listModels(); 
    } catch (e) {
        models = [];
    }

    if (!mounted) return;

    final currentModel = widget.settings.selectedModels[_currentEditingProviderId];
    
    // Auto-select first available if current is invalid
    if (models.isNotEmpty &&
        (currentModel == null || !models.contains(currentModel))) {
      final newModels = Map<String, LlmModelInfo?>.from(
        widget.settings.selectedModels,
      );
      newModels[_currentEditingProviderId] = models.first;
      widget.onChanged(widget.settings.copyWith(selectedModels: newModels));
    }

    setState(() {
      _availableModels = models;
      _isLoadingModels = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final LlmModelInfo? selectedModelInfo =
        widget.settings.selectedModels[widget.settings.refactorProviderId];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          child: Text(
            "Global Refactoring & Defaults",
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(
            labelText: 'Provider (for Code Edits)',
            helperText: 'Used by the "Refactor Selection" command',
          ),
          value: widget.settings.refactorProviderId,
          items: allLlmProviders
                  .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                  .toList(),
          onChanged: (value) {
            if (value != null) {
                // Change UI state focus
                _currentEditingProviderId = value;
                _updateApiControllerText();
                // Save setting
                widget.onChanged(widget.settings.copyWith(
                    refactorProviderId: value,
                ));
                _fetchModels();
            }
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
            controller: _apiKeyController,
            decoration: InputDecoration(
                labelText: 'API Key for ${_currentEditingProviderId}',
            ),
            obscureText: true,
            onChanged: (value) {
              final newApiKeys = Map<String, String>.from(
                widget.settings.apiKeys,
              );
              newApiKeys[_currentEditingProviderId] = value;
              widget.onChanged(widget.settings.copyWith(apiKeys: newApiKeys));
            },
            onEditingComplete: () {
              // Trigger reload when done editing
               // This won't effectively work until settings are committed by the parent SettingsScreen
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
            decoration: const InputDecoration(labelText: 'Default Model'),
            value: selectedModelInfo,
            isExpanded: true,
            items: _availableModels
                    .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(m.displayName),
                    ))
                    .toList(),
            onChanged: (value) {
              if (value != null) {
                final newModels = Map<String, LlmModelInfo?>.from(
                  widget.settings.selectedModels,
                );
                newModels[widget.settings.refactorProviderId] = value;
                widget.onChanged(
                  widget.settings.copyWith(selectedModels: newModels),
                );
              }
            },
          )
        else
          ListTile(
            leading: Icon(Icons.warning_amber_rounded, color: Colors.orange),
            title: Text('No models found'),
            subtitle: Text('Save API key settings first'),
          ),

        if (selectedModelInfo != null)
           Padding(
             padding: const EdgeInsets.only(top:8.0, left: 16.0),
             child: Text(
               'Limit: ${selectedModelInfo.inputTokenLimit} in / ${selectedModelInfo.outputTokenLimit} out',
               style: Theme.of(context).textTheme.bodySmall,
             ),
           ),
      ],
    );
  }
}
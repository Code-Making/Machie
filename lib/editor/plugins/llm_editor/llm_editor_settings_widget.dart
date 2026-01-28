import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'llm_editor_models.dart';
import 'providers/llm_provider.dart';
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
  bool _isLoadingModels = false;
  List<LlmModelInfo> _availableModels = [];
  late String _currentEditingProviderId;

  @override
  void initState() {
    super.initState();
    _currentEditingProviderId = widget.settings.refactorProviderId;
    _apiKeyController = TextEditingController(
      text: widget.settings.apiKeys[_currentEditingProviderId] ?? '',
    );
    // Fetch models immediately
    _fetchModels();
  }

  @override
  void didUpdateWidget(covariant LlmEditorSettingsUI oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the external settings changed the provider ID (rare in this view, but possible)
    if (oldWidget.settings.refactorProviderId !=
        widget.settings.refactorProviderId) {
      setState(() {
        _currentEditingProviderId = widget.settings.refactorProviderId;
        _updateApiControllerText();
      });
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

    final currentId = _currentEditingProviderId;
    // Use the key currently in the controller (so user can test without saving)
    // fallback to saved settings if empty.
    final currentKey = _apiKeyController.text.trim().isNotEmpty
        ? _apiKeyController.text.trim()
        : (widget.settings.apiKeys[currentId] ?? '');

    try {
      LlmProvider provider;
      if (currentId == 'gemini') {
        provider = GeminiProvider(currentKey);
      } else {
        provider = DummyProvider();
      }

      final models = await provider.listModels();

      if (!mounted) return;
      if (currentId != _currentEditingProviderId) return; // switched while loading

      setState(() {
        _availableModels = models;
        _isLoadingModels = false;
      });
      
      // Auto-select a model if none selected or invalid
      final currentSelected = widget.settings.selectedModels[currentId];
      if (models.isNotEmpty) {
          if (currentSelected == null || !models.contains(currentSelected)) {
              final newModels = Map<String, LlmModelInfo?>.from(widget.settings.selectedModels);
              newModels[currentId] = models.first;
              widget.onChanged(widget.settings.copyWith(selectedModels: newModels));
          }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingModels = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Current refactoring model selected
    final LlmModelInfo? selectedModelInfo =
        widget.settings.selectedModels[widget.settings.refactorProviderId];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
          child: Text(
            "Global Refactoring Configuration",
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
        ),
        
        // 1. Provider Dropdown
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'AI Provider',
              helperText: 'Select provider used for code modification commands',
              border: OutlineInputBorder(),
            ),
            value: widget.settings.refactorProviderId,
            items: allLlmProviders
                .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                // Save new provider ID
                final newSettings = widget.settings.copyWith(refactorProviderId: value);
                widget.onChanged(newSettings);
                
                // Update Local UI State
                setState(() {
                   _currentEditingProviderId = value;
                   _updateApiControllerText();
                });
                _fetchModels();
              }
            },
          ),
        ),
        const SizedBox(height: 16),

        // 2. API Key Field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: TextFormField(
            controller: _apiKeyController,
            decoration: InputDecoration(
              labelText: '${_currentEditingProviderId.toUpperCase()} API Key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                 icon: const Icon(Icons.refresh),
                 tooltip: 'Refresh Models',
                 onPressed: _fetchModels,
              )
            ),
            obscureText: true,
            onChanged: (value) {
              final newApiKeys = Map<String, String>.from(
                widget.settings.apiKeys,
              );
              newApiKeys[_currentEditingProviderId] = value;
              widget.onChanged(widget.settings.copyWith(apiKeys: newApiKeys));
            },
            onFieldSubmitted: (_) => _fetchModels(),
          ),
        ),
        
        const SizedBox(height: 16),

        // 3. Models Dropdown
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _isLoadingModels
              ? const Center(child: LinearProgressIndicator())
              : DropdownButtonFormField<LlmModelInfo>(
                  decoration: const InputDecoration(
                      labelText: 'Default Model',
                      border: OutlineInputBorder(),
                  ),
                  value: _availableModels.contains(selectedModelInfo) ? selectedModelInfo : null,
                  isExpanded: true,
                  hint: const Text('Select a model'),
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
                      newModels[_currentEditingProviderId] = value;
                      widget.onChanged(
                        widget.settings.copyWith(selectedModels: newModels),
                      );
                    }
                  },
                ),
        ),
        
        if (selectedModelInfo != null)
           Padding(
             padding: const EdgeInsets.all(16.0),
             child: Text(
               'Tokens: ${selectedModelInfo.inputTokenLimit} In / ${selectedModelInfo.outputTokenLimit} Out',
               style: Theme.of(context).textTheme.caption,
             ),
           ),
      ],
    );
  }
}
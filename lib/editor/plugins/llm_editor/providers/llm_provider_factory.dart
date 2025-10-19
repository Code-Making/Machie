// =========================================
// UPDATED: lib/editor/plugins/llm_editor/providers/llm_provider_factory.dart
// =========================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/editor/plugins/llm_editor/providers/llm_provider.dart';
import 'package:machine/settings/settings_notifier.dart';

// A simple list of all available provider instances.
final allLlmProviders = [
  DummyProvider(),
  GeminiProvider(''),
];

// The main service provider that the UI will use.
final llmServiceProvider = Provider.autoDispose<LlmProvider>((ref) {
  final providerConfig = ref.watch(settingsProvider.select((s) {
    final settings = s.pluginSettings[LlmEditorSettings] as LlmEditorSettings?;
    final id = settings?.selectedProviderId ?? 'dummy';
    final key = settings?.apiKeys[id] ?? '';
    // Return a record for easy comparison.
    return (id: id, key: key);
  }));

  final selectedId = providerConfig.id;
  final apiKey = providerConfig.key;

  switch (selectedId) {
    case 'gemini': // NEW: Handle Gemini case
      return GeminiProvider(apiKey);
    case 'dummy':
    default:
      return DummyProvider();
  }
});
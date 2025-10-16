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
  OpenAiProvider(''),
  GeminiProvider(''), // NEW: Add Gemini provider
];

// The main service provider that the UI will use.
final llmServiceProvider = Provider.autoDispose<LlmProvider>((ref) {
  final settings = ref.watch(
    settingsProvider.select(
      (s) => s.pluginSettings[LlmEditorSettings] as LlmEditorSettings?,
    ),
  );

  final selectedId = settings?.selectedProviderId ?? 'dummy';
  final apiKey = settings?.apiKeys[selectedId] ?? '';

  switch (selectedId) {
    case 'openai':
      return OpenAiProvider(apiKey);
    case 'gemini': // NEW: Handle Gemini case
      return GeminiProvider(apiKey);
    case 'dummy':
    default:
      return DummyProvider();
  }
});
// =========================================
// UPDATED: lib/editor/plugins/llm_editor/providers/llm_provider_factory.dart
// =========================================

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import '../llm_editor_models.dart';
import 'llm_provider.dart';
import '../../../../settings/settings_notifier.dart';

// A simple list of all available provider instances.
final allLlmProviders = [DummyProvider(), GeminiProvider('')];

// The main service provider that the UI will use.
final llmServiceProvider = Provider.autoDispose<LlmProvider>((ref) {
  final providerConfig = ref.watch(
    settingsProvider.select((s) {
      final settings =
          s.pluginSettings[LlmEditorSettings] as LlmEditorSettings?;
      final id = settings?.selectedProviderId ?? 'dummy';
      final key = settings?.apiKeys[id] ?? '';
      // Return a record for easy comparison.
      return (id: id, key: key);
    }),
  );

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

// =========================================
// NEW FILE: lib/editor/plugins/llm_editor/llm_editor_plugin.dart
// =========================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/command/command_models.dart';
import 'package:machine/data/cache/type_adapters.dart';
import 'package:machine/data/dto/tab_hot_state_dto.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/editor/editor_tab_models.dart';
import 'package:machine/editor/plugins/plugin_models.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_hot_state.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_models.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_settings_widget.dart';
import 'package:machine/editor/plugins/llm_editor/llm_editor_widget.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/editor/tab_state_manager.dart';
import 'package:machine/project/project_models.dart';
import 'package:machine/settings/settings_notifier.dart';
import 'package:machine/editor/plugins/llm_editor/providers/llm_provider_factory.dart';
import 'package:machine/editor/plugins/llm_editor/providers/llm_provider.dart';

// 1. Define a helper class to parse the structured JSON response.
@immutable
class _StructuredModificationResponse {
  final String modifiedText;
  final String? explanation;

  const _StructuredModificationResponse({required this.modifiedText, this.explanation});

  factory _StructuredModificationResponse.fromJson(Map<String, dynamic> json) {
    return _StructuredModificationResponse(
      modifiedText: json['modifiedText'] as String? ?? '',
      explanation: json['explanation'] as String?,
    );
  }
}


class LlmEditorPlugin extends EditorPlugin {
  @override
  String get id => 'com.machine.llm_editor';
  @override
  String get name => 'LLM Chat';
  @override
  Widget get icon => const Icon(Icons.chat_bubble_outline);
  @override
  int get priority => 2; // High priority for its specific file type.

  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.endsWith('.llm');
  }

  @override
  PluginSettings? get settings => LlmEditorSettings();
  
  
  @override
  Widget buildSettingsUI(PluginSettings settings) {
    return LlmEditorSettingsUI(settings: settings as LlmEditorSettings);
  }
  
  static Future<String> applyModification(
    WidgetRef ref, {
    required String prompt,
    required String inputText,
  }) async {
    final settings = ref.read(settingsProvider).pluginSettings[LlmEditorSettings] as LlmEditorSettings?;
    if (settings == null) {
      MachineToast.error('LLM settings are not configured.');
      return inputText;
    }

    // Handle the dummy model case as requested.
    if (settings.selectedProviderId == 'dummy') {
      return "This model is for testing, switch to an actual model for a response";
    }
    
    final model = settings.selectedModels[settings.selectedProviderId];
    if (model == null) {
      MachineToast.error('No LLM model selected. Please configure one in the settings.');
      return inputText;
    }

    // Temporarily create a provider instance based on current settings.
    final apiKey = settings.apiKeys[settings.selectedProviderId] ?? '';
    final LlmProvider provider;
    switch (settings.selectedProviderId) {
      case 'gemini':
        provider = GeminiProvider(apiKey);
        break;
      default:
        // This case should be unreachable due to the dummy check above.
        return inputText;
    }

    // Define the JSON schema for the expected output.
    final responseSchema = {
      'type': 'OBJECT',
      'properties': {
        'modifiedText': {'type': 'STRING'},
        'explanation': {'type': 'STRING'},
      },
      'required': ['modifiedText']
    };

    // Construct the full prompt for the model.
    final fullPrompt = '$prompt\n\nHere is the text to modify:\n\n---\n$inputText\n---';
    
    try {
      final jsonString = await provider.generateStructuredResponse(
        prompt: fullPrompt,
        model: model,
        responseSchema: responseSchema,
      );

      final parsedResponse = _StructuredModificationResponse.fromJson(jsonDecode(jsonString));
      
      // We only return the modified text as per the function's contract.
      // The explanation is available if you need to log or display it.
      return parsedResponse.modifiedText;

    } catch (e) {
      MachineToast.error('Failed to apply modification: $e');
      // On failure, return the original text to prevent data loss.
      return inputText;
    }
  }

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    List<ChatMessage> messagesToShow;
    final hotState = initData.hotState as LlmEditorHotStateDto?;

    // THE FIX: Decide which message list to use right here.
    if (hotState != null && hotState.messages.isNotEmpty) {
      // If cached state exists, it takes priority.
      messagesToShow = hotState.messages;
    } else {
      // Otherwise, parse from the file content.
      List<ChatMessage> messagesFromFile = [];
      final content = initData.stringData;
      if (content != null && content.isNotEmpty) {
        try {
          final List<dynamic> jsonList = jsonDecode(content);
          messagesFromFile = jsonList.map((item) => ChatMessage.fromJson(item)).toList();
        } catch (e) {
          messagesFromFile.add(
            ChatMessage(
              role: 'assistant',
              content: 'Error: Could not parse .llm file. Starting a new chat. \n\nDetails: $e',
            ),
          );
        }
      }
      messagesToShow = messagesFromFile;
    }

    // Pass the resolved list of messages to the tab.
    return LlmEditorTab(
      plugin: this,
      initialMessages: messagesToShow,
      id: id,
      onReadyCompleter: onReadyCompleter,
    );
  }
  
    LlmEditorWidgetState? _getActiveEditorState(WidgetRef ref) {
    final tab = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab));
    if (tab is! LlmEditorTab) return null;
    return tab.editorKey.currentState as LlmEditorWidgetState?;
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    final llmTab = tab as LlmEditorTab;
    return LlmEditorWidget(key: llmTab.editorKey, tab: llmTab);
  }
  
    List<Command> getCommands() => [
    BaseCommand(
      id: 'save',
      label: 'Save Chat',
      icon: const Icon(Icons.save),
      defaultPositions: [AppCommandPositions.appBar],
      sourcePlugin: id,
      execute: (ref) async => ref.read(editorServiceProvider).saveCurrentTab(),
      canExecute: (ref) {
        final currentTabId = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab?.id));
        if (currentTabId == null) return false;
        final metadata = ref.watch(tabMetadataProvider.select((m) => m[currentTabId]));
        return (metadata?.isDirty ?? false) && metadata?.file is! VirtualDocumentFile;
      },
    ),
    BaseCommand(
      id: 'save_as',
      label: 'Save Chat As...',
      icon: const Icon(Icons.save_as),
      defaultPositions: [AppCommandPositions.appBar],
      sourcePlugin: id,
      execute: (ref) async {
        final editorState = _getActiveEditorState(ref);
        if (editorState == null) return;
        await ref.read(editorServiceProvider).saveCurrentTabAs(
          stringDataProvider: () async {
            final content = await editorState.getContent();
            return (content is EditorContentString) ? content.content : null;
          },
        );
      },
      canExecute: (ref) => _getActiveEditorState(ref) != null,
    ),
    BaseCommand(
      id: 'jump_to_next_code',
      label: 'Next Code Block',
      icon: const Icon(Icons.keyboard_arrow_down),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute: (ref) async => _getActiveEditorState(ref)?.jumpToNextTarget(),
      canExecute: (ref) => _getActiveEditorState(ref) != null,
    ),
    BaseCommand(
      id: 'jump_to_prev_code',
      label: 'Previous Code Block',
      icon: const Icon(Icons.keyboard_arrow_up),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      execute: (ref) async => _getActiveEditorState(ref)?.jumpToPreviousTarget(),
      canExecute: (ref) => _getActiveEditorState(ref) != null,
    ),
  ];

  // --- Hot State Caching ---
  @override
  String? get hotStateDtoType => 'com.machine.llm_editor_state';
  @override
  Type? get hotStateDtoRuntimeType => LlmEditorHotStateDto;
  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => LlmEditorHotStateAdapter();
}
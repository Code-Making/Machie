// =========================================
// NEW FILE: lib/editor/plugins/llm_editor/llm_editor_plugin.dart
// =========================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/dto/tab_hot_state_dto.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/repositories/project_repository.dart';
import '../../../explorer/common/file_explorer_dialogs.dart';
import '../../../project/project_models.dart';
import '../../../settings/settings_notifier.dart';
import '../../../utils/toast.dart';
import '../../editor_tab_models.dart';
import '../../services/editor_service.dart';
import '../../services/text_editing_capability.dart';
import '../../tab_state_manager.dart';
import '../plugin_models.dart';
import 'llm_editor_hot_state.dart';
import 'llm_editor_models.dart';
import 'llm_editor_settings_widget.dart';
import 'llm_editor_widget.dart';
import 'providers/llm_provider.dart';
import 'providers/llm_provider_factory.dart';
import '../../../logs/logs_provider.dart';

@immutable
class LlmModificationRequest {
  final String prompt;
  final String inputText;

  const LlmModificationRequest({required this.prompt, required this.inputText});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmModificationRequest &&
          runtimeType == other.runtimeType &&
          prompt == other.prompt &&
          inputText == other.inputText;

  @override
  int get hashCode => prompt.hashCode ^ inputText.hashCode;
}

final llmModificationProvider = FutureProvider.autoDispose
    .family<String, LlmModificationRequest>((ref, request) async {
  // This provider encapsulates the entire async "use case".
  // Because it's a FutureProvider, Riverpod will automatically keep its
  // dependencies (like llmServiceProvider) alive until the future completes.

  final settings = ref.watch(settingsProvider).pluginSettings[LlmEditorSettings] as LlmEditorSettings?;
  if (settings == null) {
    throw Exception('LLM settings are not configured.');
  }

  final model = settings.selectedModels[settings.selectedProviderId];
  if (model == null) {
    throw Exception('No LLM model selected. Please configure one in the settings.');
  }

  // Here, we read the auto-disposing provider. Riverpod ensures it stays
  // alive because this FutureProvider is actively being awaited.
  final provider = ref.watch(llmServiceProvider);

  final fullPrompt = 'You are an expert code modification assistant. Your task is to modify the user-provided code based on their instructions. '
                     'You MUST respond with ONLY the modified code, enclosed in a single markdown code block. Do not include any explanations, apologies, or introductory text outside of the code block.'
                     '\n\nUser instructions: "${request.prompt}"'
                     '\n\nHere is the code to modify:\n\n---\n${request.inputText}\n---';
  
  final rawResponse = await provider.generateSimpleResponse(
    prompt: fullPrompt,
    model: model,
  );

  return LlmEditorPlugin._extractCodeFromMarkdown(rawResponse) ?? request.inputText;
});

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

  /// Extracts code from markdown code blocks in a string.
  /// If multiple blocks are found, they are concatenated.
  static String? _extractCodeFromMarkdown(String markdown) {
    final codeBlockRegex = RegExp(r'```(?:[a-zA-Z]+)?\n([\s\S]*?)```');
    final matches = codeBlockRegex.allMatches(markdown);

    if (matches.isEmpty) {
      // As a fallback, if no fenced code blocks are found,
      // return the whole string trimmed, assuming the model obeyed the prompt.
      final trimmed = markdown.trim();
      return trimmed.isNotEmpty ? trimmed : null;
    }

    return matches.map((match) => match.group(1)?.trim()).where((code) => code != null).join('\n');
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
    BaseTextEditableCommand(
      id: 'llm_refactor_selection',
      label: 'Refactor Selection',
      icon: const Icon(Icons.auto_fix_high),
      // We want this button to appear on the Code Editor's selection toolbar.
      defaultPositions: [AppCommandPositions.pluginToolbar], 
      sourcePlugin: id, // The command originates from the LLM plugin.
      canExecute: (ref, context) {
        return context.hasSelection;
      },
      execute: (ref, textEditable) async {
        try {
          final selectedText = await textEditable.getSelectedText();
          if (selectedText.isEmpty) return;

          final context = ref.read(navigatorKeyProvider).currentContext;
          if (context == null || !context.mounted) return;

          final userPrompt = await showTextInputDialog(
            context,
            title: 'Refactor Selection',
          );

          if (userPrompt == null || userPrompt.trim().isEmpty) return;

          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const PopScope( /* ... loading dialog ... */ ),
          );
        
          // Create the request object
          final request = LlmModificationRequest(prompt: userPrompt, inputText: selectedText);
          
          // Execute the use case by reading the FutureProvider's future.
          // Riverpod handles the entire lifecycle for us.
          final modifiedText = await ref.read(llmModificationProvider(request).future);
          
          if (context.mounted) Navigator.of(context).pop(); // Close loading dialog

          if (modifiedText != selectedText) {
            textEditable.replaceSelection(modifiedText);
          } else {
            MachineToast.info("AI did not suggest any changes.");
          }
        } catch (e, st) {
          final context = ref.read(navigatorKeyProvider).currentContext;
          if (context != null && context.mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
          }
          MachineToast.error("Refactor failed: ${e.toString().split(':').last}");
          ref.read(talkerProvider).handle(e, st, "[LlmRefactorCommand]");
        }
      },
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
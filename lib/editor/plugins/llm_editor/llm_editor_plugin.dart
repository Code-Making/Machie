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
import 'package:machine/utils/toast.dart';
import '../../services/text_editing_capability.dart';
import '../../../explorer/common/file_explorer_dialogs.dart';
import '../../../data/repositories/project_repository.dart';


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

    final model = settings.selectedModels[settings.selectedProviderId];
    if (model == null) {
      MachineToast.error('No LLM model selected. Please configure one in the settings.');
      return inputText;
    }

    final provider = ref.read(llmServiceProvider);
    
    // We add a system instruction to the prompt to guide the model's output.
    final fullPrompt = 'You are an expert code modification assistant. Your task is to modify the user-provided code based on their instructions. '
                       'You MUST respond with ONLY the modified code, enclosed in a single markdown code block. Do not include any explanations, apologies, or introductory text outside of the code block.'
                       '\n\nUser instructions: "$prompt"'
                       '\n\nHere is the code to modify:\n\n---\n$inputText\n---';
    
    try {
      final rawResponse = await provider.generateSimpleResponse(
        prompt: fullPrompt,
        model: model,
      );

      // Now, parse the response to extract code blocks.
      return _extractCodeFromMarkdown(rawResponse) ?? inputText;

    } catch (e) {
      MachineToast.error('Failed to apply modification: $e');
      return inputText; // Return original text on failure.
    }
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
      icon: const Icon(Icons.auto_awesome),
      // We want this button to appear on the Code Editor's selection toolbar.
      defaultPositions: [AppCommandPositions.pluginToolbar], 
      sourcePlugin: id, // The command originates from the LLM plugin.
      canExecute: (ref, context) {
        return context.hasSelection;
      },
      execute: (ref, textEditable) async {
        final selectedText = await textEditable.getSelectedText();
        if (selectedText.isEmpty) return;
        
        final context = ref.read(navigatorKeyProvider).currentContext;
        if (context == null || !context.mounted) return;

        final project = ref.read(appNotifierProvider).value!.currentProject!;
        final activeTab = project.session.currentTab!;
        final activeFile = ref.read(tabMetadataProvider)[activeTab.id]!.file;
        final repo = ref.read(projectRepositoryProvider)!;

        // 2. Get the display path of the file relative to the project root
        final displayPath = repo.fileHandler.getPathForDisplay(activeFile.uri, relativeTo: project.rootUri);

        // 1. Ask the user for their modification instructions.
        final userPrompt = await showTextInputDialog(
          context,
          title: 'Refactor Selection',
        );

        if (userPrompt == null || userPrompt.trim().isEmpty) {
          return; // User cancelled.
        }

        // 2. Show a loading indicator to the user.
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const PopScope(
            canPop: false,
            child: AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 24),
                  Text("Applying AI modification..."),
                ],
              ),
            ),
          ),
        );
        
        try {
          // v-- AUGMENT THE PROMPT SENT TO THE LLM --v
          final fullPrompt = 'The user wants to refactor a selection from the file at path: `$displayPath`.'
                             '\n\nUser instructions: "$userPrompt"'
                             '\n\nHere is the code selection to modify:';
          // ^-- END OF AUGMENTATION --^

          final modifiedText = await LlmEditorPlugin.applyModification(
            ref,
            // Pass the new, more detailed prompt
            prompt: fullPrompt,
            inputText: selectedText,
          );
          
          if (context.mounted) Navigator.of(context).pop();

          if (modifiedText != selectedText) {
            textEditable.replaceSelection(modifiedText);
          } else {
            MachineToast.info("AI did not suggest any changes.");
          }
        } catch (e) {
          // Ensure the dialog is closed even on error.
          if (context.mounted) Navigator.of(context).pop();
          MachineToast.error("An unexpected error occurred.");
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
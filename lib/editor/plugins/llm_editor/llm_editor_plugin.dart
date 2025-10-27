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

  // *** FIX: This function no longer accepts a WidgetRef. ***
  // It now receives the dependencies it needs directly, making it safer to call
  // after an 'await'.
  static Future<String> applyModification({
    required LlmProvider provider,
    required LlmEditorSettings? settings,
    required String prompt,
    required String inputText,
  }) async {
    if (settings == null) {
      throw Exception('LLM settings are not configured.');
    }

    final model = settings.selectedModels[settings.selectedProviderId];
    if (model == null) {
      throw Exception(
        'No LLM model selected. Please configure one in the settings.',
      );
    }

    // We add a system instruction to the prompt to guide the model's output.
    final fullPrompt =
        'You are an expert code modification assistant. Your task is to modify the user-provided code based on their instructions. '
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
      // Re-throw to allow the caller to manage UI state (like closing a loading dialog)
      // and display a more context-aware error.
      rethrow;
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

    return matches
        .map((match) => match.group(1)?.trim())
        .where((code) => code != null)
        .join('\n');
  }

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    List<ChatMessage> messagesToShow;
    LlmEditorHotStateDto hotState;
    if (initData.hotState!=null){
      hotState = initData!.hotState as LlmEditorHotStateDto; 
    }

    if (hotState!=null && hotState.messages.isNotEmpty) {
      // If cached state exists, it takes priority.
      messagesToShow = hotState.messages;
    } else {
      // Otherwise, parse from the file content.
      List<ChatMessage> messagesFromFile = [];
      final stringData = initData.initialContent as EditorContentString;
      final content = stringData.content;
      if (content != null && content.isNotEmpty) {
        try {
          final List<dynamic> jsonList = jsonDecode(content);
          messagesFromFile =
              jsonList.map((item) => ChatMessage.fromJson(item)).toList();
        } catch (e) {
          messagesFromFile.add(
            ChatMessage(
              role: 'assistant',
              content:
                  'Error: Could not parse .llm file. Starting a new chat. \n\nDetails: $e',
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
    final tab = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab,
      ),
    );
    if (tab is! LlmEditorTab) return null;
    return tab.editorKey.currentState;
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
        final currentTabId = ref.watch(
          appNotifierProvider.select(
            (s) => s.value?.currentProject?.session.currentTab?.id,
          ),
        );
        if (currentTabId == null) return false;
        final metadata = ref.watch(
          tabMetadataProvider.select((m) => m[currentTabId]),
        );
        return (metadata?.isDirty ?? false) &&
            metadata?.file is! VirtualDocumentFile;
      },
    ),
    //FIXME: BaseCommand(
    //   id: 'save_as',
    //   label: 'Save Chat As...',
    //   icon: const Icon(Icons.save_as),
    //   defaultPositions: [AppCommandPositions.appBar],
    //   sourcePlugin: id,
    //   execute: (ref) async {
    //     final editorState = _getActiveEditorState(ref);
    //     if (editorState == null) return;
    //     await ref.read(editorServiceProvider).saveCurrentTabAs(
    //       stringDataProvider: () async {
    //         final content = await editorState.getContent();
    //         return (content is EditorContentString) ? content.content : null;
    //       },
    //     );
    //   },
    //   canExecute: (ref) => _getActiveEditorState(ref) != null,
    // ),
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
      execute:
          (ref) async => _getActiveEditorState(ref)?.jumpToPreviousTarget(),
      canExecute: (ref) => _getActiveEditorState(ref) != null,
    ),
    BaseTextEditableCommand(
      id: 'llm_refactor_selection',
      label: 'Refactor Selection',
      icon: const Icon(Icons.auto_fix_high),
      defaultPositions: [AppCommandPositions.pluginToolbar],
      sourcePlugin: id,
      canExecute: (ref, context) {
        return context.hasSelection;
      },
      execute: (ref, textEditable) async {
        final selectedText = await textEditable.getSelectedText();
        if (selectedText.isEmpty) return;

        // Grab the context and all dependencies from ref BEFORE the first await.
        final context = ref.read(navigatorKeyProvider).currentContext;
        // *** FIX: Get dependencies from ref BEFORE the first await ***
        final settings =
            ref.read(settingsProvider).pluginSettings[LlmEditorSettings]
                as LlmEditorSettings?;
        final provider = ref.read(llmServiceProvider);
        final project = ref.read(appNotifierProvider).value!.currentProject!;
        final activeTab = project.session.currentTab!;
        final activeFile = ref.read(tabMetadataProvider)[activeTab.id]!.file;
        final repo = ref.read(projectRepositoryProvider)!;

        if (context == null || !context.mounted) return;

        // Gather non-UI info.
        final displayPath = repo.fileHandler.getPathForDisplay(
          activeFile.uri,
          relativeTo: project.rootUri,
        );

        // 1. Ask the user for their modification instructions.
        final userPrompt = await showTextInputDialog(
          context,
          title: 'Refactor Selection',
        );

        if (userPrompt == null || userPrompt.trim().isEmpty) {
          return; // User cancelled.
        }

        // After an async gap, we must re-check if the context is still valid.
        if (!context.mounted) return;

        var isCancelled = false;
        // 2. Show a loading indicator.
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (ctx) => PopScope(
                canPop: false,
                child: AlertDialog(
                  content: const Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 24),
                      Text("Applying AI modification..."),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        isCancelled = true;
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Stop'),
                    ),
                  ],
                ),
              ),
        );

        try {
          final fullPrompt =
              'The user wants to refactor a selection from the file at path: `$displayPath`.'
              '\n\nUser instructions: "$userPrompt"'
              '\n\nHere is the code selection to modify:';

          // *** FIX: Pass the actual provider and settings, not the ref ***
          final modifiedText = await LlmEditorPlugin.applyModification(
            provider: provider,
            settings: settings,
            prompt: fullPrompt,
            inputText: selectedText,
          );

          if (context.mounted) Navigator.of(context).pop();

          if (isCancelled) return;

          if (modifiedText != selectedText) {
            textEditable.replaceSelection(modifiedText);
          } else {
            MachineToast.info("AI did not suggest any changes.");
          }
        } catch (e) {
          if (context.mounted) Navigator.of(context).pop();
          if (isCancelled) return;
          MachineToast.error("Failed to apply AI modification: $e");
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
  TypeAdapter<TabHotStateDto>? get hotStateAdapter =>
      LlmEditorHotStateAdapter();
}

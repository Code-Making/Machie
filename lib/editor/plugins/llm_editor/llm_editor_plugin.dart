import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../../data/cache/type_adapters.dart';
import '../../../data/file_handler/file_handler.dart';
import '../../../data/repositories/project/project_repository.dart';
import '../../../project/project_models.dart';
import '../../../settings/settings_notifier.dart';
import '../../../utils/cancel_token.dart'; // Import the new class
import '../../../utils/toast.dart';
import '../../../widgets/dialogs/file_explorer_dialogs.dart';
import '../../models/editor_plugin_models.dart';
import '../../models/editor_tab_models.dart';
import '../../models/text_editing_capability.dart';
import '../../services/editor_service.dart';
import '../../tab_metadata_notifier.dart';
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
  int get priority => 2;

  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.endsWith('.llm');
  }

  @override
  PluginSettings? get settings => LlmEditorSettings();

  @override
  Widget buildSettingsUI(
    PluginSettings settings,
    void Function(PluginSettings) onChanged,
  ) => LlmEditorSettingsUI(
    settings: settings as LlmEditorSettings,
    onChanged: onChanged,
  );

  static Future<String> applyModification({
    required LlmProvider provider,
    required LlmEditorSettings? settings,
    required String prompt,
    required String inputText,
    CancelToken? cancelToken, // Pass it down
  }) async {
    if (settings == null) {
      throw Exception('LLM settings are not configured.');
    }

    // FIX: Use refactorProviderId here
    final model = settings.selectedModels[settings.refactorProviderId];
    if (model == null) {
      throw Exception(
        'No Refactoring model selected. Please configure the "Provider (for Code Edits)" in settings.',
      );
    }

    final fullPrompt =
        'You are an expert code modification assistant. Your task is to modify the user-provided code based on their instructions. '
        'You MUST respond with ONLY the modified code, enclosed in a single markdown code block. Do not include any explanations, apologies, or introductory text outside of the code block.'
        '\n\nUser instructions: "$prompt"'
        '\n\nHere is the code to modify:\n\n---\n$inputText\n---';

    try {
    final rawResponse = await provider.generateSimpleResponse(
      prompt: fullPrompt,
      model: model,
      cancelToken: cancelToken, // Pass it here
    );

      return _extractCodeFromMarkdown(rawResponse) ?? inputText;
    } catch (e) {
      rethrow;
    }
  }

  static String? _extractCodeFromMarkdown(String markdown) {
    final codeBlockRegex = RegExp(r'```(?:[a-zA-Z]+)?\n([\s\S]*?)```');
    final matches = codeBlockRegex.allMatches(markdown);

    if (matches.isEmpty) {
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
    List<ChatMessage> messagesToShow = [];
    String? initialProviderId;
    LlmModelInfo? initialModel;

    if (initData.hotState is LlmEditorHotStateDto) {
      final hotState = initData.hotState as LlmEditorHotStateDto;
      messagesToShow = hotState.messages;
      initialProviderId = hotState.selectedProviderId;
      initialModel = hotState.selectedModel;
    } else {
      final stringData = initData.initialContent as EditorContentString;
      final content = stringData.content;
      if (content.isNotEmpty) {
        try {
          final decoded = jsonDecode(content);
          if (decoded is List) {
             // Legacy format support
             messagesToShow = decoded.map((i) => ChatMessage.fromJson(i)).toList();
          } else if (decoded is Map<String, dynamic>) {
             // New Format
             if (decoded.containsKey('messages')) {
               messagesToShow = (decoded['messages'] as List).map((i) => ChatMessage.fromJson(i)).toList();
             }
             initialProviderId = decoded['providerId'];
             if (decoded['model'] != null) {
                try {
                  initialModel = LlmModelInfo.fromJson(decoded['model']);
                } catch(_) {}
             }
          }
        } catch (e) {
          messagesToShow.add(
            ChatMessage(
              role: 'assistant',
              content:
                  'Error: Could not parse .llm file. Starting a new chat. \n\nDetails: $e',
            ),
          );
        }
      }
    }

    return LlmEditorTab(
      plugin: this,
      initialMessages: messagesToShow,
      initialProviderId: initialProviderId,
      initialModel: initialModel,
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

  @override
  List<Command> getCommands(Ref ref) => [
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
      canExecute: (ref, context) => context.hasSelection,
      execute: (ref, textEditable) async {
        final selectedText = await textEditable.getSelectedText();
        if (selectedText.isEmpty) return;

        final context = ref.read(navigatorKeyProvider).currentContext;
        final settings =
            ref
                    .read(effectiveSettingsProvider)
                    .pluginSettings[LlmEditorSettings]
                as LlmEditorSettings?;
        // For refactoring, we use the global provider settings via factory
        final provider = ref.read(llmServiceProvider);
        
        final project = ref.read(appNotifierProvider).value!.currentProject!;
        final activeTab = project.session.currentTab!;
        final activeFile = ref.read(tabMetadataProvider)[activeTab.id]!.file;
        final repo = ref.read(projectRepositoryProvider)!;

        if (context == null || !context.mounted) return;

        final displayPath = repo.fileHandler.getPathForDisplay(
          activeFile.uri,
          relativeTo: project.rootUri,
        );

        final userPrompt = await showTextInputDialog(
          context,
          title: 'Refactor Selection',
        );

        if (userPrompt == null || userPrompt.trim().isEmpty) {
          return;
        }

        if (!context.mounted) return;

        final cancelToken = CancelToken();

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
                    cancelToken.cancel();
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

          final modifiedText = await LlmEditorPlugin.applyModification(
            provider: provider,
            settings: settings,
            prompt: fullPrompt,
            inputText: selectedText,
            cancelToken: cancelToken,
          );

          if (context.mounted) Navigator.of(context).pop();

          if (modifiedText != selectedText) {
            textEditable.replaceSelection(modifiedText);
          } else {
            MachineToast.info("AI did not suggest any changes.");
          }
        } catch (e) {
          // Pop the dialog on error
          if (context.mounted) Navigator.of(context).pop();
          
          // Don't show an error toast if the error was due to cancellation
          if (e is Exception && e.toString().contains("cancelled")) {
            MachineToast.info("AI modification cancelled.");
          } else {
            MachineToast.error("Failed to apply AI modification: $e");
          }
        }
      },
    ),
  ];

  @override
  String? get hotStateDtoType => 'com.machine.llm_editor_state';
  @override
  Type? get hotStateDtoRuntimeType => LlmEditorHotStateDto;
  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter =>
      LlmEditorHotStateAdapter();
}
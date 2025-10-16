// =========================================
// NEW FILE: lib/editor/plugins/llm_editor/llm_editor_plugin.dart
// =========================================

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

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
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
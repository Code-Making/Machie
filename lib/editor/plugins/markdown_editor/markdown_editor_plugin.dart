// =========================================
// NEW FILE: lib/editor/plugins/markdown_editor/markdown_editor_plugin.dart
// =========================================
import 'package:machine/app/app_notifier.dart';
import 'package:machine/editor/tab_state_manager.dart';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/command/command_models.dart';
import 'package:machine/data/cache/type_adapters.dart';
import 'package:machine/data/dto/tab_hot_state_dto.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/editor/editor_tab_models.dart';
import 'package:machine/editor/plugins/markdown_editor/markdown_editor_models.dart';
import 'package:machine/editor/plugins/markdown_editor/markdown_editor_widget.dart';
import 'package:machine/editor/plugins/plugin_models.dart';
import 'package:machine/editor/services/editor_service.dart'; // <-- THE MISSING IMPORT

class MarkdownEditorPlugin implements EditorPlugin {
  @override
  String get name => 'Markdown Editor';

  @override
  Widget get icon => const Icon(Icons.article_outlined);

  @override
  PluginDataRequirement get dataRequirement => PluginDataRequirement.string;

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.toLowerCase().endsWith('.md');
  }

  @override
  Future<EditorTab> createTab(DocumentFile file, dynamic data, {String? id}) async {
    final markdownContent = data as String? ?? '';
    
    // Use the AppFlowy converter to parse the markdown string into a Document object.
    final document = markdownToDocument(markdownContent);
    
    return MarkdownEditorTab(
      plugin: this,
      initialDocument: document,
      id: id,
    );
  }

  @override
  Widget buildEditor(EditorTab tab, WidgetRef ref) {
    final markdownTab = tab as MarkdownEditorTab;
    return MarkdownEditorWidget(
      key: markdownTab.editorKey,
      tab: markdownTab,
    );
  }

  // --- Methods to be implemented in future installments ---

  // ADDED: Helper to get the state of the currently active editor widget.
  MarkdownEditorWidgetState? _getActiveEditorState(WidgetRef ref) {
    final tab = ref.watch(
      appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab),
    );
    if (tab is! MarkdownEditorTab) return null;
    return tab.editorKey.currentState as MarkdownEditorWidgetState?;
  }

  @override
  List<Command> getCommands() {
    return [
      BaseCommand(
        id: 'save',
        label: 'Save',
        icon: const Icon(Icons.save),
        defaultPosition: CommandPosition.appBar,
        sourcePlugin: runtimeType.toString(),
        execute: (ref) async {
          final editorState = _getActiveEditorState(ref);
          if (editorState == null) return;
          
          final project = ref.read(appNotifierProvider).value!.currentProject!;
          final content = editorState.getMarkdownContent();
          
          await ref
              .read(editorServiceProvider)
              .saveCurrentTab(project, content: content);
        },
        canExecute: (ref) {
          final tab = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab));
          if (tab == null) return false;
          // The command is enabled if the corresponding tab's metadata is dirty.
          final metadata = ref.watch(tabMetadataProvider.select((m) => m[tab.id]));
          return metadata?.isDirty ?? false;
        },
      ),
    ];
  }

// ... inside MarkdownEditorPlugin class ...

  @override
  Widget buildToolbar(WidgetRef ref) {
    // The toolbar is now built inside the main editor widget,
    // so this plugin doesn't need a separate bottom toolbar.
    return const SizedBox.shrink();
  }

// ... rest of the file ...
  
  @override
  void activateTab(EditorTab tab, Ref ref) {}

  @override
  void deactivateTab(EditorTab tab, Ref ref) {}

  @override
  void disposeTab(EditorTab tab) {}

  @override
  Future<void> dispose() async {}

  @override
  PluginSettings? get settings => null;

  @override
  Widget buildSettingsUI(PluginSettings settings) => const SizedBox.shrink();

  @override
  List<FileContextCommand> getFileContextMenuCommands(DocumentFile item) => [];
  
  @override
  Future<EditorTab> createTabFromSerialization(Map<String, dynamic> tabJson, FileHandler fileHandler) async {
    // This will be implemented fully when we handle persistence.
    throw UnimplementedError();
  }
  
  @override
  String? get hotStateDtoType => null; // To be implemented in Installment 3

  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => null; // To be implemented in Installment 3
  
  @override
  Future<TabHotStateDto?> serializeHotState(EditorTab tab) async {
    return null; // To be implemented in Installment 3
  }
}
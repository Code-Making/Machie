// lib/session/session_models.dart
import 'package:collection/collection.dart';
import 'package:re_editor/re_editor.dart';

import '../plugins/plugin_architecture.dart';
import '../project/file_handler/file_handler.dart';

@immutable
class SessionState {
  final List<EditorTab> tabs;
  final int currentTabIndex;

  const SessionState({
    this.tabs = const [],
    this.currentTabIndex = 0,
  });

  EditorTab? get currentTab =>
      tabs.isNotEmpty && currentTabIndex < tabs.length ? tabs[currentTabIndex] : null;

  SessionState copyWith({
    List<EditorTab>? tabs,
    int? currentTabIndex,
  }) {
    return SessionState(
      tabs: tabs ?? List.from(this.tabs),
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'tabs': tabs.map((t) => t.toJson()).toList(),
        'currentTabIndex': currentTabIndex,
      };
}

@immutable
abstract class EditorTab {
  final DocumentFile file;
  final EditorPlugin plugin;
  final bool isDirty; // CORRECTED: Made final for immutability

  const EditorTab({required this.file, required this.plugin, this.isDirty = false});

  String get contentString;
  void dispose();

  EditorTab copyWith({DocumentFile? file, EditorPlugin? plugin, bool? isDirty});

  Map<String, dynamic> toJson();
}

@immutable
class CodeEditorTab extends EditorTab {
  final CodeLineEditingController controller;
  final CodeCommentFormatter commentFormatter;
  final String? languageKey;

  const CodeEditorTab({
    required super.file,
    required this.controller,
    required super.plugin,
    required this.commentFormatter,
    super.isDirty = false,
    this.languageKey,
  });

  @override
  void dispose() => controller.dispose();
  @override
  String get contentString => controller.text;

  @override
  CodeEditorTab copyWith({
    DocumentFile? file,
    EditorPlugin? plugin,
    bool? isDirty,
    CodeLineEditingController? controller,
    CodeCommentFormatter? commentFormatter,
    String? languageKey,
  }) {
    return CodeEditorTab(
      file: file ?? this.file,
      plugin: plugin ?? this.plugin,
      isDirty: isDirty ?? this.isDirty,
      controller: controller ?? this.controller,
      commentFormatter: commentFormatter ?? this.commentFormatter,
      languageKey: languageKey ?? this.languageKey,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'code',
        'fileUri': file.uri,
        'pluginType': plugin.runtimeType.toString(),
        'languageKey': languageKey,
        'isDirty': isDirty,
      };
}
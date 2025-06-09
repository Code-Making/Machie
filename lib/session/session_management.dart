// lib/session/session_management.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:collection/collection.dart';
import '../app_state/app_state.dart';
import '../file_system/file_handler.dart';
import '../plugins/plugin_architecture.dart';

// The sessionProvider now acts as a proxy to the active project's session
final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

// The LifecycleHandler now triggers saves via the AppNotifier
class LifecycleHandler extends StatefulWidget {
  final Widget child;
  const LifecycleHandler({super.key, required this.child});
  @override
  State<LifecycleHandler> createState() => _LifecycleHandlerState();
}

class _LifecycleHandlerState extends State<LifecycleHandler> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final container = ProviderScope.containerOf(context);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Use the new AppNotifier to save everything on exit
        await container.read(appStateProvider.notifier).saveOnExit();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

// SessionState is now a simple data class representing an editing session's state
@immutable
class SessionState {
  final List<EditorTab> tabs;
  final int currentTabIndex;

  const SessionState({
    this.tabs = const [],
    this.currentTabIndex = 0,
  });

  EditorTab? get currentTab => (tabs.isNotEmpty && currentTabIndex < tabs.length) ? tabs[currentTabIndex] : null;

  SessionState copyWith({
    List<EditorTab>? tabs,
    int? currentTabIndex,
  }) {
    return SessionState(
      tabs: tabs ?? this.tabs,
      currentTabIndex: currentTabIndex ?? this.currentTabIndex,
    );
  }
  
  // Serialization for when it's saved as part of a project
  Map<String, dynamic> toJson() => {
    'tabs': tabs.map((t) => t.toJson()).toList(),
    'currentTabIndex': currentTabIndex,
  };

  // Deserialization - tab content is restored by LocalFileSystemProject
  factory SessionState.fromJson(Map<String, dynamic> json) {
    return SessionState(
      tabs: [], // Tabs are deserialized separately by the project
      currentTabIndex: json['currentTabIndex'] ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionState &&
          currentTabIndex == other.currentTabIndex &&
          const DeepCollectionEquality().equals(tabs, other.tabs);

  @override
  int get hashCode => Object.hash(currentTabIndex, const DeepCollectionEquality().hash(tabs));
}


// SessionNotifier is now a proxy that reflects the active project's session
class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    // Watch the active project and update the session state accordingly
    final activeSession = ref.watch(appStateProvider.select((app) => app.activeProject?.session));
    return activeSession ?? const SessionState();
  }

  // --- All operations are now delegated to the active project ---

  Future<void> openFile(DocumentFile file) async {
    await ref.read(appStateProvider).activeProject?.openFileInSession(file);
  }

  void switchTab(int index) {
    ref.read(appStateProvider).activeProject?.switchTabInSession(index);
  }

  void closeTab(int index) {
    ref.read(appStateProvider).activeProject?.closeTabInSession(index);
  }

  Future<void> saveCurrentTab() async {
    final index = state.currentTabIndex;
    await ref.read(appStateProvider).activeProject?.saveTabInSession(index);
  }

  void reorderTabs(int oldIndex, int newIndex) {
    ref.read(appStateProvider).activeProject?.reorderTabsInSession(oldIndex, newIndex);
  }
}


// --- EditorTab and CodeEditorTab classes remain mostly the same ---
// They are fundamental data structures for a tab.

abstract class EditorTab {
  final DocumentFile file;
  final EditorPlugin plugin;
  bool isDirty;

  EditorTab({required this.file, required this.plugin, this.isDirty = false});
  String get contentString;
  void dispose();

  EditorTab copyWith({DocumentFile? file, EditorPlugin? plugin, bool? isDirty});

  Map<String, dynamic> toJson();
}

class CodeEditorTab extends EditorTab {
  final CodeLineEditingController controller;
  final CodeCommentFormatter commentFormatter;
  final String? languageKey;

  CodeEditorTab({
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
    'fileUri': file.uri,
    'pluginType': plugin.runtimeType.toString(),
    'languageKey': languageKey,
    // Note: dirty state is not saved; files are assumed clean on reopen.
  };
}
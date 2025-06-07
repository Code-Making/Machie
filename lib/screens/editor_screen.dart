import 'package:collection/collection.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart'; // For CodeEditorTapRegion, CodeLineEditingController

import '../file_system/file_handler.dart'; // For DocumentFile
import '../main.dart'; // For sessionProvider, tabBarScrollProvider
import '../plugins/code_editor/code_editor_plugin.dart'; // NEW: For CodeEditorPlugin type check
import '../plugins/plugin_registry.dart'; // For EditorPlugin, activePluginsProvider
import '../plugins/plugin_architecture.dart'; // For EditorPlugin
import '../session/session_management.dart'; // For EditorTab
import '../widgets/file_explorer_drawer.dart'; // For FileExplorerDrawer
import 'settings_screen.dart'; // For DebugLogView
import 'settings_screen.dart'; // For DebugLogView

final tabBarScrollProvider = Provider<ScrollController>((ref) {
  return ScrollController();
});

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentProject = ref.watch(sessionProvider.select((s) => s.currentProject));
    final currentUri = ref.watch(
      sessionProvider.select((s) => s.currentTab?.file.uri), // Use sessionProvider
    );
    final currentName = ref.read(
      sessionProvider.select((s) => s.currentTab?.file.name), // Use sessionProvider
    );
    final currentPlugin = ref.watch(
      sessionProvider.select((s) => s.currentTab?.plugin),
    );

    final scaffoldKey = GlobalKey<ScaffoldState>(); // Add key here

    return Scaffold(
      key: scaffoldKey, // Assign key to Scaffold
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          currentPlugin is CodeEditorPlugin
              ? CodeEditorTapRegion(child: const AppBarCommands())
              : const AppBarCommands(),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed:
                () => showDialog(
                  context: context,
                  builder: (_) => const DebugLogView(),
                ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
        title: Text(currentName != null ? currentName : 'Code Editor'),
      ),
      drawer: FileExplorerDrawer(),
      body: Column(
        children: [
          const TabBarView(),
          Expanded(
            child:
                currentUri != null
                    ? EditorContentSwitcher()
                    : const Center(child: Text('Open file')),
          ),
          if (currentPlugin != null) currentPlugin.buildToolbar(ref),
        ],
      ),
    );
  }
}

class TabBarView extends ConsumerWidget {
  const TabBarView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollController = ref.watch(tabBarScrollProvider);
    final tabs = ref.watch(sessionProvider.select((state) => state.tabs));

    return Container(
      color: Colors.grey[900],
      height: 40,
      child: CodeEditorTapRegion(
        child: ReorderableListView(
          key: const PageStorageKey<String>('tabBarScrollPosition'),
          scrollController: scrollController,
          scrollDirection: Axis.horizontal,
          onReorder:
              (oldIndex, newIndex) => ref
                  .read(sessionProvider.notifier)
                  .reorderTabs(oldIndex, newIndex),
          buildDefaultDragHandles: false,
          children: [
            for (final tab in tabs)
              ReorderableDelayedDragStartListener(
                key: ValueKey(tab.file),
                index: tabs.indexOf(tab),
                child: FileTab(tab: tab, index: tabs.indexOf(tab)),
              ),
          ],
        ),
      ),
    );
  }
}

class FileTab extends ConsumerWidget {
  final EditorTab tab;
  final int index;

  const FileTab({super.key, required this.tab, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ref.watch(
      sessionProvider.select((s) => s.currentTabIndex == index),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
      child: Material(
        color: isActive ? Colors.blueGrey[800] : Colors.grey[900],
        child: InkWell(
          onTap: () => ref.read(sessionProvider.notifier).switchTab(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed:
                      () => ref.read(sessionProvider.notifier).closeTab(index),
                ),
                Expanded(
                  child: Text(
                    tab.file.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: tab.isDirty ? Colors.orange : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getFileName(String uri) =>
      Uri.parse(uri).pathSegments.last.split('/').last;
}

class EditorContentSwitcher extends ConsumerWidget {
  const EditorContentSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUri = ref.watch(
      sessionProvider.select((s) => s.currentTab?.file.uri),
    );

    return KeyedSubtree(
      key: ValueKey(currentUri),
      child: _EditorContentProxy(),
    );
  }
}

class _EditorContentProxy extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.read(sessionProvider).currentTab;
    return tab != null ? tab.plugin.buildEditor(tab, ref) : const SizedBox();
  }
}

class FileTypeIcon extends ConsumerWidget {
  final DocumentFile file;

  const FileTypeIcon({super.key, required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(activePluginsProvider);
    final plugin = plugins.firstWhereOrNull((p) => p.supportsFile(file));

    return plugin?.icon ?? const Icon(Icons.insert_drive_file);
  }
}

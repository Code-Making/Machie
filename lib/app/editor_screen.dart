// lib/screens/editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import 'app_notifier.dart';
import '../plugins/code_editor/code_editor_plugin.dart';
import '../plugins/plugin_models.dart';
import '../session/session_models.dart';
import '../explorer/file_explorer_drawer.dart';
import '../settings/settings_screen.dart';
import '../utils/logs.dart';
import '../command/command_models.dart';
import '../command/command_widgets.dart';

final tabBarScrollProvider = Provider<ScrollController>((ref) {
  return ScrollController();
});

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab));
    final currentPlugin = currentTab?.plugin;
    final scaffoldKey = GlobalKey<ScaffoldState>();

    return Scaffold(
      key: scaffoldKey,
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
            onPressed: () => showDialog(context: context, builder: (_) => const DebugLogView()),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
        title: Text(currentTab?.file.name ?? 'Code Editor'),
      ),
      drawer: const FileExplorerDrawer(),
      body: Column(
        children: [
          const TabBarView(),
          Expanded(
            child: currentTab != null
                ? const EditorContentSwitcher()
                : const Center(child: Text('Open a file to start editing')),
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
    final tabs = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.tabs)) ?? [];

    if (tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.grey[900],
      height: 40,
      child: CodeEditorTapRegion(
        child: ReorderableListView(
          key: const PageStorageKey<String>('tabBarScrollPosition'),
          scrollController: scrollController,
          scrollDirection: Axis.horizontal,
          // CORRECTED: Call the right method
          onReorder: (oldIndex, newIndex) => ref.read(appNotifierProvider.notifier).reorderTabs(oldIndex, newIndex),
          buildDefaultDragHandles: false,
          children: [
            for (int i = 0; i < tabs.length; i++)
              ReorderableDelayedDragStartListener(
                key: ValueKey(tabs[i].file.uri),
                index: i,
                child: FileTab(tab: tabs[i], index: i),
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
    final isActive = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTabIndex == index));

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
      child: Material(
        color: isActive ? Colors.blueGrey[800] : Colors.grey[900],
        child: InkWell(
          // CORRECTED: Call the right method
          onTap: () => ref.read(appNotifierProvider.notifier).switchTab(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => ref.read(appNotifierProvider.notifier).closeTab(index),
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
}

class EditorContentSwitcher extends ConsumerWidget {
  const EditorContentSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUri = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab?.file.uri));

    return KeyedSubtree(
      key: ValueKey(currentUri),
      child: const _EditorContentProxy(),
    );
  }
}

class _EditorContentProxy extends ConsumerWidget {
  const _EditorContentProxy();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(appNotifierProvider.select((s) => s.value?.currentProject?.session.currentTab));
    return tab != null ? tab.plugin.buildEditor(tab, ref) : const SizedBox();
  }
}
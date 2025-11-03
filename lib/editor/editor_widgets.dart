// =========================================
// FILE: lib/editor/editor_widgets.dart
// =========================================

// lib/editor/editor_widgets.dart

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../app/app_notifier.dart';
import '../command/command_models.dart';
import '../explorer/plugins/git_explorer/git_object_file.dart';
import '../project/project_models.dart';
import 'editor_tab_models.dart';
import 'tab_state_manager.dart';

// ... TabBarWidget is unchanged ...
class TabBarWidget extends ConsumerStatefulWidget {
  const TabBarWidget({super.key});

  @override
  ConsumerState<TabBarWidget> createState() => _TabBarWidgetState();
}

class _TabBarWidgetState extends ConsumerState<TabBarWidget> {
  late final ScrollController _scrollController;
  int? _dragStartIndex;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showTabContextMenu(
    BuildContext context,
    WidgetRef ref,
    int targetIndex,
  ) {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    final activeTab = project?.session.currentTab;
    if (project == null || activeTab == null) return;

    final targetTab = project.session.tabs[targetIndex];

    // 1. Get ALL possible commands from the new provider.
    final allCommands = ref.read(allTabContextCommandsProvider);

    // 2. Filter them here in the UI, using the available WidgetRef.
    //    This resolves the type mismatch error.
    final executableCommands =
        allCommands
            .where((cmd) => cmd.canExecuteFor(ref, activeTab, targetTab))
            .toList();

    if (executableCommands.isEmpty) return;

    // 3. The presentation logic remains the same.
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      ref.read(tabMetadataProvider)[targetTab.id]?.title ??
                          'Tab Options',
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Divider(height: 1),
                  ...executableCommands.map((command) {
                    return ListTile(
                      leading: command.icon,
                      title: Text(command.label),
                      onTap: () {
                        Navigator.pop(ctx);
                        command.executeFor(ref, activeTab, targetTab);
                      },
                    );
                  }),
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs =
        ref.watch(
          appNotifierProvider.select(
            (s) => s.value?.currentProject?.session.tabs,
          ),
        ) ??
        [];

    if (tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Theme.of(
        context,
      ).tabBarTheme.unselectedLabelColor?.withValues(alpha: 0.1),
      height: 32,
      child: CodeEditorTapRegion(
        child: ReorderableListView(
          key: const PageStorageKey<String>('tabBarScrollPosition'),
          scrollController: _scrollController,
          scrollDirection: Axis.horizontal,
          onReorderStart: (index) {
            setState(() => _dragStartIndex = index);
          },
          onReorderEnd: (index) {
            if (_dragStartIndex == index) {
              _showTabContextMenu(context, ref, index);
            }
            setState(() => _dragStartIndex = null);
          },
          onReorder:
              (oldIndex, newIndex) => ref
                  .read(appNotifierProvider.notifier)
                  .reorderTabs(oldIndex, newIndex),
          buildDefaultDragHandles: false,
          children: [
            for (int i = 0; i < tabs.length; i++)
              ReorderableDelayedDragStartListener(
                // REFACTORED: The key is still the stable tab ID.
                key: ValueKey(tabs[i].id),
                index: i,
                child: TabWidget(tab: tabs[i], index: i),
              ),
          ],
        ),
      ),
    );
  }
}

class TabWidget extends ConsumerWidget {
  final EditorTab tab;
  final int index;

  const TabWidget({super.key, required this.tab, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isActive = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTabIndex == index,
      ),
    );
    // REFACTORED: Watch the metadata for this specific tab ID.
    final metadata = ref.watch(
      tabMetadataProvider.select((map) => map[tab.id]),
    );

    if (metadata == null) {
      // This can happen briefly during tab closing.
      return const SizedBox.shrink();
    }

    final isDirty = metadata.isDirty;
    final title = metadata.title;
    final isVirtual = metadata.file is InternalAppFile;
    final isGit = metadata.file is GitObjectDocumentFile;

    final Color textColor;
    if (isGit) {
      textColor = Colors.lightBlue.shade300;
    } else if (isVirtual) {
      // Virtual files get a special color (e.g., cyan) regardless of dirty state.
      textColor = Colors.lime.shade300;
    } else if (isDirty) {
      // Dirty real files are orange.
      textColor = Colors.orange.shade300;
    } else {
      // Clean real files are the default color.
      textColor = Colors.white70;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(appNotifierProvider.notifier).switchTab(index),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.2),
                width: 1,
              ),
              bottom:
                  isActive
                      ? BorderSide(color: theme.colorScheme.primary, width: 2)
                      : BorderSide.none,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap:
                    () =>
                        ref.read(appNotifierProvider.notifier).closeTab(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 4.0,
                  ),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: isActive ? Colors.white70 : Colors.white54,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  // Use title from metadata
                  title,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(fontSize: 13, color: textColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EditorView extends ConsumerWidget {
  const EditorView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(appNotifierProvider).value?.currentProject;
    if (project == null || project.session.tabs.isEmpty) {
      return const Center(child: Text('Open a file to start editing'));
    }

    return IndexedStack(
      index: project.session.currentTabIndex,
      children: List.generate(project.session.tabs.length, (index) {
        final tab = project.session.tabs[index];
        final bool isActive = index == project.session.currentTabIndex;

        // The KeyedSubtree ensures the State of the editor widget is preserved.
        return KeyedSubtree(
          key: ValueKey(tab.id),
          child: TickerMode(
            // Mute animations and tickers for inactive tabs.
            enabled: isActive,
            child: FocusTraversalGroup(
              // This is the crucial part for focus.
              // It prevents focus from escaping this group via traversal keys.
              policy:
                  OrderedTraversalPolicy(), // or WidgetOrderTraversalPolicy()
              child: tab.plugin.buildEditor(tab, ref),
            ),
          ),
        );
      }),
    );
  }
}

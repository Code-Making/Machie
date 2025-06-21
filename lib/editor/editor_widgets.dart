// lib/screens/editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../app/app_notifier.dart';
import 'editor_tab_models.dart';
import 'tab_state_notifier.dart';

class TabBarWidget extends ConsumerStatefulWidget {
  const TabBarWidget({super.key});

  @override
  ConsumerState<TabBarWidget> createState() => _TabBarWidgetState();
}

class _TabBarWidgetState extends ConsumerState<TabBarWidget> {
  late final ScrollController _scrollController;

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
      color: Theme.of(context).appBarTheme.backgroundColor,
      height: 28,
      child: CodeEditorTapRegion(
        child: ReorderableListView(
          key: const PageStorageKey<String>('tabBarScrollPosition'),
          scrollController: _scrollController,
          scrollDirection: Axis.horizontal,
          onReorder:
              (oldIndex, newIndex) => ref
                  .read(appNotifierProvider.notifier)
                  .reorderTabs(oldIndex, newIndex),
          buildDefaultDragHandles: false,
          children: [
            for (int i = 0; i < tabs.length; i++)
              ReorderableDelayedDragStartListener(
                key: ValueKey(tabs[i].file.uri),
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
    final isActive = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTabIndex == index,
      ),
    );

    final isDirty = ref.watch(
      tabStateProvider.select((stateMap) => stateMap[tab.file.uri] ?? false),
    );

    // REFACTOR: The ConstrainedBox now only has a maxWidth, allowing the tab to shrink.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Material(
        color: isActive ? Colors.blueGrey[800] : Colors.grey[900],
        child: InkWell(
          onTap: () => ref.read(appNotifierProvider.notifier).switchTab(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            // REFACTOR: Row now shrinks to fit its children.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The close button is a fixed size.
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed:
                      () => ref
                          .read(appNotifierProvider.notifier)
                          .closeTab(index),
                ),
                // REFACTOR: Flexible allows the text to take up remaining space
                // up to the ConstrainedBox limit, and then use an ellipsis.
                Flexible(
                  child: Text(
                    tab.file.name,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false, // Ensure text stays on one line.
                    style: TextStyle(
                      fontSize: 13, // Slightly smaller font for a tighter look.
                      color: isDirty ? Colors.orange.shade300 : Colors.white70,
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
    final currentUri = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab?.file.uri,
      ),
    );

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
    final tab = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab,
      ),
    );
    return tab != null ? tab.plugin.buildEditor(tab, ref) : const SizedBox();
  }
}
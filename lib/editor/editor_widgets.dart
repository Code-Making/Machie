// lib/screens/editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../app/app_notifier.dart';
import 'editor_tab_models.dart';
import 'tab_state_notifier.dart';

final tabBarScrollProvider = Provider<ScrollController>((ref) {
  return ScrollController();
});

class TabBarWidget extends ConsumerWidget {
  const TabBarWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scrollController = ref.watch(tabBarScrollProvider);
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
      color: Colors.grey[900],
      height: 40,
      child: CodeEditorTapRegion(
        child: ReorderableListView(
          key: const PageStorageKey<String>('tabBarScrollPosition'),
          scrollController: scrollController,
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

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
      child: Material(
        color: isActive ? Colors.blueGrey[800] : Colors.grey[900],
        child: InkWell(
          onTap: () => ref.read(appNotifierProvider.notifier).switchTab(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed:
                      () => ref
                          .read(appNotifierProvider.notifier)
                          .closeTab(index),
                ),
                Expanded(
                  child: Text(
                    tab.file.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDirty ? Colors.orange : Colors.white,
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

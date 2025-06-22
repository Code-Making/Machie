// lib/screens/editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../app/app_notifier.dart';
import 'editor_tab_models.dart';
import 'tab_state_notifier.dart';
import 'tab_state_manager.dart';

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
      color: Theme.of(context).tabBarTheme.unselectedLabelColor?.withOpacity(0.1),
      height: 32,
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
    final theme = Theme.of(context);
    final isActive = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTabIndex == index,
      ),
    );
    // REFACTOR: Watch the consolidated manager for the isDirty flag.
    final isDirty = ref.watch(
      tabStateManagerProvider.select((stateMap) => stateMap[tab.file.uri]?.isDirty ?? false),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => ref.read(appNotifierProvider.notifier).switchTab(index),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 220),
          // REFACTOR: Remove left padding from the container.
          padding: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: theme.dividerColor.withOpacity(0.2),
                width: 1,
              ),
              bottom: isActive
                  ? BorderSide(color: theme.colorScheme.primary, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // REFACTOR: Use GestureDetector and Padding for precise control.
              // This creates a tappable area with no external whitespace.
              GestureDetector(
                behavior: HitTestBehavior.opaque, // Ensures the padding is tappable
                onTap: () =>
                    ref.read(appNotifierProvider.notifier).closeTab(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: isActive ? Colors.white70 : Colors.white54,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  tab.file.name,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 13,
                    color: isActive
                        ? Colors.white
                        : isDirty
                            ? Colors.orange.shade300
                            : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// ... (EditorContentSwitcher and _EditorContentProxy are unchanged)
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
// lib/screens/editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import 'app_notifier.dart';
import '../editor/plugins/code_editor/code_editor_plugin.dart';
import '../editor/editor_widgets.dart';
import '../explorer/explorer_host_drawer.dart';
import '../command/command_widgets.dart';

class AppScreen extends ConsumerWidget {
  const AppScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(
      appNotifierProvider.select(
        (s) => s.value?.currentProject?.session.currentTab,
      ),
    );
    final currentPlugin = currentTab?.plugin;
    final scaffoldKey = GlobalKey<ScaffoldState>();

    final appBarOverride = ref.watch(
      appNotifierProvider.select((s) => s.value?.appBarOverride),
    );

    return Scaffold(
      key: scaffoldKey,
      appBar:
          appBarOverride != null
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(kToolbarHeight),
                  child: appBarOverride,
                )
              : AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => scaffoldKey.currentState?.openDrawer(),
                  ),
                  // REFACTOR: Removed hardcoded buttons. AppBarCommands now handles everything.
                  actions: [
                    currentPlugin is CodeEditorPlugin
                        ? CodeEditorTapRegion(child: const AppBarCommands())
                        : const AppBarCommands(),
                  ],
                  title: Text(currentTab?.file.name ?? 'Machine'),
                ),
      drawer: const ExplorerHostDrawer(),
      body: Column(
        children: [
          const TabBarWidget(),
          Expanded(
            child:
                currentTab != null
                    ? const EditorContentSwitcher()
                    : const Center(child: Text('Open a file to start editing')),
          ),
          // REFACTOR: This now correctly renders the BottomToolbar, not the plugin's toolbar directly.
          if (currentPlugin != null) const BottomToolbar(),
        ],
      ),
    );
  }
}
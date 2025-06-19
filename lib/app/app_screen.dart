// lib/screens/editor_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import 'app_notifier.dart';
import '../editors/plugins/code_editor/code_editor_plugin.dart';
import '../editors/editor_tab_models.dart';
import '../editors/editor_widgets.dart';
import '../editors/tab_state_notifier.dart';
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
      // CORRECTED: The override widget is wrapped in a PreferredSize to satisfy the appBar type requirement.
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
                actions: [
                  currentPlugin is CodeEditorPlugin
                      ? CodeEditorTapRegion(child: const AppBarCommands())
                      : const AppBarCommands(),
                  IconButton(
                    icon: const Icon(Icons.bug_report),
                    onPressed: () => Navigator.pushNamed(context, '/logs'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () => Navigator.pushNamed(context, '/settings'),
                  ),
                ],
                title: Text(currentTab?.file.name ?? 'Machine'),
              ),
      drawer: const FileExplorerDrawer(),
      body: Column(
        children: [
          const TabBarWidget(),
          Expanded(
            child:
                currentTab != null
                    ? const EditorContentSwitcher()
                    : const Center(child: Text('Open a file to start editing')),
          ),
          if (currentPlugin != null) currentPlugin.buildToolbar(ref),
        ],
      ),
    );
  }
}
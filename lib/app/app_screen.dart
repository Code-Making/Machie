// lib/screens/editor_screen.dart
import 'package:back_button_interceptor/back_button_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import 'app_notifier.dart';
import '../editor/plugins/code_editor/code_editor_plugin.dart';
import '../editor/editor_widgets.dart';
import '../explorer/explorer_host_drawer.dart';
import '../command/command_widgets.dart';
import '../explorer/common/file_explorer_dialogs.dart';
import '../settings/settings_notifier.dart';
import '../settings/settings_models.dart';


class AppScreen extends ConsumerStatefulWidget {
  const AppScreen({super.key});

  @override
  ConsumerState<AppScreen> createState() => _AppScreenState();
}

class _AppScreenState extends ConsumerState<AppScreen> {
  late final GlobalKey<ScaffoldState> _scaffoldKey;

  @override
  void initState() {
    super.initState();
    _scaffoldKey = GlobalKey<ScaffoldState>();
    BackButtonInterceptor.add(_backButtonInterceptor);
  }

  @override
  void dispose() {
    BackButtonInterceptor.remove(_backButtonInterceptor);
    super.dispose();
  }

  Future<bool> _backButtonInterceptor(
      bool stopDefaultButtonEvent, RouteInfo info) async {
    final isFullScreen = ref.read(appNotifierProvider).value?.isFullScreen ?? false;
    final notifier = ref.read(appNotifierProvider.notifier);

    if (isFullScreen) {
      notifier.toggleFullScreen();
      return true;
    }

    if (!mounted) return true;
    final shouldExit = await showConfirmDialog(
      context,
      title: 'Exit App?',
      content: 'Are you sure you want to close the application?',
    );

    if (shouldExit) {
      await SystemNavigator.pop();
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appNotifierProvider).value;
    final currentTab = appState?.currentProject?.session.currentTab;
    final currentPlugin = currentTab?.plugin;
    final isFullScreen = appState?.isFullScreen ?? false;
    
    final generalSettings = ref.watch(settingsProvider.select(
      (s) => s.pluginSettings[GeneralSettings] as GeneralSettings?,
    )) ?? GeneralSettings();

    final appBarOverride = appState?.appBarOverride;

    return Scaffold(
      key: _scaffoldKey,
      appBar: (!isFullScreen || !generalSettings.hideAppBarInFullScreen)
          ? (appBarOverride != null
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(kToolbarHeight),
                  child: appBarOverride,
                )
              : AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  actions: [
                    currentPlugin is CodeEditorPlugin
                        ? CodeEditorTapRegion(child: const AppBarCommands())
                        : const AppBarCommands(),
                  ],
                  title: Text(currentTab?.file.name ?? 'Machine'),
                ))
          : null,
      drawer: const ExplorerHostDrawer(),
      body: Column(
        children: [
          if (!isFullScreen || !generalSettings.hideTabBarInFullScreen)
            const TabBarWidget(),
          Expanded(
            // FIX: This is the core of the change.
            // We use KeyedSubtree directly here, keyed by the tab's unique URI.
            // When the URI changes (i.e., we switch tabs), Flutter will throw away
            // the old widget tree and build a new one, correctly initializing the editor.
            child: KeyedSubtree(
              key: ValueKey(currentTab?.file.uri),
              child: currentTab != null
                  // Directly build the editor widget for the current tab.
                  ? currentTab.plugin.buildEditor(currentTab, ref)
                  // Show a placeholder if no tab is open.
                  : const Center(child: Text('Open a file to start editing')),
            ),
          ),
          if (currentPlugin != null && (!isFullScreen || !generalSettings.hideBottomToolbarInFullScreen))
            currentPlugin.buildToolbar(ref),
        ],
      ),
    );
  }
}

// DELETED: The following widgets are no longer needed as their logic has been
// moved directly into the AppScreen's build method for clarity and correctness.
/*
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
*/
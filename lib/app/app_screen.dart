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
import '../explorer/common/file_explorer_dialogs.dart'; // For showConfirmDialog
import '../settings/settings_notifier.dart'; // For GeneralSettings
import '../settings/settings_models.dart';


// REFACTOR: Convert to ConsumerStatefulWidget to manage the back button interceptor.
class AppScreen extends ConsumerStatefulWidget {
  const AppScreen({super.key});

  @override
  ConsumerState<AppScreen> createState() => _AppScreenState();
}

class _AppScreenState extends ConsumerState<AppScreen> {
  @override
  void initState() {
    super.initState();
    // Add the interceptor when the widget is created.
    BackButtonInterceptor.add(_backButtonInterceptor);
  }

  @override
  void dispose() {
    // Remove the interceptor when the widget is disposed to prevent memory leaks.
    BackButtonInterceptor.remove(_backButtonInterceptor);
    super.dispose();
  }

  // The interceptor function.
  Future<bool> _backButtonInterceptor(
      bool stopDefaultButtonEvent, RouteInfo info) async {
    final isFullScreen = ref.read(appNotifierProvider).value?.isFullScreen ?? false;
    final notifier = ref.read(appNotifierProvider.notifier);

    // If in fullscreen, the back button should exit fullscreen mode first.
    if (isFullScreen) {
      notifier.toggleFullScreen();
      return true; // Stop default back action (e.g., quitting the app).
    }

    // If not in fullscreen, show the confirmation dialog to quit.
    final shouldExit = await showConfirmDialog(
      context,
      title: 'Exit App?',
      content: 'Are you sure you want to close the application?',
    );

    if (shouldExit) {
      // If confirmed, use SystemNavigator to close the app.
      await SystemNavigator.pop();
    }

    // Always return true to manually control the back button behavior.
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appNotifierProvider).value;
    final currentTab = appState?.currentProject?.session.currentTab;
    final currentPlugin = currentTab?.plugin;
    final isFullScreen = appState?.isFullScreen ?? false;
    
    // Get fullscreen settings
    final generalSettings = ref.watch(settingsProvider.select(
      (s) => s.pluginSettings[GeneralSettings] as GeneralSettings?,
    )) ?? GeneralSettings();

    final scaffoldKey = GlobalKey<ScaffoldState>();
    final appBarOverride = appState?.appBarOverride;

    return Scaffold(
      key: scaffoldKey,
      // REFACTOR: Conditionally render the AppBar based on fullscreen state and settings.
      appBar: (!isFullScreen || !generalSettings.hideAppBarInFullScreen)
          ? (appBarOverride != null
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
                  ],
                  title: Text(currentTab?.file.name ?? 'Machine'),
                ))
          : null, // Hide AppBar completely in fullscreen.
      drawer: const ExplorerHostDrawer(),
      body: Column(
        children: [
          // REFACTOR: Conditionally render the TabBar
          if (!isFullScreen || !generalSettings.hideTabBarInFullScreen)
            const TabBarWidget(),
          Expanded(
            child:
                currentTab != null
                    ? const EditorContentSwitcher()
                    : const Center(child: Text('Open a file to start editing')),
          ),
          // REFACTOR: Conditionally render the plugin's toolbar
          if (currentPlugin != null && (!isFullScreen || !generalSettings.hideBottomToolbarInFullScreen))
            currentPlugin.buildToolbar(ref),
        ],
      ),
    );
  }
}
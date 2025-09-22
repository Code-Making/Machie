// =========================================
// FILE: lib/app/app_screen.dart
// =========================================

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
import '../editor/tab_state_manager.dart'; // ADDED

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
    bool stopDefaultButtonEvent,
    RouteInfo info,
  ) async {
    final isFullScreen =
        ref.read(appNotifierProvider).value?.isFullScreen ?? false;
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

    // REFACTORED: Get the title by watching the metadata for the current tab.
    // This ensures the title updates on rename without rebuilding the whole screen.
    final currentTabMetadata = ref.watch(
      tabMetadataProvider.select(
        (metadataMap) =>
            currentTab != null ? metadataMap[currentTab.id] : null,
      ),
    );
    final appBarTitle = currentTabMetadata?.title ?? 'Machine';

    final generalSettings =
        ref.watch(
          settingsProvider.select(
            (s) => s.pluginSettings[GeneralSettings] as GeneralSettings?,
          ),
        ) ??
        GeneralSettings();

    final appBarOverride = appState?.appBarOverride;

    return Scaffold(
      key: _scaffoldKey,
      appBar:
          (!isFullScreen || !generalSettings.hideAppBarInFullScreen)
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
                    // REFACTORED: Use the title from the metadata provider.
                    title: Text(appBarTitle),
                  ))
              : null,
      drawer: const ExplorerHostDrawer(),
      body: Column(
        children: [
          if (!isFullScreen || !generalSettings.hideTabBarInFullScreen)
            const TabBarWidget(),
          Expanded(
            // CORRECTED: Wrap the EditorView's container in a FocusScope.
            child: FocusScope(
              child: const EditorView(),
            ),
          ),
          if (currentPlugin != null &&
              (!isFullScreen || !generalSettings.hideBottomToolbarInFullScreen))
            currentPlugin.buildToolbar(ref),
        ],
      ),
    );
  }
}
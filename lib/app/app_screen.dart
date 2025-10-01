// =========================================
// UPDATED: lib/app/app_screen.dart
// =========================================

import 'package:back_button_interceptor/back_button_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_notifier.dart';
import '../editor/editor_widgets.dart';
import '../explorer/explorer_host_drawer.dart';
import '../command/command_widgets.dart';
import '../explorer/common/file_explorer_dialogs.dart';
import '../settings/settings_notifier.dart';
import '../editor/tab_state_manager.dart';

class AppScreen extends ConsumerStatefulWidget {
  const AppScreen({super.key});

  @override
  ConsumerState<AppScreen> createState() => _AppScreenState();
}

class _AppScreenState extends ConsumerState<AppScreen> {
  late final GlobalKey<ScaffoldState> _scaffoldKey;
  // This flag is correctly defined here as a member of the State class.
  bool _isExitDialogShowing = false;

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

  // THE FIX: The interceptor now uses the correct API from the package documentation.
  Future<bool> _backButtonInterceptor(
    bool stopDefaultButtonEvent,
    RouteInfo info,
  ) async {
    // === GUARD CLAUSES ===
    // If any of these are true, we return `false` to let the default back
    // button behavior (like navigating back) happen.

    if (!mounted) return false;

    // 1. Get the current route's name. The root route is always '/'.
    //    If we are on any other named route (like '/settings') or an overlay
    //    route (which often has a null name), we should not intercept.
    final currentRouteName = ModalRoute.of(context)?.settings.name;
    if (currentRouteName != '/') {
      return false;
    }

    // 2. The drawer is part of the Scaffold's state, not a separate route,
    //    so we still need to check for it manually.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      return false;
    }

    // === INTERCEPTION LOGIC ===
    // If we've gotten this far, we are on the home screen with no overlays open.

    final isFullScreen = ref.read(appNotifierProvider).value?.isFullScreen ?? false;
    if (isFullScreen) {
      ref.read(appNotifierProvider.notifier).toggleFullScreen();
      return true; // We handled it. Stop further processing.
    }

    if (_isExitDialogShowing) {
      return true;
    }

    try {
      _isExitDialogShowing = true;
      
      final shouldExit = await showConfirmDialog(
        context,
        title: 'Exit App?',
        content: 'Are you sure you want to close the application?',
      );

      if (shouldExit) {
        await SystemNavigator.pop();
      }
    } finally {
      _isExitDialogShowing = false;
    }
    
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appNotifierProvider).value;
    final currentTab = appState?.currentProject?.session.currentTab;
    final currentPlugin = currentTab?.plugin;
    final isFullScreen = appState?.isFullScreen ?? false;

    final currentTabMetadata = ref.watch(
      tabMetadataProvider.select(
        (metadataMap) => currentTab != null ? metadataMap[currentTab.id] : null,
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
    final double toolbarHeight = Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight;

    return Scaffold(
      key: _scaffoldKey,
      appBar:
          (!isFullScreen || !generalSettings.hideAppBarInFullScreen)
              ? (appBarOverride != null
                  ? PreferredSize(
                      preferredSize: Size.fromHeight(toolbarHeight),
                      child: appBarOverride,
                    )
                  : AppBar(
                      leading: IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      ),
                      actions: [
                        if (currentPlugin != null)
                          currentPlugin.wrapCommandToolbar(const AppBarCommands())
                        else
                          const AppBarCommands(),
                      ],
                      title: Text(appBarTitle),
                    ))
              : null,
      drawer: const ExplorerHostDrawer(),
      body: Column(
        children: [
          if (!isFullScreen || !generalSettings.hideTabBarInFullScreen)
            const TabBarWidget(),
          const Expanded(
            child: FocusScope(child: EditorView()),
          ),
          if (currentPlugin != null &&
              (!isFullScreen || !generalSettings.hideBottomToolbarInFullScreen))
            currentPlugin.buildToolbar(ref),
        ],
      ),
    );
  }
}
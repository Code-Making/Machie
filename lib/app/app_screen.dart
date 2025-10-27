// =========================================
// UPDATED: lib/app/app_screen.dart
// =========================================

import 'package:back_button_interceptor/back_button_interceptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_notifier.dart';
import '../command/command_widgets.dart';
import '../editor/editor_widgets.dart';
import '../editor/plugins/editor_command_context.dart';
import '../editor/tab_state_manager.dart';
import '../explorer/common/file_explorer_dialogs.dart';
import '../explorer/explorer_host_drawer.dart';
import '../settings/settings_notifier.dart';
import '../editor/plugins/plugin_models.dart';

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
    bool canPop = Navigator.of(context).canPop();
    final currentRouteName = ModalRoute.of(context)?.settings.name;
    if (currentRouteName != '/') {
      return false;
    }
    if (canPop == true) {
      return false;
    }
    // 2. The drawer is part of the Scaffold's state, not a separate route,
    //    so we still need to check for it manually.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      return false;
    }

    // === INTERCEPTION LOGIC ===
    // If we've gotten this far, we are on the home screen with no overlays open.

    final isFullScreen =
        ref.read(appNotifierProvider).value?.isFullScreen ?? false;
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

    // REMOVED: The watch for appBarOverride is now in the new _AppScreenAppBar widget.
    // final appBarOverride = ref.watch(
    //   activeCommandContextProvider.select((context) => context.appBarOverride)
    // );
    final double toolbarHeight =
        Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight;

    return Scaffold(
      key: _scaffoldKey,
      // UPDATED: The complex logic is replaced by the new, self-contained widget.
      // This is only rebuilt when high-level state like isFullScreen changes,
      // not when the command context's appBarOverride changes.
      appBar:
          (!isFullScreen || !generalSettings.hideAppBarInFullScreen)
              ? _AppScreenAppBar(
                scaffoldKey: _scaffoldKey,
                currentPlugin: currentPlugin,
                appBarTitle: appBarTitle,
                height: toolbarHeight,
              )
              : null,
      drawer: const ExplorerHostDrawer(),
      body: Column(
        children: [
          if (!isFullScreen || !generalSettings.hideTabBarInFullScreen)
            TabBarWidget(),
          const Expanded(child: FocusScope(child: EditorView())),
          if (currentPlugin != null &&
              (!isFullScreen || !generalSettings.hideBottomToolbarInFullScreen))
            currentPlugin.buildToolbar(ref),
        ],
      ),
    );
  }
}

/// A dedicated widget to build the app bar.
///
/// It encapsulates the watch on `activeCommandContextProvider` so that only the
/// AppBar rebuilds when the command context changes, not the entire `AppScreen`.
/// It implements `PreferredSizeWidget` to be a valid `Scaffold.appBar`.
class _AppScreenAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _AppScreenAppBar({
    required this.scaffoldKey,
    required this.currentPlugin,
    required this.appBarTitle,
    required this.height,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final EditorPlugin? currentPlugin;
  final String appBarTitle;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Encapsulated watch: only this widget rebuilds when the override changes.
    final appBarOverride = ref.watch(
      activeCommandContextProvider.select((context) => context.appBarOverride),
    );

    // If an override from the command context is active, render it directly.
    // This widget, being a PreferredSizeWidget, provides the necessary constraints.
    if (appBarOverride != null) {
      return appBarOverride;
    }

    // Otherwise, build the default AppBar.
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.menu),
        onPressed: () => scaffoldKey.currentState?.openDrawer(),
      ),
      actions: [
        if (currentPlugin != null)
          currentPlugin!.wrapCommandToolbar(const AppBarCommands())
        else
          const AppBarCommands(),
      ],
      title: Text(appBarTitle),
    );
  }

  @override
  Size get preferredSize {
    // Return the default toolbar height. The actual widget returned by `build`
    // (AppBar or a custom override) will manage its own height, making this a
    // safe and standard approach for custom PreferredSizeWidgets.
    return Size.fromHeight(height);
  }
}

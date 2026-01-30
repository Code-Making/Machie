import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:back_button_interceptor/back_button_interceptor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../command/command_widgets.dart';
import '../editor/models/editor_command_context.dart';
import '../editor/models/editor_plugin_models.dart';
import '../editor/tab_metadata_notifier.dart';
import '../editor/widgets/editor_widgets.dart';
import '../explorer/widgets/explorer_host_drawer.dart';
import '../settings/settings_notifier.dart';
import '../widgets/dialogs/file_explorer_dialogs.dart';
import 'app_notifier.dart';

class AppScreen extends ConsumerStatefulWidget {
  const AppScreen({super.key});

  @override
  ConsumerState<AppScreen> createState() => _AppScreenState();
}

class _AppScreenState extends ConsumerState<AppScreen> {
  late final GlobalKey<ScaffoldState> _scaffoldKey;
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

  Future<bool> _backButtonInterceptor(
    bool stopDefaultButtonEvent,
    RouteInfo info,
  ) async {

    if (!mounted) return false;

    bool canPop = Navigator.of(context).canPop();
    final currentRouteName = ModalRoute.of(context)?.settings.name;
    if (currentRouteName != '/') {
      return false;
    }
    if (canPop == true) {
      return false;
    }
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      return false;
    }


    final isFullScreen =
        ref.read(appNotifierProvider).value?.isFullScreen ?? false;
    if (isFullScreen) {
      ref.read(appNotifierProvider.notifier).toggleFullScreen();
      return true;
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

    final double toolbarHeight =
        Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight;

    return Scaffold(
      key: _scaffoldKey,
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
    final appBarOverride = ref.watch(
      activeCommandContextProvider.select((context) => context.appBarOverride),
    );

    if (appBarOverride != null) {
      return appBarOverride;
    }

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
    return Size.fromHeight(height);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/latex.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/plaintext.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_method_channel.dart';
import 'package:saf_util/saf_util_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_system/file_handler.dart';
import 'plugins/code_editor/code_editor_plugin.dart';
import 'plugins/plugin_architecture.dart';
import 'screens/editor_screen.dart';
import 'screens/settings_screen.dart';
import 'session/session_management.dart';

// --------------------
//     Main
// --------------------
final printStream = StreamController<String>.broadcast();

ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFF44336), // Red-500
    brightness: Brightness.dark,
  ).copyWith(
    background: const Color(0xFF2F2F2F),
    surface: const Color(0xFF2B2B29),
  ),
  // Custom AppBar styling (smaller height & title)
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF2B2B29), // Matches surface color
    elevation: 1, // Slight shadow
    scrolledUnderElevation: 1, // Shadow when scrolling
    centerTitle: true, // Optional: Center the title
    titleTextStyle: TextStyle(
      fontSize: 14, // Smaller title
      //fontWeight: FontWeight.w600,
    ),
    toolbarHeight: 56, // Less tall than default (default is 64 in M3)
  ),
  // Custom TabBar styling (matches AppBar background)
  tabBarTheme: TabBarTheme(
    indicator: UnderlineTabIndicator(
      borderSide: BorderSide(
        color: Color(0xFFF44336), // Matches seedColor
        width: 2.0,
      ),
    ),
    unselectedLabelColor: Colors.grey[400], // Unselected tab text
    //dividerColor: Colors.transparent, // Removes top divider
    //overlayColor: MaterialStateProperty.all(Colors.transparent), // Disables ripple
    // Optional: Adjust tab height & padding
    indicatorSize: TabBarIndicatorSize.tab,
    labelPadding: EdgeInsets.symmetric(horizontal: 12.0),
  ),
  // Custom ElevatedButton styling (slightly lighter than background)
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF3A3A3A),
    ),
  ),
);

void main() {
  runZonedGuarded(
    () {
      runApp(
        ProviderScope(
          child: LifecycleHandler(
            child: MaterialApp(
              theme: darkTheme,
              home: AppStartupWidget(
                onLoaded: (context) => const EditorScreen(),
              ),
              routes: {
                '/settings': (_) => const SettingsScreen(),
                '/command-settings': (_) => const CommandSettingsScreen(),
              },
            ),
          ),
        ),
      );
    },
    (error, stack) {
      printStream.add('[ERROR] $error\n$stack');
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, message) {
        final formatted = '[${DateTime.now()}] $message';
        parent.print(zone, formatted);
        printStream.add(formatted);
      },
    ),
  );
}

// --------------------
//   Providers
// --------------------

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((
  ref,
) async {
  return await SharedPreferences.getInstance();
});

final fileHandlerProvider = Provider<FileHandler>((ref) {
  return SAFFileHandler();
});

final pluginRegistryProvider = Provider<Set<EditorPlugin>>(
  (_) => {CodeEditorPlugin()},
);

final activePluginsProvider =
    StateNotifierProvider<PluginManager, Set<EditorPlugin>>((ref) {
      return PluginManager(ref.read(pluginRegistryProvider));
    });

final rootUriProvider = StateProvider<DocumentFile?>((_) => null);

final directoryContentsProvider = FutureProvider.autoDispose
    .family<List<DocumentFile>, String?>((ref, uri) async {
      final handler = ref.read(fileHandlerProvider);
      final targetUri = uri ?? await handler.getPersistedRootUri();
      return targetUri != null ? handler.listDirectory(targetUri) : [];
    });

final sessionManagerProvider = Provider<SessionManager>((ref) {
  return SessionManager(
    fileHandler: ref.watch(fileHandlerProvider),
    plugins: ref.watch(activePluginsProvider),
    prefs: ref.watch(sharedPreferencesProvider).requireValue,
  );
});

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

final bracketHighlightProvider =
    NotifierProvider<BracketHighlightNotifier, BracketHighlightState>(
      BracketHighlightNotifier.new,
    );

final logProvider = StateNotifierProvider<LogNotifier, List<String>>((ref) {
  // Capture the print stream when provider initializes
  final logNotifier = LogNotifier();
  final subscription = printStream.stream.listen(logNotifier.add);
  ref.onDispose(() => subscription.cancel());
  return logNotifier;
});

final commandProvider = StateNotifierProvider<CommandNotifier, CommandState>((
  ref,
) {
  return CommandNotifier(ref: ref, plugins: ref.watch(activePluginsProvider));
});

final appBarCommandsProvider = Provider<List<Command>>((ref) {
  final state = ref.watch(commandProvider);
  final notifier = ref.read(commandProvider.notifier);
  final currentPlugin = ref.watch(sessionProvider.select((s) => s.currentTab?.plugin.runtimeType.toString()));


  return [
    ...state.appBarOrder,
    ...state.pluginToolbarOrder.where(
      (id) => notifier.getCommand(id)?.defaultPosition == CommandPosition.both,
    ),
  ].map((id) => notifier.getCommand(id))
  .where((cmd) => _shouldShowCommand(cmd!, currentPlugin))
  .whereType<Command>()
  .toList();
});


final pluginToolbarCommandsProvider = Provider<List<Command>>((ref) {
  final state = ref.watch(commandProvider);
  final notifier = ref.read(commandProvider.notifier);
  final currentPlugin = ref.watch(sessionProvider.select((s) => s.currentTab?.plugin.runtimeType.toString()));

  return [
    ...state.pluginToolbarOrder,
    ...state.appBarOrder.where(
      (id) => notifier.getCommand(id)?.defaultPosition == CommandPosition.both,
    ),
  ].map((id) => notifier.getCommand(id))
  .whereType<Command>()
  .where((cmd) => _shouldShowCommand(cmd!, currentPlugin))
  .toList();
});

bool _shouldShowCommand(Command cmd, String? currentPlugin) {
  // Always show core commands
  if (cmd.sourcePlugin == 'Core') return true;
  // Show plugin-specific commands only when their plugin is active
  return cmd.sourcePlugin == currentPlugin;
}

final canUndoProvider = StateProvider<bool>((ref) => false);
final canRedoProvider = StateProvider<bool>((ref) => false);
final markProvider = StateProvider<CodeLinePosition?>((ref) => null);


final tabBarScrollProvider = Provider<ScrollController>((ref) {
  return ScrollController();
});

final bottomToolbarScrollProvider = Provider<ScrollController>((ref) {
  return ScrollController();
});


// --------------------
//        Startup
// --------------------
final appStartupProvider = FutureProvider<void>((ref) async {
  await appStartup(ref);
});

Future<void> appStartup(Ref ref) async {
  try {
    final prefs = await ref.read(sharedPreferencesProvider.future);

    ref.read(logProvider.notifier);
    await ref.read(settingsProvider.notifier).loadSettings();
    await ref.read(sessionProvider.notifier).initialize();
  } catch (e, st) {
    print('App startup error: $e\n$st');
    rethrow;
  }
}

class AppStartupWidget extends ConsumerWidget {
  final WidgetBuilder onLoaded;

  const AppStartupWidget({super.key, required this.onLoaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startupState = ref.watch(appStartupProvider);

    return startupState.when(
      loading: () => const AppStartupLoadingWidget(),
      error:
          (error, stack) => AppStartupErrorWidget(
            error: error,
            onRetry: () => ref.invalidate(appStartupProvider),
          ),
      data: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(sessionProvider.notifier).loadSession();
        });
        return onLoaded(context);
      },
    );
  }
}

class AppStartupLoadingWidget extends StatelessWidget {
  const AppStartupLoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Initializing application...'),
          ],
        ),
      ),
    );
  }
}

class AppStartupErrorWidget extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const AppStartupErrorWidget({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 50),
            const SizedBox(height: 20),
            Text('Initialization failed: $error', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

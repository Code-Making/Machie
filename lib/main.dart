import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math'; // For max in SessionState

import 'package:collection/collection.dart'; // For DeepCollectionEquality
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart'; // Not strictly used by main.dart but good to keep if it was related to initial permissions
import 'package:re_editor/re_editor.dart'; // For CodeLinePosition etc.

import 'file_system/file_handler.dart'; // For SAFFileHandler and DocumentFile
import 'plugins/code_editor/code_editor_plugin.dart'; // For CodeEditorPlugin and BracketHighlightNotifier/State
import 'plugins/plugin_architecture.dart'; // For PluginManager, EditorPlugin, Command, CommandNotifier, SettingsNotifier
import 'screens/editor_screen.dart'; // For EditorScreen
import 'screens/settings_screen.dart'; // For SettingsScreen, CommandSettingsScreen, LogNotifier, DebugLogView
import 'session/session_management.dart'; // For LifecycleHandler, SessionManager, SessionNotifier, SessionState, EditorTab


// --------------------
//   Global Providers
// --------------------

// Global provider for SharedPreferences, used across multiple features
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

// Main application startup provider
final appStartupProvider = FutureProvider<void>((ref) async {
  await appStartup(ref);
});

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

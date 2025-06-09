// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_notifier.dart';
import 'plugins/plugin_architecture.dart'; // For CommandSettingsScreen
import 'screens/editor_screen.dart';
import 'screens/settings_screen.dart';

// --------------------
//   Global Providers
// --------------------

// Global provider for SharedPreferences, used by the PersistenceService.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

// The broadcast stream for capturing log messages from `print()`.
final printStream = StreamController<String>.broadcast();

// NEW: A dedicated provider for the app's one-time startup logic.
final appStartupProvider = FutureProvider<void>((ref) async {
  // This provider's job is to ensure the main AppNotifier is initialized.
  // By depending on the `.future`, we wait for the initial `build` method
  // of AppNotifier to complete.
  await ref.read(appNotifierProvider.future);
});


// --------------------
//     ThemeData
// --------------------

ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFF44336), // Red-500
    brightness: Brightness.dark,
  ).copyWith(
    background: const Color(0xFF2F2F2F),
    surface: const Color(0xFF2B2B29),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF2B2B29),
    elevation: 1,
    scrolledUnderElevation: 1,
    centerTitle: true,
    titleTextStyle: TextStyle(fontSize: 14),
    toolbarHeight: 56,
  ),
  tabBarTheme: TabBarTheme(
    indicator: const UnderlineTabIndicator(
      borderSide: BorderSide(
        color: Color(0xFFF44336),
        width: 2.0,
      ),
    ),
    unselectedLabelColor: Colors.grey[400],
    indicatorSize: TabBarIndicatorSize.tab,
    labelPadding: const EdgeInsets.symmetric(horizontal: 12.0),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF3A3A3A),
    ),
  ),
);

// --------------------
//     Main
// --------------------

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
      // Forward unhandled framework errors to the log stream.
      printStream.add('[UNHANDLED_ERROR] $error\n$stack');
    },
    zoneSpecification: ZoneSpecification(
      // Intercept all calls to `print()` and redirect them to our stream.
      print: (self, parent, zone, message) {
        final formatted = '[${DateTime.now()}] $message';
        parent.print(zone, formatted); // Also print to the original console for debugging.
        printStream.add(formatted);
      },
    ),
  );
}

// --------------------
//    Lifecycle & Startup
// --------------------

// Handles app lifecycle events, primarily for saving state.
class LifecycleHandler extends ConsumerStatefulWidget {
  final Widget child;
  const LifecycleHandler({super.key, required this.child});
  @override
  ConsumerState<LifecycleHandler> createState() => _LifecycleHandlerState();
}

class _LifecycleHandlerState extends ConsumerState<LifecycleHandler> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    // When the app is paused or detached, trigger a save of the entire app state.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      await ref.read(appNotifierProvider.notifier).saveAppState();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

// Manages the UI during the initial app loading process.
class AppStartupWidget extends ConsumerWidget {
  final WidgetBuilder onLoaded;

  const AppStartupWidget({super.key, required this.onLoaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // CORRECTED: Watch the dedicated startup provider. This will only run once.
    final startupState = ref.watch(appStartupProvider);

    return startupState.when(
      loading: () => const AppStartupLoadingWidget(),
      error: (error, stack) => AppStartupErrorWidget(
        error: error,
        // Invalidate the startup provider to re-run the initialization.
        onRetry: () => ref.invalidate(appStartupProvider),
      ),
      // Once the startup provider completes successfully, the app is ready.
      data: (_) => onLoaded(context),
    );
  }
}

// Simple loading screen UI.
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

// UI to show if the initial loading fails.
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
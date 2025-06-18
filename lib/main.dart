// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_notifier.dart';
import 'app/lifecycle.dart';
import 'app/editor_screen.dart';
import 'command/command_notifier.dart'; // NEW IMPORT
import 'settings/settings_notifier.dart'; // NEW IMPORT
import 'settings/settings_screen.dart';
import 'utils/logs.dart';
import 'data/persistence_service.dart';

// --------------------
//   Global Providers
// --------------------

// MODIFIED: This is now the single, robust provider for all app initialization.
final appStartupProvider = FutureProvider<void>((ref) async {
  await ref.read(sharedPreferencesProvider.future);
  ref.read(settingsProvider);
  ref.read(commandProvider);
  await ref.read(appNotifierProvider.future);
});

// --------------------
//     ThemeData
// --------------------
// ... (no changes to ThemeData)
ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFFF44336), // Red-500
    brightness: Brightness.dark,
  ).copyWith(surface: const Color(0xFF2B2B29)),
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
      borderSide: BorderSide(color: Color(0xFFF44336), width: 2.0),
    ),
    unselectedLabelColor: Colors.grey[400],
    indicatorSize: TabBarIndicatorSize.tab,
    labelPadding: const EdgeInsets.symmetric(horizontal: 12.0),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3A3A3A)),
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
            // MODIFIED: Wrap MaterialApp to provide the keys
            child: Consumer(
              // Use a consumer to read the providers
              builder: (context, ref, child) {
                return MaterialApp(
                  // NEW: Assign the global keys
                  navigatorKey: ref.watch(navigatorKeyProvider),
                  scaffoldMessengerKey: ref.watch(
                    rootScaffoldMessengerKeyProvider,
                  ),
                  theme: darkTheme,
                  home: AppStartupWidget(
                    onLoaded: (context) => const EditorScreen(),
                  ),
                  routes: {
                    '/settings': (_) => const SettingsScreen(),
                    '/command-settings': (_) => const CommandSettingsScreen(),
                  },
                );
              },
            ),
          ),
        ),
      );
    },
    (error, stack) {
      printStream.add('[UNHANDLED_ERROR] $error\n$stack');
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
//    Lifecycle & Startup
// --------------------

class AppStartupWidget extends ConsumerWidget {
  final WidgetBuilder onLoaded;

  const AppStartupWidget({super.key, required this.onLoaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // This logic is already correct and does not need to change.
    final startupState = ref.watch(appStartupProvider);

    return startupState.when(
      loading: () => const AppStartupLoadingWidget(),
      error:
          (error, stack) => AppStartupErrorWidget(
            error: error,
            onRetry: () => ref.invalidate(appStartupProvider),
          ),
      data: (_) => onLoaded(context),
    );
  }
}

// ... (AppStartupLoadingWidget and AppStartupErrorWidget are unchanged)
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

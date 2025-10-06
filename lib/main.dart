// lib/main.dart
import 'dart:async';
import 'dart:io'; // ADDED: For platform check

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <-- 1. IMPORT THIS
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_notifier.dart';
import 'app/app_screen.dart';
import 'app/lifecycle.dart';
import 'command/command_notifier.dart'; // NEW IMPORT
import 'data/persistence_service.dart';
import 'logs/logs_provider.dart';
import 'project/services/hot_state_cache_service.dart'; // ADDED
import 'settings/settings_notifier.dart'; // NEW IMPORT
import 'settings/settings_screen.dart';

import 'package:flutter_foreground_task/flutter_foreground_task.dart'; // ADD THIS
import 'project/services/hot_state_task_handler.dart'; // ADD THIS

// --------------------
//   Global Providers
// --------------------

final appStartupProvider = FutureProvider<void>((ref) async {
  await ref.read(cacheRepositoryProvider).init();
  // THE FIX: Start the cache service once on app startup (Android only).
  if (Platform.isAndroid) {
    await _startCacheService();
  }
  await ref.read(sharedPreferencesProvider.future);

  ref.read(settingsProvider);
  ref.read(commandProvider);
  await ref.read(appNotifierProvider.future);
});

// --------------------
//     ThemeData
// --------------------
// NEW: A helper function to create ThemeData instances to avoid code duplication.
ThemeData _createThemeData(Color seedColor, Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ).copyWith(
      // Keep surface consistent for dark mode, use default for light
      surface: brightness == Brightness.dark ? const Color(0xFF2B2B29) : null,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor:
          brightness == Brightness.dark ? const Color(0xFF2B2B29) : null,
      elevation: 1,
      scrolledUnderElevation: 1,
      centerTitle: true,
      titleTextStyle: const TextStyle(fontSize: 14),
      toolbarHeight: 48,
    ),
    tabBarTheme: TabBarThemeData(
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: seedColor, width: 2.0),
      ),
      unselectedLabelColor: Colors.grey[400],
      indicatorSize: TabBarIndicatorSize.tab,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8.0),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor:
            brightness == Brightness.dark ? const Color(0xFF3A3A3A) : null,
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor:
          brightness == Brightness.dark ? const Color(0xFF212121) : null,
    ),
  );
}

//iii
// NEW: A provider that builds and returns the theme configuration.
final themeConfigProvider = Provider((ref) {
  // Watch the settings provider for changes.
  final settings = ref.watch(settingsProvider);
  final generalSettings =
      settings.pluginSettings[GeneralSettings] as GeneralSettings;

  final seedColor = Color(generalSettings.accentColorValue);
  final themeMode = generalSettings.themeMode;

  // Create both light and dark themes based on the seed color.
  final lightTheme = _createThemeData(seedColor, Brightness.light);
  final darkTheme = _createThemeData(seedColor, Brightness.dark);

  // Return all the necessary parts for MaterialApp in a record.
  return (light: lightTheme, dark: darkTheme, mode: themeMode);
});
// --------------------
//     Main
// --------------------

void main() {
  final talker = TalkerFlutter.init(
    logger: TalkerLogger(settings: TalkerLoggerSettings()),
    settings: TalkerSettings(
      enabled: true,
      useConsoleLogs: true,
      colors: {
        // Colors for default log types can be defined with AnsiPen
        TalkerLogType.httpResponse.key: AnsiPen()..red(),
        TalkerLogType.error.key: AnsiPen()..green(),
        TalkerLogType.info.key: AnsiPen()..blue(),
        FileOperationLog.getKey: FileOperationLog.getPen,
      },
    ),
  );

  final riverpodObserver = TalkerRiverpodObserver(
    talker: talker,
    settings: TalkerRiverpodLoggerSettings(
      enabled: true,
      printStateFullData: false, // Truncate long state objects
    ),
  );

  WidgetsFlutterBinding.ensureInitialized(); // <-- 2. ENSURE BINDING IS INITIALIZED
  FlutterForegroundTask.initCommunicationPort();
  _initForegroundTask(); // ADD THIS CALL
  // --- 3. SET THE SYSTEM UI STYLE ---
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      // This makes the system navigation bar background black.
      systemNavigationBarColor: Color(0xFF2B2B29),

      // This makes the icons on the navigation bar (back, home, etc.) white.
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runZonedGuarded(
    () {
      runApp(
        ProviderScope(
          overrides: [talkerProvider.overrideWithValue(talker)],
          observers: [riverpodObserver],
          child: LifecycleHandler(
            talker: talker,
            child: Consumer(
              builder: (context, ref, child) {
                // REFACTOR: Watch the new theme provider.
                final themeConfig = ref.watch(themeConfigProvider);

                return MaterialApp(
                  navigatorKey: ref.watch(navigatorKeyProvider),
                  scaffoldMessengerKey: ref.watch(
                    rootScaffoldMessengerKeyProvider,
                  ),
                  // REFACTOR: Apply the dynamic theme configuration.
                  theme: themeConfig.light,
                  darkTheme: themeConfig.dark,
                  //themeMode: themeConfig.mode,
                  themeMode: ThemeMode.dark, // Fixed darkMode for now
                  home: AppStartupWidget(
                    onLoaded: (context) => const AppScreen(),
                  ),
                  routes: {
                    '/settings': (_) => const SettingsScreen(),
                    '/command-settings': (_) => const CommandSettingsScreen(),
                    '/logs':
                        (_) => TalkerScreen(talker: ref.read(talkerProvider)),
                  },
                );
              },
            ),
          ),
        ),
      );
    },
    (error, stack) {
      talker.handle(error, stack, 'Unhandled error');
    },
  );
}

// --------------------
//    Lifecycle & Startup
// --------------------

Future<void> _startCacheService() async {
  if (await FlutterForegroundTask.isRunningService) {
    return;
  }
  FlutterForegroundTask.startService(
    notificationTitle: 'Machine',
    notificationText: 'File cache is running.',
    notificationIcon: const NotificationIcon(
      metaDataName: 'my_service_icon_metadata',
    ),
    notificationButtons: [
      const NotificationButton(
        id: 'STOP_SERVICE_ACTION',
        text: 'Stop Cache Service',
      ),
    ],
    callback: startCallback,
  );
}

void _initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'machine_hot_state_service',
      channelName: 'Machine Hot State Service',
      channelDescription: 'This notification keeps the unsaved file cache alive.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      // The icon is NOT set here. It's set in startService.
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      // CORRECTED: There is no `.manual()` action. To create an event-driven
      // task that doesn't run on a timer, we use `.repeat()` with a very
      // large interval. This effectively makes it wait for manual triggers.
      eventAction: ForegroundTaskEventAction.repeat(99999999),
      autoRunOnBoot: false,
      allowWifiLock: true,
    ),
  );
}

class AppStartupWidget extends ConsumerWidget {
  final WidgetBuilder onLoaded;

  const AppStartupWidget({super.key, required this.onLoaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startupState = ref.watch(appStartupProvider);

    return startupState.when(
      loading: () => const AppStartupLoadingWidget(),
      error: (error, stack) {
        // Report startup errors to Talker
        ref.read(talkerProvider).handle(error, stack, 'Startup error');
        return AppStartupErrorWidget(
          error: error,
          onRetry: () => ref.invalidate(appStartupProvider),
        );
      },
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_notifier.dart';
import 'app/app_screen.dart';
import 'app/lifecycle.dart';
import 'command/command_notifier.dart';
import 'data/cache/hot_state_cache_service.dart';
import 'data/shared_preferences.dart';
import 'logs/logs_provider.dart';
import 'settings/settings_notifier.dart';
import 'settings/settings_screen.dart';

// --------------------
//   Global Providers
// --------------------

final appStartupProvider = FutureProvider<void>((ref) async {
  final talker = ref.read(talkerProvider);
  talker.info('appStartupProvider: Starting async initialization...');


  await ref.read(cacheRepositoryProvider).init();
  await ref.read(hotStateCacheServiceProvider).initializeAndStart();
  await ref.read(sharedPreferencesProvider.future);

  ref.read(settingsProvider);
  ref.read(commandProvider);
  await ref.read(appNotifierProvider.future);

  talker.info('appStartupProvider: Async initialization complete.');
});

// --------------------
//     ThemeData
// --------------------
ThemeData _createThemeData(Color seedColor, Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ).copyWith(
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

/// A provider that builds and returns the theme configuration.
final themeConfigProvider = Provider((ref) {
  final settings = ref.watch(effectiveSettingsProvider);
  final generalSettings =
      settings.pluginSettings[GeneralSettings] as GeneralSettings;

  final seedColor = Color(generalSettings.accentColorValue);
  final themeMode = generalSettings.themeMode;

  final lightTheme = _createThemeData(seedColor, Brightness.light);
  final darkTheme = _createThemeData(seedColor, Brightness.dark);

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
      colors: {FileOperationLog.getKey: FileOperationLog.getPen},
    ),
  );

  final riverpodObserver = TalkerRiverpodObserver(
    talker: talker,
    settings: TalkerRiverpodLoggerSettings(
      enabled: true,
      printProviderDisposed: true,
      printStateFullData: false,
    ),
  );
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Color(0xFF2B2B29),

      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runZonedGuarded(
    () {
      FlutterError.onError = (details) {
        talker.handle(
          details.exception,
          details.stack,
          'Flutter framework error',
        );
      };

      runApp(
        ProviderScope(
          overrides: [talkerProvider.overrideWithValue(talker)],
          observers: [riverpodObserver],
          child: LifecycleHandler(
            talker: talker,
            child: Consumer(
              builder: (context, ref, child) {
                final themeConfig = ref.watch(themeConfigProvider);

                return MaterialApp(
                  navigatorKey: ref.watch(navigatorKeyProvider),
                  scaffoldMessengerKey: ref.watch(
                    rootScaffoldMessengerKeyProvider,
                  ),
                  theme: themeConfig.light,
                  darkTheme: themeConfig.dark,
                  themeMode: ThemeMode.dark,
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

class AppStartupWidget extends ConsumerWidget {
  final WidgetBuilder onLoaded;

  const AppStartupWidget({super.key, required this.onLoaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startupState = ref.watch(appStartupProvider);

    return startupState.when(
      loading: () => const AppStartupLoadingWidget(),
      error: (error, stack) {
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

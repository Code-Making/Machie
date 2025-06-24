// lib/app/app_commands.dart
import 'package:flutter/material.dart';
import '../command/command_models.dart';
import 'app_notifier.dart';

class AppCommands {
  static List<Command> getCommands() => [
    // ... (show_logs and show_settings commands are unchanged)
    BaseCommand(
      id: 'show_logs',
      label: 'Show Logs',
      icon: const Icon(Icons.bug_report),
      defaultPosition: CommandPosition.appBar,
      sourcePlugin: 'App',
      execute: (ref) async {
        final navigatorKey = ref.read(navigatorKeyProvider);
        navigatorKey.currentState?.pushNamed('/logs');
      },
    ),
    BaseCommand(
      id: 'show_settings',
      label: 'Show Settings',
      icon: const Icon(Icons.settings),
      defaultPosition: CommandPosition.appBar,
      sourcePlugin: 'App',
      execute: (ref) async {
        final navigatorKey = ref.read(navigatorKeyProvider);
        navigatorKey.currentState?.pushNamed('/settings');
      },
    ),
    // NEW: The fullscreen command.
    BaseCommand(
      id: 'toggle_fullscreen',
      label: 'Toggle Fullscreen',
      // The icon could be made dynamic in CommandButton, but for now this is simpler.
      icon: const Icon(Icons.fullscreen),
      defaultPosition: CommandPosition.appBar,
      sourcePlugin: 'App',
      execute: (ref) async {
        ref.read(appNotifierProvider.notifier).toggleFullScreen();
      },
    ),
  ];
}

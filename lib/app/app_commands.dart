// =========================================
// UPDATED: lib/app/app_commands.dart
// =========================================

import 'package:flutter/material.dart';
import '../command/command_models.dart';
import 'app_notifier.dart';

class AppCommands {
  static const String scratchpadTabId = 'internal_scratchpad_tab';

  static List<Command> getCommands() => [
    BaseCommand(
      id: 'show_logs',
      label: 'Show Logs',
      icon: const Icon(Icons.bug_report),
      // REFACTORED
      defaultPosition: AppCommandPositions.appBar,
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
      // REFACTORED
      defaultPosition: AppCommandPositions.appBar,
      sourcePlugin: 'App',
      execute: (ref) async {
        final navigatorKey = ref.read(navigatorKeyProvider);
        navigatorKey.currentState?.pushNamed('/settings');
      },
    ),
    BaseCommand(
      id: 'toggle_fullscreen',
      label: 'Toggle Fullscreen',
      icon: const Icon(Icons.fullscreen),
      // REFACTORED
      defaultPosition: AppCommandPositions.appBar,
      sourcePlugin: 'App',
      execute: (ref) async {
        ref.read(appNotifierProvider.notifier).toggleFullScreen();
      },
    ),
  ];
}
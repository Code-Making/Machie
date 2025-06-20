// lib/app/app_commands.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../command/command_models.dart';
import 'app_notifier.dart'; // For navigatorKeyProvider

class AppCommands {
  static List<Command> getCommands() => [
        // The new command for showing the logs screen
        BaseCommand(
          id: 'show_logs',
          label: 'Show Logs',
          icon: const Icon(Icons.bug_report),
          defaultPosition: CommandPosition.appBar,
          sourcePlugin: 'App', // A generic source for app-level commands
          execute: (ref) async {
            final navigatorKey = ref.read(navigatorKeyProvider);
            navigatorKey.currentState?.pushNamed('/logs');
          },
        ),
        // The new command for showing the settings screen
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
      ];
}
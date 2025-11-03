// =========================================
// NEW FILE: lib/editor/tab_context_commands.dart
// =========================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/app_notifier.dart';
import '../command/command_models.dart';

/// A class that provides a list of generic, app-level context menu commands for editor tabs.
class AppTabContextCommands {
  static List<TabContextCommand> getCommands() {
    return [
      BaseTabContextCommand(
        id: 'close_other_tabs',
        label: 'Close Other Tabs',
        icon: const Icon(Icons.close_rounded, size: 20),
        // Source is now 'App' to indicate it's a global command.
        sourcePlugin: 'App',
        canExecuteFor: (ref, activeTab, targetTab) {
          final project = ref.read(appNotifierProvider).value?.currentProject;
          return (project?.session.tabs.length ?? 0) > 1;
        },
        executeFor: (ref, activeTab, targetTab) async {
          final notifier = ref.read(appNotifierProvider.notifier);
          final tabs = ref.read(appNotifierProvider).value!.currentProject!.session.tabs;
          final targetIndex = tabs.indexOf(targetTab);

          final indicesToClose = <int>[];
          for (int i = 0; i < tabs.length; i++) {
            if (i != targetIndex) {
              indicesToClose.add(i);
            }
          }
          notifier.closeMultipleTabs(indicesToClose);
        },
      ),
      // You can add more generic commands here in the future.
      // e.g., "Close Tabs to the Right", "Copy File Path", etc.
    ];
  }
}
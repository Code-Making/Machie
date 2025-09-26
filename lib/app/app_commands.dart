// lib/app/app_commands.dart
import 'package:flutter/material.dart';
import '../command/command_models.dart';
import 'app_notifier.dart';

import 'package:collection/collection.dart';
import '../editor/tab_state_manager.dart';
import '../project/project_models.dart';
import '../project/services/cache_service.dart';
import '../editor/plugins/code_editor/code_editor_plugin.dart';
import '../editor/plugins/plugin_registry.dart';

class AppCommands {
    
  static const String scratchpadTabId = 'internal_scratchpad_tab';
    
  static List<Command> getCommands() => [
    BaseCommand(
      id: 'open_scratchpad',
      label: 'Open Scratchpad',
      icon: const Icon(Icons.edit_note),
      defaultPosition: CommandPosition.appBar,
      sourcePlugin: 'App',
      canExecute: (ref) => ref.watch(appNotifierProvider.select((s) => s.value?.currentProject != null)),
      execute: (ref) async {
        final appNotifier = ref.read(appNotifierProvider.notifier);
        final project = ref.read(appNotifierProvider).value!.currentProject!;
        
        // 1. Check if the scratchpad tab is already open.
        final existingTab = project.session.tabs.firstWhereOrNull(
          (t) => t.id == scratchpadTabId
        );
        if (existingTab != null) {
          final index = project.session.tabs.indexOf(existingTab);
          appNotifier.switchTab(index);
          return;
        }

        // 2. If not open, create it.
        final cacheService = ref.read(cacheServiceProvider);
        final codeEditorPlugin = ref.read(pluginRegistryProvider).whereType<CodeEditorPlugin>().first;

        // 3. Define the virtual file for the scratchpad.
        final scratchpadFile = VirtualDocumentFile(
          uri: 'scratchpad://${project.id}',
          name: 'Scratchpad',
        );

        // 4. Try to load its previous content from the cache.
        final cachedDto = await cacheService.getTabState(project.id, scratchpadTabId);
        String initialContent = '';
        if (cachedDto is CodeEditorHotStateDto) {
          initialContent = cachedDto.content;
        }

        // 5. Create the tab using the CodeEditorPlugin.
        final newTab = await codeEditorPlugin.createTab(
          scratchpadFile, 
          initialContent, 
          id: scratchpadTabId,
        );

        // 6. Add the new tab to the app state.
        final newTabs = [...project.session.tabs, newTab];
        final newProject = project.copyWith(
          session: project.session.copyWith(
            tabs: newTabs,
            currentTabIndex: newTabs.length - 1,
          ),
        );
        appNotifier.updateCurrentProject(newProject);
        
        // 7. IMPORTANT: Initialize its metadata and mark it as dirty.
        // Marking it dirty ensures that the `cacheAllTabs` logic will always
        // save its contents when the app is paused or closed.
        final metadataNotifier = ref.read(tabMetadataProvider.notifier);
        metadataNotifier.initTab(newTab.id, scratchpadFile);
        metadataNotifier.markDirty(newTab.id);
      },
    ),
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

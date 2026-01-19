// FILE: lib/editor/plugins/exporter/exporter_plugin.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/app_notifier.dart';
import '../../../command/command_models.dart';
import '../../models/editor_plugin_models.dart';
import '../../models/editor_tab_models.dart';
import '../../models/editor_command_context.dart'; 
import '../../../data/file_handler/file_handler.dart';
import '../../../data/cache/type_adapters.dart'; 

import 'exporter_models.dart';
import 'exporter_editor.dart';

class ExporterPlugin extends EditorPlugin {
  static const String pluginId = 'com.machine.exporter';

  static const exporterFloatingToolbar = CommandPosition(
    id: 'exporter_floating_toolbar',
    label: 'Exporter Toolbar',
    icon: Icons.import_export,
  );

  @override
  String get id => pluginId;

  @override
  String get name => 'Asset Exporter';

  @override
  Widget get icon => const Icon(Icons.import_export);

  @override
  int get priority => 20;

  @override
  bool supportsFile(DocumentFile file) {
    return file.name.endsWith('.export');
  }

  @override
  List<CommandPosition> getCommandPositions() => [exporterFloatingToolbar];

  ExporterEditorWidgetState? _getEditorState(WidgetRef ref) {
    final tab = ref.read(appNotifierProvider).value?.currentProject?.session.currentTab;
    if (tab is ExporterTab) {
      return tab.editorKey.currentState;
    }
    return null;
  }

  @override
  List<Command> getCommands() {
    return [
      BaseCommand(
        id: 'exporter_toggle_settings',
        label: 'Settings',
        icon: Consumer(
          builder: (context, ref, _) {
            final ctx = ref.watch(activeCommandContextProvider);
            final isActive = ctx is ExporterCommandContext && ctx.isSettingsVisible;
            return Icon(
              Icons.settings_outlined,
              color: isActive ? Theme.of(context).colorScheme.primary : null,
            );
          },
        ),
        defaultPositions: [exporterFloatingToolbar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.toggleSettings(),
      ),
      BaseCommand(
        id: 'exporter_run',
        label: 'Build Export',
        icon: Consumer(
          builder: (context, ref, _) {
            final ctx = ref.watch(activeCommandContextProvider);
            final isBuilding = ctx is ExporterCommandContext && ctx.isBuilding;
            
            if (isBuilding) {
              return SizedBox(
                width: 20, 
                height: 20, 
                child: CircularProgressIndicator(
                  strokeWidth: 2, 
                  color: Theme.of(context).colorScheme.primary,
                )
              );
            }
            return const Icon(Icons.play_arrow_rounded, color: Colors.green);
          },
        ),
        defaultPositions: [exporterFloatingToolbar],
        sourcePlugin: id,
        execute: (ref) async => _getEditorState(ref)?.runExport(),
        canExecute: (ref) {
           final ctx = ref.watch(activeCommandContextProvider);
           return ctx is ExporterCommandContext && !ctx.isBuilding;
        },
      ),
    ];
  }

  @override
  Future<EditorTab> createTab(
    DocumentFile file,
    EditorInitData initData, {
    String? id,
    Completer<EditorWidgetState>? onReadyCompleter,
  }) async {
    final content = (initData.initialContent as EditorContentString).content;
    
    ExportConfig config;
    if (content.trim().isEmpty) {
      config = const ExportConfig(includedFiles: []);
    } else {
      try {
        config = ExportConfig.fromJson(jsonDecode(content));
      } catch (_) {
        config = const ExportConfig(includedFiles: []);
      }
    }

    return ExporterTab(
      plugin: this,
      initialConfig: config,
      id: id,
      onReadyCompleter: onReadyCompleter,
    );
  }

  @override
  EditorWidget buildEditor(EditorTab tab, WidgetRef ref) {
    return ExporterEditorWidget(
      key: (tab as ExporterTab).editorKey,
      tab: tab,
    );
  }

  @override
  String? get hotStateDtoType => null;
  @override
  Type? get hotStateDtoRuntimeType => null;
  @override
  TypeAdapter<TabHotStateDto>? get hotStateAdapter => null;
}

// Define ExporterTab here so it is visible to this file and importers
class ExporterTab extends EditorTab {
  @override
  final GlobalKey<ExporterEditorWidgetState> editorKey;
  final ExportConfig initialConfig;

  ExporterTab({
    required super.plugin,
    required this.initialConfig,
    super.id,
    super.onReadyCompleter,
  }) : editorKey = GlobalKey<ExporterEditorWidgetState>();

  @override
  void dispose() {}
}
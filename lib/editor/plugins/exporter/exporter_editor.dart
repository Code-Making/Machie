// FILE: lib/editor/plugins/exporter/exporter_editor.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/utils/toast.dart';
import 'package:machine/export_core/export_service.dart';

import '../models/editor_command_context.dart';
import 'exporter_models.dart';
import 'exporter_plugin.dart';
import 'widgets/source_file_tree.dart';
import 'widgets/exporter_settings_panel.dart';
import '../../../command/command_widgets.dart'; // For CommandToolbar

class ExporterEditorWidget extends EditorWidget {
  @override
  final ExporterTab tab;

  const ExporterEditorWidget({required super.key, required this.tab}) : super(tab: tab);

  @override
  ExporterEditorWidgetState createState() => ExporterEditorWidgetState();
}

class ExporterEditorWidgetState extends EditorWidgetState<ExporterEditorWidget> {
  late ExportConfig _config;
  bool _isBuilding = false;
  bool _isSettingsVisible = false;

  @override
  void init() {
    _config = widget.tab.initialConfig;
  }
  
  @override
  void syncCommandContext() {
    ref.read(commandContextProvider(widget.tab.id).notifier).state =
        ExporterCommandContext(
      isSettingsVisible: _isSettingsVisible,
      isBuilding: _isBuilding,
    );
  }

  @override
  void onFirstFrameReady() {
    if (mounted && !widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
    syncCommandContext();
  }

  void toggleSettings() {
    setState(() => _isSettingsVisible = !_isSettingsVisible);
    syncCommandContext();
  }

  void _updateConfig(ExportConfig newConfig) {
    setState(() => _config = newConfig);
    ref.read(editorServiceProvider).markCurrentTabDirty();
  }

  void runExport() async {
    if (_config.includedFiles.isEmpty) {
      MachineToast.error("No source files selected.");
      return;
    }

    setState(() => _isBuilding = true);
    syncCommandContext();

    try {
      await ref.read(editorServiceProvider).saveCurrentTab();

      final service = ref.read(exportServiceProvider);
      await service.runExportJob(
        sourceFilePaths: _config.includedFiles,
        outputFolder: _config.outputFolder,
        maxSize: _config.atlasSize,
        padding: _config.padding,
      );

      MachineToast.info("Export Build Successful!");
    } catch (e) {
      MachineToast.error("Build Failed: $e");
    } finally {
      if (mounted) {
        setState(() => _isBuilding = false);
        syncCommandContext();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate panel height: usually ~55% of screen height is good for settings
    final panelHeight = MediaQuery.of(context).size.height * 0.55;
    final bottomOffset = _isSettingsVisible ? 0.0 : -panelHeight;

    return Stack(
      children: [
        // 1. Background: Source File Tree
        Positioned.fill(
          child: Column(
            children: [
              Expanded(
                child: SourceFileTree(
                  selectedFiles: _config.includedFiles.toSet(),
                  onSelectionChanged: (newSet) {
                    _updateConfig(_config.copyWith(includedFiles: newSet.toList()));
                  },
                ),
              ),
              // Spacer to ensure list items scroll above the panel when it opens
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                height: _isSettingsVisible ? panelHeight : 0,
              ),
            ],
          ),
        ),

        // 2. Floating Command Toolbar (Top Right)
        Positioned(
          top: 8,
          right: 8,
          child: Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: const SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: CommandToolbar(
                    position: ExporterPlugin.exporterFloatingToolbar,
                  ),
                ),
              ),
            ),
          ),
        ),

        // 3. Settings Panel sliding up from bottom
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          left: 0,
          right: 0,
          bottom: bottomOffset,
          height: panelHeight,
          child: ExporterSettingsPanel(
            config: _config,
            onChanged: _updateConfig,
            onClose: toggleSettings,
            onBuild: runExport,
            isBuilding: _isBuilding,
          ),
        ),
        
        // 4. Loading Overlay
        if (_isBuilding)
           Positioned(
             top: 0, left: 0, right: 0,
             child: LinearProgressIndicator(
               backgroundColor: Colors.transparent, 
               color: Theme.of(context).colorScheme.secondary,
             ),
           ),
      ],
    );
  }

  @override
  void undo() {}
  @override
  void redo() {}
  @override
  void onSaveSuccess(String newHash) {}
  @override
  Future<TabHotStateDto?> serializeHotState() async => null;
  
  @override
  Future<EditorContent> getContent() async {
    return EditorContentString(jsonEncode(_config.toJson()));
  }
}
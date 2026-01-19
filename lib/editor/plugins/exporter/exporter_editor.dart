import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/utils/toast.dart';
import 'package:machine/export_core/export_service.dart'; // From Phase 3

import 'exporter_models.dart';
import 'exporter_plugin.dart';
import 'widgets/source_file_tree.dart';

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

  @override
  void init() {
    _config = widget.tab.initialConfig;
  }

  @override
  void onFirstFrameReady() {
    if (mounted && !widget.tab.onReady.isCompleted) {
      widget.tab.onReady.complete(this);
    }
  }

  void _updateConfig(ExportConfig newConfig) {
    setState(() => _config = newConfig);
    ref.read(editorServiceProvider).markCurrentTabDirty();
  }

  Future<void> _runExport() async {
    if (_config.includedFiles.isEmpty) {
      MachineToast.error("No source files selected.");
      return;
    }

    setState(() => _isBuilding = true);

    try {
      // 1. Auto-save current config before running
      await ref.read(editorServiceProvider).saveCurrentTab();

      // 2. Call the Export Pipeline (Phase 3 Service)
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
      if (mounted) setState(() => _isBuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left Panel: Source Tree
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Source Files', style: Theme.of(context).textTheme.titleMedium),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SourceFileTree(
                    selectedFiles: _config.includedFiles.toSet(),
                    onSelectionChanged: (newSet) {
                      _updateConfig(_config.copyWith(includedFiles: newSet.toList()));
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Right Panel: Settings
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Configuration', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 24),
              
              TextFormField(
                initialValue: _config.outputFolder,
                decoration: const InputDecoration(
                  labelText: 'Output Folder',
                  helperText: 'Relative to project root',
                  prefixIcon: Icon(Icons.folder_open),
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) => _updateConfig(_config.copyWith(outputFolder: val)),
              ),
              const SizedBox(height: 24),

              Text('Atlas Settings', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              
              DropdownButtonFormField<int>(
                value: _config.atlasSize,
                decoration: const InputDecoration(labelText: 'Max Atlas Size', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 512, child: Text('512x512')),
                  DropdownMenuItem(value: 1024, child: Text('1024x1024')),
                  DropdownMenuItem(value: 2048, child: Text('2048x2048')),
                  DropdownMenuItem(value: 4096, child: Text('4096x4096')),
                ],
                onChanged: (val) {
                  if (val != null) _updateConfig(_config.copyWith(atlasSize: val));
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                initialValue: _config.padding.toString(),
                decoration: const InputDecoration(
                  labelText: 'Padding (px)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (val) {
                  final p = int.tryParse(val);
                  if (p != null) _updateConfig(_config.copyWith(padding: p));
                },
              ),
              
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Remove Unused Tilesets'),
                subtitle: const Text('Strip empty tilesets from TMX output'),
                value: _config.removeUnused,
                onChanged: (val) => _updateConfig(_config.copyWith(removeUnused: val)),
                contentPadding: EdgeInsets.zero,
              ),

              const SizedBox(height: 48),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _isBuilding ? null : _runExport,
                  icon: _isBuilding 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.build),
                  label: Text(_isBuilding ? 'Building Atlas...' : 'Build Export'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Boilerplate implementation
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
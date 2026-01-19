// FILE: lib/editor/plugins/exporter/exporter_editor.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/models/editor_tab_models.dart';
import 'package:machine/editor/services/editor_service.dart';
import 'package:machine/utils/toast.dart';
import 'package:machine/logs/logs_provider.dart';

import '../../models/editor_command_context.dart';
import 'exporter_models.dart';
import 'exporter_plugin.dart';
import 'widgets/source_file_tree.dart';
import 'widgets/exporter_settings_panel.dart';

// Unified Export Imports
import '../../tiled_editor/tiled_asset_resolver.dart';
import '../../../asset_cache/asset_providers.dart';
import '../../../asset_cache/asset_models.dart';
import '../../../command/command_widgets.dart';
import '../../../data/file_handler/file_handler.dart';
import '../unified_export/unified_export_service.dart';
import '../unified_export/unified_export_models.dart';

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

  Future<void> runExport() async {
    if (_config.includedFiles.isEmpty) {
      MachineToast.error("No source files selected.");
      return;
    }

    setState(() => _isBuilding = true);
    syncCommandContext();

    final talker = ref.read(talkerProvider);
    talker.info("Starting Export Job...");

    try {
      await ref.read(editorServiceProvider).saveCurrentTab();

      final repo = ref.read(projectRepositoryProvider);
      if (repo == null) throw Exception("Project repository not found");

      final exportService = ref.read(unifiedExportServiceProvider);
      
      // 1. Prepare Root Nodes from Config
      final rootChildren = <DependencyNode>[];
      
      // Dummy resolver for scanning phase (assets not needed yet)
      final dummyResolver = TiledAssetResolver({}, repo, "");

      for (final relPath in _config.includedFiles) {
         final file = await repo.fileHandler.resolvePath(repo.rootUri, relPath);
         if (file != null) {
           // Scan individual files
           final node = await exportService.scanDependencies(file.uri, repo, dummyResolver);
           rootChildren.add(node);
         }
      }
      
      final rootNode = DependencyNode(
        sourcePath: "Root", 
        destinationPath: "", 
        type: ExportNodeType.unknown, 
        children: rootChildren
      );

      // 2. Identify Assets to Load
      final assetsToLoad = <AssetQuery>{};
      void collectAssets(DependencyNode node) {
        if (node.type == ExportNodeType.image) {
           assetsToLoad.add(AssetQuery(path: node.sourcePath, mode: AssetPathMode.projectRelative));
        }
        for(var c in node.children) collectAssets(c);
      }
      collectAssets(rootNode);
      talker.info("Found ${assetsToLoad.length} assets to load.");

      // 3. Load Assets into this Tab's AssetMap
      // ExporterTab doesn't auto-load, so we force it here
      final assetNotifier = ref.read(assetMapProvider(widget.tab.id).notifier);
      await assetNotifier.updateUris(assetsToLoad);
      
      // 4. Construct Real Resolver
      final assetMap = ref.read(assetMapProvider(widget.tab.id)).value ?? {};
      final resolver = TiledAssetResolver(assetMap, repo, "");

      // 5. Build Atlas
      talker.info("Packing Atlas...");
      final result = await exportService.buildAtlas(
        rootNode, 
        resolver,
        maxAtlasSize: _config.atlasSize,
        stripUnused: _config.removeUnused
      );

      // 6. Ensure Output Directory
      ProjectDocumentFile? destDir = await repo.fileHandler.resolvePath(repo.rootUri, _config.outputFolder);
      if (destDir == null) {
         // Naive creation of one level
         final creation = await repo.fileHandler.createDirectoryAndFile(
           repo.rootUri, 
           "${_config.outputFolder}/.marker"
         );
         destDir = await repo.fileHandler.resolvePath(repo.rootUri, _config.outputFolder);
         // Cleanup marker
         if (creation.file.name == '.marker') {
           await repo.deleteFile(creation.file.uri);
         }
      }

      if (destDir == null) throw Exception("Could not create output directory");

      // 7. Write Export
      talker.info("Writing files to ${destDir.uri}...");
      await exportService.writeExport(
        rootNode, 
        result, 
        destDir.uri, 
        repo,
        exportAsJson: true 
      );

      MachineToast.info("Export Successful!");
    } catch (e, st) {
      talker.handle(e, st, "Export Failed");
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
    final panelHeight = MediaQuery.of(context).size.height * 0.55;
    final bottomOffset = _isSettingsVisible ? 0.0 : -panelHeight;

    return Stack(
      children: [
        // Background: Source File Tree
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                height: _isSettingsVisible ? panelHeight : 0,
              ),
            ],
          ),
        ),

        // Floating Command Toolbar
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

        // Settings Panel
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
        
        // Loading Overlay
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
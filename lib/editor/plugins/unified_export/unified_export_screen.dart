// FILE: lib/editor/plugins/unified_export/unified_export_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/tiled_editor/tiled_asset_resolver.dart';
import 'package:machine/widgets/dialogs/folder_picker_dialog.dart';
import 'package:machine/utils/toast.dart';
import 'unified_export_models.dart';
import 'unified_export_service.dart';

class UnifiedExportScreen extends ConsumerStatefulWidget {
  final String rootFileUri;
  final String tabId;

  const UnifiedExportScreen({super.key, required this.rootFileUri, required this.tabId});

  @override
  ConsumerState<UnifiedExportScreen> createState() => _UnifiedExportScreenState();
}

class _UnifiedExportScreenState extends ConsumerState<UnifiedExportScreen> {
  DependencyNode? _rootNode;
  bool _isScanning = true;
  bool _isExporting = false;
  String? _destinationUri;
  String _destinationDisplay = "Select Destination...";
  
  ExportResult? _previewResult;
  List<ExportLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _log(String msg, {bool error = false}) {
    setState(() {
      _logs.add(ExportLog(msg, isError: error));
    });
  }

  Future<void> _scan() async {
    final resolver = ref.read(tiledAssetResolverProvider(widget.tabId)).valueOrNull;
    final repo = ref.read(projectRepositoryProvider);
    
    if (resolver == null || repo == null) {
      _log("Error: Assets not loaded.", error: true);
      return;
    }

    try {
      _log("Scanning dependencies...");
      final node = await ref.read(unifiedExportServiceProvider).scanDependencies(widget.rootFileUri, repo, resolver);
      if (mounted) {
        setState(() {
          _rootNode = node;
          _isScanning = false;
        });
      }
      _log("Scan complete. Found hierarchy.");
      _generatePreview(); // Auto-generate preview on load
    } catch (e) {
      _log("Scan failed: $e", error: true);
    }
  }

  Future<void> _generatePreview() async {
    if (_rootNode == null) return;
    final resolver = ref.read(tiledAssetResolverProvider(widget.tabId)).value!;
    
    try {
      setState(() => _isExporting = true);
      _log("Packing atlas preview...");
      
      final result = await ref.read(unifiedExportServiceProvider).buildAtlas(
        _rootNode!, 
        resolver, 
        stripUnused: true
      );
      
      if (mounted) {
        setState(() {
          _previewResult = result;
          _isExporting = false;
        });
      }
      _log("Preview generated. Atlas size: ${result.atlases.first.width}x${result.atlases.first.height}");
    } catch (e) {
      _log("Preview failed: $e", error: true);
      setState(() => _isExporting = false);
    }
  }

  Future<void> _doExport() async {
    if (_destinationUri == null) {
      MachineToast.error("Select export destination");
      return;
    }
    if (_previewResult == null) await _generatePreview();
    
    final repo = ref.read(projectRepositoryProvider)!;
    setState(() => _isExporting = true);
    
    try {
      _log("Writing files...");
      await ref.read(unifiedExportServiceProvider).writeExport(
        _rootNode!, 
        _previewResult!, 
        _destinationUri!, 
        repo
      );
      _log("Export Successful!");
      MachineToast.info("Export Complete");
    } catch (e) {
      _log("Export Write Failed: $e", error: true);
    } finally {
      setState(() => _isExporting = false);
    }
  }

  Future<void> _pickDest() async {
    final path = await showDialog<String>(context: context, builder: (_) => const FileOrFolderPickerDialog());
    if (path != null) {
      final repo = ref.read(projectRepositoryProvider)!;
      final file = await repo.fileHandler.resolvePath(repo.rootUri, path);
      if (file != null) {
        setState(() {
          _destinationUri = file.isDirectory ? file.uri : repo.fileHandler.getParentUri(file.uri);
          _destinationDisplay = path;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Unified Export")),
      body: Row(
        children: [
          // Left: Dependency Tree
          Expanded(
            flex: 1,
            child: Column(
              children: [
                ListTile(title: Text("Dependencies", style: Theme.of(context).textTheme.titleMedium)),
                const Divider(height: 1),
                Expanded(
                  child: _isScanning 
                    ? const Center(child: CircularProgressIndicator()) 
                    : _rootNode == null 
                        ? const Center(child: Text("Scan Failed"))
                        : ListView(children: [_buildNodeTile(_rootNode!, 0)]),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Right: Preview & Settings
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Expanded(
                  flex: 2,
                  child: _previewResult == null
                      ? const Center(child: Text("No Preview"))
                      : Center(
                          child: InteractiveViewer(
                            maxScale: 10,
                            child: Image.memory(
                              _previewResult!.atlases.first.pngBytes, 
                              filterQuality: FilterQuality.none,
                            ),
                          ),
                        ),
                ),
                const Divider(height: 1),
                Expanded(
                  flex: 1,
                  child: Container(
                    color: Colors.black12,
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (ctx, i) {
                        final log = _logs[i];
                        return Text(
                          "${log.timestamp.second}:${log.timestamp.millisecond} - ${log.message}",
                          style: TextStyle(
                            color: log.isError ? Colors.red : null, 
                            fontFamily: 'monospace', 
                            fontSize: 12
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _pickDest, 
                          child: Text(_destinationDisplay, overflow: TextOverflow.ellipsis)
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton.icon(
                        onPressed: _isExporting ? null : _doExport,
                        icon: _isExporting 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                          : const Icon(Icons.output),
                        label: const Text("EXPORT"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeTile(DependencyNode node, int depth) {
    return ExpansionTile(
      title: Text(node.sourcePath.split('/').last),
      leading: Icon(_getIcon(node.type), size: 16),
      controlAffinity: ListTileControlAffinity.leading,
      initiallyExpanded: true,
      childrenPadding: EdgeInsets.only(left: 16),
      children: node.children.map((c) => _buildNodeTile(c, depth + 1)).toList(),
    );
  }

  IconData _getIcon(ExportNodeType type) {
    switch (type) {
      case ExportNodeType.tmx: return Icons.grid_on;
      case ExportNodeType.tpacker: return Icons.view_comfy;
      case ExportNodeType.flowGraph: return Icons.hub;
      case ExportNodeType.image: return Icons.image;
      default: return Icons.insert_drive_file;
    }
  }
}
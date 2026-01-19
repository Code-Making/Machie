// FILE: lib/editor/plugins/tiled_editor/widgets/export_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/tiled_editor/tiled_export_service.dart';
import 'package:machine/editor/plugins/tiled_editor/tiled_map_notifier.dart';
import 'package:machine/utils/toast.dart';
import 'package:machine/widgets/dialogs/folder_picker_dialog.dart';
import '../../../../logs/logs_provider.dart';
import '../tiled_asset_resolver.dart';

class ExportDialog extends ConsumerStatefulWidget {
  final TiledMapNotifier notifier;
  final Talker talker;
  final String tabId;
  final String initialMapName; // Added parameter

  const ExportDialog({
    super.key,
    required this.notifier,
    required this.talker,
    required this.tabId,
    required this.initialMapName, // Added parameter
  });
  @override
  ConsumerState<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends ConsumerState<ExportDialog> {
  bool _removeUnusedTilesets = true;
  bool _exportAsJson = false;
  bool _packInAtlas = false;
  String? _destinationFolderUri;
  String _destinationFolderDisplay = 'Not selected';
  bool _isExporting = false;

  late final TextEditingController _mapNameController;
  late final TextEditingController _atlasNameController;

  @override
  void initState() {
    super.initState();
    // FIX: Use the initialMapName passed from the widget, not from the map object.
    _mapNameController = TextEditingController(text: widget.initialMapName);
    _atlasNameController = TextEditingController(text: 'packed_atlas');
  }
  
  @override
  void dispose() {
    _mapNameController.dispose();
    _atlasNameController.dispose();
    super.dispose();
  }


  Future<void> _pickDestinationFolder() async {
    final project = ref.read(appNotifierProvider).value!.currentProject!;
    final repo = ref.read(projectRepositoryProvider)!;

    final selectedRelativePath = await showDialog<String>(
      context: context,
      builder: (_) => const FileOrFolderPickerDialog(),
    );

    if (selectedRelativePath != null) {
      final file = await repo.fileHandler.resolvePath(project.rootUri, selectedRelativePath);
      if (file != null) {
        setState(() {
          _destinationFolderUri = file.isDirectory ? file.uri : repo.fileHandler.getParentUri(file.uri);
          _destinationFolderDisplay = selectedRelativePath;
        });
      }
    }
  }

  Future<void> _startExport() async {
    if (_destinationFolderUri == null) {
      MachineToast.error("Please select a destination folder.");
      return;
    }
    
    setState(() => _isExporting = true);

    try {
      final resolverAsync = ref.read(tiledAssetResolverProvider(widget.tabId));
      if (!resolverAsync.hasValue) {
        throw Exception("Assets are not yet loaded. Please wait a moment and try again.");
      }

      await ref.read(tiledExportServiceProvider).exportMap(
            map: widget.notifier.map,
            resolver: resolverAsync.value!,
            destinationFolderUri: _destinationFolderUri!,
            mapFileName: _mapNameController.text.trim(),
            atlasFileName: _atlasNameController.text.trim(),
            removeUnused: _removeUnusedTilesets,
            asJson: _exportAsJson,
            packInAtlas: _packInAtlas,
          );
      MachineToast.info("Export successful!");
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      widget.talker.handle(e, StackTrace.current, 'Export failed');
      MachineToast.error("Export failed: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // UI remains unchanged
    return AlertDialog(
      title: const Text('Export Map'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Destination', style: TextStyle(fontWeight: FontWeight.bold)),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Export to folder'),
                subtitle: Text(_destinationFolderDisplay, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.folder_open_outlined),
                onTap: _pickDestinationFolder,
              ),
              const Divider(height: 24),
              const Text('Filenames', style: TextStyle(fontWeight: FontWeight.bold)),
              TextFormField(
                controller: _mapNameController,
                decoration: InputDecoration(
                  labelText: 'Map filename',
                  suffixText: _exportAsJson ? '.json' : '.tmx',
                ),
              ),
              if (_packInAtlas)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: TextFormField(
                    controller: _atlasNameController,
                    decoration: const InputDecoration(
                      labelText: 'Atlas filename',
                      suffixText: '.png',
                    ),
                  ),
                ),
              const Divider(height: 24),
              const Text('Options', style: TextStyle(fontWeight: FontWeight.bold)),
              SwitchListTile(
                title: const Text('Export as JSON (.tmj)'),
                subtitle: const Text('Default is XML (.tmx)'),
                value: _exportAsJson,
                onChanged: (value) => setState(() => _exportAsJson = value),
              ),
              SwitchListTile(
                title: const Text('Remove unused tilesets'),
                subtitle: const Text('Cleans the exported map file'),
                value: _removeUnusedTilesets,
                onChanged: (value) => setState(() => _removeUnusedTilesets = value),
              ),
              SwitchListTile(
                title: const Text('Pack into a single atlas'),
                subtitle: const Text('Combines all tiles into one image'),
                value: _packInAtlas,
                onChanged: (value) => setState(() => _packInAtlas = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isExporting || _destinationFolderUri == null ? null : _startExport,
          icon: _isExporting
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.output_outlined),
          label: Text(_isExporting ? 'Exporting...' : 'Export'),
        ),
      ],
    );
  }
}
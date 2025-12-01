// FILE: lib/editor/plugins/tiled_editor/widgets/multi_map_export_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../data/file_handler/file_handler.dart';
import '../../../../project/services/project_hierarchy_service.dart';
import '../../../../utils/toast.dart';
import '../../../../widgets/dialogs/folder_picker_dialog.dart';
import '../services/tiled_project_service.dart';

class MultiMapExportDialog extends ConsumerStatefulWidget {
  const MultiMapExportDialog({super.key});

  @override
  ConsumerState<MultiMapExportDialog> createState() => _MultiMapExportDialogState();
}

class _MultiMapExportDialogState extends ConsumerState<MultiMapExportDialog> {
  final Set<DocumentFile> _selectedMaps = {};
  bool _removeUnused = true;
  bool _asJson = false;
  bool _packInAtlas = true;
  String? _destinationFolderUri;
  String _destinationFolderDisplay = 'Not selected';
  bool _isExporting = false;
  
  // Controllers can be added for atlas/map naming if needed

  @override
  Widget build(BuildContext context) {
    final allFilesAsync = ref.watch(flatFileIndexProvider);

    return AlertDialog(
      title: const Text('Pack Maps into Atlas'),
      content: SizedBox(
        width: double.maxFinite,
        height: 500, // Give it a fixed height
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('1. Select Maps to Export', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: allFilesAsync.when(
                  data: (files) {
                    final tmxFiles = files.where((f) => f.name.toLowerCase().endsWith('.tmx')).toList();
                    if (tmxFiles.isEmpty) {
                      return const Center(child: Text('No .tmx files found in project.'));
                    }
                    return ListView.builder(
                      itemCount: tmxFiles.length,
                      itemBuilder: (context, index) {
                        final file = tmxFiles[index];
                        return CheckboxListTile(
                          title: Text(file.name),
                          value: _selectedMaps.contains(file),
                          onChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                _selectedMaps.add(file);
                              } else {
                                _selectedMaps.remove(file);
                              }
                            });
                          },
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, st) => const Center(child: Text('Could not load project files.')),
                ),
              ),
            ),
            const Text('2. Select Destination', style: TextStyle(fontWeight: FontWeight.bold)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Export to folder'),
              subtitle: Text(_destinationFolderDisplay, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.folder_open_outlined),
              onTap: _pickDestinationFolder,
            ),
            // Other options can be added here (Switches for JSON, etc.)
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isExporting || _destinationFolderUri == null || _selectedMaps.isEmpty
              ? null
              : _startExport,
          icon: _isExporting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.output_outlined),
          label: Text(_isExporting ? 'Exporting...' : 'Export'),
        ),
      ],
    );
  }

  Future<void> _pickDestinationFolder() async {
    // This is identical to the logic in ExportDialog
    final selectedRelativePath = await showDialog<String>(
      context: context,
      builder: (_) => const FileOrFolderPickerDialog(),
    );
    if (selectedRelativePath != null) {
      // ... resolve path and set state for _destinationFolderUri and _destinationFolderDisplay
    }
  }

  Future<void> _startExport() async {
    setState(() => _isExporting = true);
    final talker = ref.read(talkerProvider);
    try {
      final tiledService = ref.read(tiledProjectServiceProvider);
      
      // Load all selected maps headlessly
      final List<TiledMapData> mapsToExport = [];
      await Future.forEach(_selectedMaps, (file) async {
        final mapData = await tiledService.loadMap(file);
        mapsToExport.add(mapData);
      });

      // Call the new service method
      await tiledService.exportMaps(
        mapsToExport: mapsToExport,
        destinationFolderUri: _destinationFolderUri!,
        atlasFileName: 'packed_atlas', // Can be made configurable
        removeUnused: _removeUnused,
        asJson: _asJson,
        packInAtlas: _packInAtlas,
      );

      MachineToast.info("Export successful!");
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      talker.handle(e, st, 'Multi-map export failed');
      MachineToast.error("Export failed: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}
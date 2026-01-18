// FILE: lib/editor/plugins/flow_graph/widgets/property_tiled_object_picker.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tiled/tiled.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/asset_cache/asset_providers.dart';
import 'package:machine/widgets/dialogs/folder_picker_dialog.dart'; // Reusing existing picker
import '../models/flow_references.dart';
import '../models/flow_schema_models.dart';

class PropertyTiledObjectPicker extends ConsumerWidget {
  final FlowPropertyDefinition definition;
  final TiledObjectReference? value;
  final ValueChanged<TiledObjectReference> onChanged;

  const PropertyTiledObjectPicker({
    super.key,
    required this.definition,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayText = value != null
        ? '${value!.objectNameSnapshot ?? "Obj#${value!.objectId}"} (L:${value!.layerId})'
        : 'Select Object...';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(definition.label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          const SizedBox(height: 2),
          InkWell(
            onTap: () => _showPickerDialog(context, ref),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: Row(
                children: [
                  Icon(Icons.category, size: 14, color: Colors.green.shade300),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      displayText,
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPickerDialog(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(projectRepositoryProvider);
    if (repo == null) return;

    final result = await showDialog<TiledObjectReference>(
      context: context,
      builder: (ctx) => _TiledObjectSelectionDialog(
        initialValue: value,
        repo: repo,
      ),
    );

    if (result != null) {
      onChanged(result);
    }
  }
}

class _TiledObjectSelectionDialog extends StatefulWidget {
  final TiledObjectReference? initialValue;
  final ProjectRepository repo;

  const _TiledObjectSelectionDialog({required this.initialValue, required this.repo});

  @override
  State<_TiledObjectSelectionDialog> createState() => _TiledObjectSelectionDialogState();
}

class _TiledObjectSelectionDialogState extends State<_TiledObjectSelectionDialog> {
  String? _selectedMapPath;
  int? _selectedLayerId;
  int? _selectedObjectId;
  String? _selectedObjectName;

  TiledMap? _parsedMap;
  bool _isLoadingMap = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _selectedMapPath = widget.initialValue!.sourceMapPath;
      _selectedLayerId = widget.initialValue!.layerId;
      _selectedObjectId = widget.initialValue!.objectId;
      if (_selectedMapPath != null) {
        _loadMap(_selectedMapPath!);
      }
    }
  }

  Future<void> _loadMap(String path) async {
    setState(() => _isLoadingMap = true);
    try {
      final file = await widget.repo.fileHandler.resolvePath(widget.repo.rootUri, path);
      if (file != null) {
        final content = await widget.repo.readFile(file.uri);
        // Simple parse, ignoring external tilesets for object listing speed
        final map = TileMapParser.parseTmx(content);
        setState(() => _parsedMap = map);
      }
    } catch (e) {
      // Handle error
    } finally {
      setState(() => _isLoadingMap = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Tiled Object'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Map Selection
            ListTile(
              title: const Text('Map File'),
              subtitle: Text(_selectedMapPath ?? 'None'),
              trailing: const Icon(Icons.folder_open),
              onTap: () async {
                final path = await showDialog<String>(
                  context: context,
                  builder: (_) => const FileOrFolderPickerDialog(),
                );
                if (path != null && path.endsWith('.tmx')) {
                  setState(() {
                    _selectedMapPath = path;
                    _selectedLayerId = null;
                    _selectedObjectId = null;
                    _parsedMap = null;
                  });
                  _loadMap(path);
                }
              },
            ),
            const Divider(),
            
            if (_isLoadingMap)
              const Center(child: CircularProgressIndicator())
            else if (_parsedMap != null) ...[
              // Layer Selection
              DropdownButtonFormField<int>(
                value: _selectedLayerId,
                decoration: const InputDecoration(labelText: 'Layer'),
                items: _parsedMap!.layers
                    .whereType<ObjectGroup>()
                    .map((l) => DropdownMenuItem(
                          value: l.id,
                          child: Text(l.name),
                        ))
                    .toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedLayerId = val;
                    _selectedObjectId = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              
              // Object Selection
              if (_selectedLayerId != null)
                DropdownButtonFormField<int>(
                  value: _selectedObjectId,
                  decoration: const InputDecoration(labelText: 'Object'),
                  items: _getObjectsInLayer(_selectedLayerId!).map((o) {
                    final name = o.name.isEmpty ? 'Object ${o.id}' : o.name;
                    return DropdownMenuItem(
                      value: o.id,
                      onTap: () => _selectedObjectName = name,
                      child: Text('$name (ID:${o.id})'),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedObjectId = val),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _selectedMapPath != null && _selectedLayerId != null && _selectedObjectId != null
              ? () {
                  Navigator.pop(
                    context,
                    TiledObjectReference(
                      sourceMapPath: _selectedMapPath,
                      layerId: _selectedLayerId!,
                      objectId: _selectedObjectId!,
                      objectNameSnapshot: _selectedObjectName,
                    ),
                  );
                }
              : null,
          child: const Text('Select'),
        ),
      ],
    );
  }

  List<TiledObject> _getObjectsInLayer(int layerId) {
    if (_parsedMap == null) return [];
    final layer = _parsedMap!.layers.firstWhere((l) => l.id == layerId, orElse: () => ObjectGroup(id: -1));
    if (layer is ObjectGroup) {
      return layer.objects;
    }
    return [];
  }
}
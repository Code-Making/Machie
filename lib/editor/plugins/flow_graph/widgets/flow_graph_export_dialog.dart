// FILE: lib/editor/plugins/flow_graph/widgets/flow_graph_export_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/flow_graph/flow_graph_asset_resolver.dart';
import 'package:machine/editor/plugins/flow_graph/flow_graph_notifier.dart';
import 'package:machine/editor/plugins/flow_graph/services/flow_export_service.dart';
import 'package:machine/utils/toast.dart';
import 'package:machine/widgets/dialogs/folder_picker_dialog.dart';
import 'package:path/path.dart' as p;
import '../../../tab_metadata_notifier.dart';

class FlowGraphExportDialog extends ConsumerStatefulWidget {
  final String tabId;
  final FlowGraphNotifier notifier;

  const FlowGraphExportDialog({
    super.key,
    required this.tabId,
    required this.notifier,
  });

  @override
  ConsumerState<FlowGraphExportDialog> createState() => _FlowGraphExportDialogState();
}

class _FlowGraphExportDialogState extends ConsumerState<FlowGraphExportDialog> {
  late final TextEditingController _nameController;
  String? _destinationUri;
  String _destinationDisplay = 'Select destination...';
  bool _isExporting = false;
  bool _embedSchema = true;

  @override
  void initState() {
    super.initState();
    final metadata = ref.read(tabMetadataProvider)[widget.tabId];
    final initialName = metadata != null ? p.basenameWithoutExtension(metadata.file.name) : 'flow';
    _nameController = TextEditingController(text: initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDestination() async {
    final project = ref.read(appNotifierProvider).value?.currentProject;
    final repo = ref.read(projectRepositoryProvider);
    if (project == null || repo == null) return;

    final path = await showDialog<String>(
      context: context,
      builder: (_) => const FileOrFolderPickerDialog(),
    );

    if (path != null) {
      final file = await repo.fileHandler.resolvePath(project.rootUri, path);
      if (file != null) {
        setState(() {
          _destinationUri = file.isDirectory ? file.uri : repo.fileHandler.getParentUri(file.uri);
          _destinationDisplay = path;
        });
      }
    }
  }

  Future<void> _doExport() async {
    if (_destinationUri == null) {
      MachineToast.error('Please select a destination folder.');
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      MachineToast.error('Please enter a filename.');
      return;
    }

    setState(() => _isExporting = true);

    try {
      final resolverAsync = ref.read(flowGraphAssetResolverProvider(widget.tabId));
      
      if (!resolverAsync.hasValue) {
        throw Exception('Assets are not fully loaded. Please wait and try again.');
      }

      await ref.read(flowExportServiceProvider).export(
        graph: widget.notifier.graph,
        resolver: resolverAsync.value!,
        destinationFolderUri: _destinationUri!,
        fileName: _nameController.text.trim(),
        embedSchema: _embedSchema,
      );

      MachineToast.info('Export successful!');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      MachineToast.error('Export failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export Flow Graph'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Destination Folder'),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_open),
            title: Text(_destinationDisplay, overflow: TextOverflow.ellipsis),
            onTap: _pickDestination,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Filename (without extension)'),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'e.g. character_logic',
              suffixText: '.json',
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Embed Schema'),
            subtitle: const Text('Includes schema definition in the file'),
            value: _embedSchema,
            onChanged: (val) => setState(() => _embedSchema = val),
            contentPadding: EdgeInsets.zero,
          )
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isExporting ? null : _doExport,
          child: _isExporting 
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Export'),
        ),
      ],
    );
  }
}
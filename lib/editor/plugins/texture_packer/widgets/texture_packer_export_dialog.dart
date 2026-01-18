// FILE: lib/editor/plugins/texture_packer/widgets/texture_packer_export_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/editor/plugins/texture_packer/services/pixi_export_service.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/utils/toast.dart';
import 'package:machine/widgets/dialogs/folder_picker_dialog.dart';
import '../texture_packer_asset_resolver.dart';

class TexturePackerExportDialog extends ConsumerStatefulWidget {
  final String tabId;
  final TexturePackerNotifier notifier;

  const TexturePackerExportDialog({
    super.key,
    required this.tabId,
    required this.notifier,
  });

  @override
  ConsumerState<TexturePackerExportDialog> createState() => _TexturePackerExportDialogState();
}

class _TexturePackerExportDialogState extends ConsumerState<TexturePackerExportDialog> {
  final TextEditingController _nameController = TextEditingController(text: 'atlas');
  String? _destinationUri;
  String _destinationDisplay = 'Select destination...';
  bool _isExporting = false;

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
      // KEY CHANGE: Use resolver provider instead of raw map
      final resolverAsync = ref.read(texturePackerAssetResolverProvider(widget.tabId));
      
      if (!resolverAsync.hasValue) {
        throw Exception('Assets are not fully loaded. Please wait and try again.');
      }

      await ref.read(pixiExportServiceProvider).export(
        project: widget.notifier.project,
        resolver: resolverAsync.value!,
        destinationFolderUri: _destinationUri!,
        fileName: _nameController.text.trim(),
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
    // ... (UI code remains exactly the same as original)
    return AlertDialog(
      title: const Text('Export Texture Atlas (PixiJS)'),
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
              hintText: 'e.g. characters',
              suffixText: '.png / .json',
            ),
          ),
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
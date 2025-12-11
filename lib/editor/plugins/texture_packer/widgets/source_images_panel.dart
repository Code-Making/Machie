import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/utils/toast.dart';
import 'package:machine/widgets/dialogs/folder_picker_dialog.dart';

class SourceImagesPanel extends ConsumerWidget {
  final String tabId;
  const SourceImagesPanel({super.key, required this.tabId});

  Future<void> _addImage(BuildContext context, WidgetRef ref) async {
    final newPath = await showDialog<String>(
      context: context,
      builder: (_) => const FileOrFolderPickerDialog(),
    );
    if (newPath != null) {
      if (!newPath.toLowerCase().endsWith('.png')) {
        MachineToast.error('Please select a PNG image.');
        return;
      }
      ref.read(texturePackerNotifierProvider(tabId).notifier).addSourceImage(newPath);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceImages = ref.watch(texturePackerNotifierProvider(tabId)
        .select((project) => project.sourceImages));
    final activeIndex = ref.watch(activeSourceImageIndexProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('Source Images', style: Theme.of(context).textTheme.titleMedium),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: sourceImages.length,
            itemBuilder: (context, index) {
              final imageConfig = sourceImages[index];
              return ListTile(
                title: Text(imageConfig.path, overflow: TextOverflow.ellipsis),
                selected: index == activeIndex,
                onTap: () {
                  ref.read(activeSourceImageIndexProvider.notifier).state = index;
                },
                // TODO: Add a context menu for 'Remove' or 'Edit Slicing'
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: OutlinedButton.icon(
            onPressed: () => _addImage(context, ref),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add Image'),
          ),
        ),
      ],
    );
  }
}
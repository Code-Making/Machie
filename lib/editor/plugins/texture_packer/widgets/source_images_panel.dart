import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';
import 'package:machine/widgets/dialogs/file_explorer_dialogs.dart'; // For confirmation dialog

class SourceImagesPanel extends ConsumerWidget {
  final TexturePackerNotifier notifier;
  final VoidCallback onAddImage;
  final VoidCallback onClose; // Callback to close the panel

  const SourceImagesPanel({
    super.key,
    required this.notifier,
    required this.onAddImage,
    required this.onClose,
  });

  // --- SOURCE PANEL REFACTOR: Delete Action ---
  Future<void> _removeImage(BuildContext context, WidgetRef ref, int index) async {
    final imagePath = notifier.project.sourceImages[index].path;
    final confirm = await showConfirmDialog(
      context,
      title: 'Remove Source Image?',
      content: 'Are you sure you want to remove "$imagePath"?\n\nSprites using this image may become invalid. This action cannot be undone from here.',
    );

    if (confirm) {
      final activeIndex = ref.read(activeSourceImageIndexProvider);

      notifier.removeSourceImage(index);

      // After removal, adjust the active index to prevent errors
      if (activeIndex == index) {
        // If we deleted the active one, select the first one if possible
        ref.read(activeSourceImageIndexProvider.notifier).state = 0;
      } else if (activeIndex > index) {
        // If we deleted an image that came *before* the active one,
        // we need to shift the active index down by one.
        ref.read(activeSourceImageIndexProvider.notifier).state = activeIndex - 1;
      }
      // If we deleted an image after the active one, the index remains valid.
    }
  }
  // --- END REFACTOR ---

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceImages = notifier.project.sourceImages;
    final activeIndex = ref.watch(activeSourceImageIndexProvider);

    // --- SOURCE PANEL REFACTOR: UI Overhaul ---
    return Material(
      elevation: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Title and Close Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Text('Source Images', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                  tooltip: 'Close Panel',
                )
              ],
            ),
          ),
          const Divider(height: 1),
          // List of images
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
                  // Trailing delete button
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    tooltip: 'Remove Image',
                    onPressed: () => _removeImage(context, ref, index),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          // Add button footer
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: OutlinedButton.icon(
              onPressed: onAddImage,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Add Image'),
            ),
          ),
        ],
      ),
    );
    // --- END REFACTOR ---
  }
}
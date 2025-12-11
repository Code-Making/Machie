import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_editor_widget.dart';
import 'package:machine/editor/plugins/texture_packer/texture_packer_notifier.dart';

class SourceImagesPanel extends ConsumerWidget {
  final String tabId;
  final VoidCallback onAddImage;

  const SourceImagesPanel({
    super.key,
    required this.tabId,
    required this.onAddImage,
  });


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceImages = ref.watch(texturePackerNotifierProvider(tabId)
        .select((project) => project.sourceImages));
    final activeIndex = ref.watch(activeSourceImageIndexProvider);

    return Material(
      elevation: 4,
      child: Column(
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
                );
              },
            ),
          ),
          const Divider(height: 1),
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
  }
}
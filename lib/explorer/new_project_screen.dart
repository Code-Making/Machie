// lib/explorer/new_project_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/app_notifier.dart';
import '../data/file_handler/local_file_handler.dart';
import '../project/project_factory.dart';

class NewProjectScreen extends ConsumerWidget {
  const NewProjectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final factories = ref.watch(projectFactoryRegistryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create or Open Project'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
      body: ListView.builder(
        itemCount: factories.length,
        itemBuilder: (context, index) {
          final factory = factories.values.elementAt(index);
          return ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: Text(factory.name),
            subtitle: Text(factory.description),
            onTap: () async {
              // 1. Pick a directory from the file system
              final fileHandler = LocalFileHandlerFactory.create();
              final pickedDir = await fileHandler.pickDirectory();

              if (pickedDir != null && context.mounted) {
                // 2. Call the AppNotifier with the folder and the selected factory's type ID
                await ref.read(appNotifierProvider.notifier).openProjectFromFolder(
                      folder: pickedDir,
                      projectTypeId: factory.projectTypeId,
                    );
                // 3. Close all dialogs/drawers and return to the editor
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          );
        },
      ),
    );
  }
}
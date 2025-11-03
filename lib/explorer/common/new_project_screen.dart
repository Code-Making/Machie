// lib/explorer/new_project_screen.dart

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Project imports:
import '../../app/app_notifier.dart';
import '../../data/file_handler/local_file_handler.dart';

// REFACTOR: This screen now needs to show the different project "types".
// Let's create a simple model for that.
class ProjectTypeInfo {
  final String id;
  final String name;
  final String description;
  const ProjectTypeInfo(this.id, this.name, this.description);
}

final projectTypesProvider = Provider<List<ProjectTypeInfo>>((ref) {
  return const [
    ProjectTypeInfo(
      'local_persistent',
      'Persistent Project',
      'Saves session data and settings in a hidden ".machine" folder within your project directory.',
    ),
    ProjectTypeInfo(
      'simple_local',
      'Simple Project',
      'A temporary project. No files are created in the project folder. Session is discarded when another project is opened.',
    ),
  ];
});

class NewProjectScreen extends ConsumerWidget {
  const NewProjectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectTypes = ref.watch(projectTypesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create or Open Project'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: projectTypes.length,
        itemBuilder: (context, index) {
          final projectType = projectTypes[index];
          return ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: Text(projectType.name),
            subtitle: Text(projectType.description),
            onTap: () async {
              final fileHandler = LocalFileHandlerFactory.create();
              final pickedDir = await fileHandler.pickDirectory();

              if (pickedDir != null && context.mounted) {
                await ref
                    .read(appNotifierProvider.notifier)
                    .openProjectFromFolder(
                      folder: pickedDir,
                      projectTypeId: projectType.id,
                    );
                if (!context.mounted) return;
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          );
        },
      ),
    );
  }
}

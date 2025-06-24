// lib/explorer/plugins/file_explorer/file_explorer_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../project/project_models.dart';
import '../../common/file_explorer_widgets.dart';
import '../../common/file_operations_footer.dart';
import 'file_explorer_state.dart';
import '../../explorer_plugin_registry.dart'; // REFACTOR: Import generic provider

class FileExplorerView extends ConsumerWidget {
  final Project project;
  const FileExplorerView({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // REFACTOR: Now uses the generic settings provider.
    final fileExplorerState =
        ref.watch(activeExplorerSettingsProvider) as FileExplorerSettings?;

    // Handle the case where state might not be ready.
    if (fileExplorerState == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: DirectoryView(
            directory: project.rootUri,
            projectRootUri: project.rootUri,
            // Pass the state down to the truly common widget.
            state: fileExplorerState,
          ),
        ),
        RootDropZone(projectRootUri: project.rootUri),
        FileOperationsFooter(projectRootUri: project.rootUri),
      ],
    );
  }
}

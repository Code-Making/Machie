// lib/explorer/plugins/file_explorer/file_explorer_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../project/project_models.dart';
import '../../common/file_explorer_widgets.dart';
import '../../common/file_operations_footer.dart';
import 'file_explorer_state.dart';

class FileExplorerView extends ConsumerWidget {
  final Project project;
  const FileExplorerView({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // REFACTOR: State is read directly from a simple provider now.
    final fileExplorerState = ref.watch(fileExplorerStateProvider(project.id));

    return Column(
      children: [
        Expanded(
          child: DirectoryView(
            directory: project.rootUri,
            projectRootUri: project.rootUri,
            projectId: project.id,
            // Pass the state down
            state: fileExplorerState,
          ),
        ),
        FileOperationsFooter(
          projectRootUri: project.rootUri,
          projectId: project.id,
        ),
      ],
    );
  }
}
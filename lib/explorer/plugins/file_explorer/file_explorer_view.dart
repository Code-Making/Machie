// lib/explorer/plugins/file_explorer/file_explorer_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../project/project_models.dart';
import '../../common/file_explorer_widgets.dart';
import '../../common/file_operations_footer.dart';
import 'file_explorer_state.dart';
import '../../explorer_plugin_registry.dart'; // REFACTOR: Import generic provider

// MODIFIED: Converted to a ConsumerStatefulWidget
class FileExplorerView extends ConsumerStatefulWidget {
  final Project project;
  const FileExplorerView({super.key, required this.project});

  @override
  ConsumerState<FileExplorerView> createState() => _FileExplorerViewState();
}

class _FileExplorerViewState extends ConsumerState<FileExplorerView> {
  // ADDED: Local state to track if a drag is happening anywhere over the view.
  bool _isDragInProgress = false;

  @override
  Widget build(BuildContext context) {
    final fileExplorerState =
        ref.watch(activeExplorerSettingsProvider) as FileExplorerSettings?;

    if (fileExplorerState == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // ADDED: A parent DragTarget to detect when a drag enters or leaves the explorer area.
    return DragTarget<DocumentFile>(
      // This builder renders the actual UI.
      builder: (context, candidateData, rejectedData) {
        return Column(
          children: [
            Expanded(
              child: DirectoryView(
                directory: widget.project.rootUri,
                projectRootUri: widget.project.rootUri,
                state: fileExplorerState,
              ),
            ),
            // Pass the drag-in-progress state down to the drop zone.
            RootDropZone(
              projectRootUri: widget.project.rootUri,
              isDragActive: _isDragInProgress,
            ),
            FileOperationsFooter(projectRootUri: widget.project.rootUri),
          ],
        );
      },
      // When a draggable enters this large area, we update the state.
      onWillAcceptWithDetails: (details) {
        if (!_isDragInProgress) {
          setState(() {
            _isDragInProgress = true;
          });
        }
        // We return false because this parent target's job is only DETECTION.
        // We want the actual acceptance to be handled by the child targets (folders, RootDropZone).
        return false;
      },
      // When the draggable leaves this area, we reset the state.
      onLeave: (data) {
        setState(() {
          _isDragInProgress = false;
        });
      },
      // Also reset on drop, just in case `onLeave` doesn't fire (e.g., app switch).
      onAcceptWithDetails: (details) {
        setState(() {
          _isDragInProgress = false;
        });
      },
    );
  }
}
// lib/explorer/plugins/file_explorer/file_explorer_view.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/data/file_handler/file_handler.dart';
import 'package:machine/project/project_models.dart';
import 'package:machine/explorer/common/file_operations_footer.dart';
import 'package:machine/explorer/common/file_explorer_widgets.dart';

class FileExplorerView extends ConsumerStatefulWidget {
  final Project project;
  const FileExplorerView({super.key, required this.project});

  @override
  ConsumerState<FileExplorerView> createState() => _FileExplorerViewState();
}

class _FileExplorerViewState extends ConsumerState<FileExplorerView> {
  // Local state to track if a drag is happening anywhere over the view.
  bool _isDragInProgress = false;

  @override
  Widget build(BuildContext context) {
    // A parent DragTarget to detect when a drag enters or leaves the explorer area.
    return DragTarget<ProjectDocumentFile>(
      builder: (context, candidateData, rejectedData) {
        return Column(
          children: [
            Expanded(
              child: DirectoryView(
                directoryUri: widget.project.rootUri,
                depth: 1,
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
        if (mounted && !_isDragInProgress) {
          setState(() => _isDragInProgress = true);
        }
        // This parent target only detects; it doesn't accept the drop itself.
        return false;
      },
      // When the draggable leaves this area, we reset the state.
      onLeave: (data) {
        if (mounted) setState(() => _isDragInProgress = false);
      },
      // Also reset on drop, just in case `onLeave` doesn't fire.
      onAcceptWithDetails: (details) {
        if (mounted) setState(() => _isDragInProgress = false);
      },
    );
  }
}
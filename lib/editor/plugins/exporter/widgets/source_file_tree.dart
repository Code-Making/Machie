import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:machine/app/app_notifier.dart';
import 'package:machine/data/repositories/project/project_repository.dart';
import 'package:machine/data/file_handler/file_handler.dart';

class SourceFileTree extends ConsumerWidget {
  final Set<String> selectedFiles;
  final ValueChanged<Set<String>> onSelectionChanged;

  const SourceFileTree({
    super.key,
    required this.selectedFiles,
    required this.onSelectionChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(appNotifierProvider).value?.currentProject;
    if (project == null) return const SizedBox.shrink();

    return _FolderNode(
      uri: project.rootUri,
      projectRoot: project.rootUri,
      selectedFiles: selectedFiles,
      onSelectionChanged: onSelectionChanged,
      isRoot: true,
    );
  }
}

class _FolderNode extends ConsumerStatefulWidget {
  final String uri;
  final String projectRoot;
  final Set<String> selectedFiles;
  final ValueChanged<Set<String>> onSelectionChanged;
  final bool isRoot;

  const _FolderNode({
    required this.uri,
    required this.projectRoot,
    required this.selectedFiles,
    required this.onSelectionChanged,
    this.isRoot = false,
  });

  @override
  ConsumerState<_FolderNode> createState() => _FolderNodeState();
}

class _FolderNodeState extends ConsumerState<_FolderNode> {
  bool _isExpanded = true; // Default expanded for visibility
  List<ProjectDocumentFile>? _children;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    setState(() => _isLoading = true);
    try {
      final repo = ref.read(projectRepositoryProvider)!;
      final files = await repo.listDirectory(widget.uri);
      
      if (mounted) {
        setState(() {
          // Sort folders first, then files
          _children = files..sort((a, b) {
            if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleSelection(String relativePath, bool? value) {
    final newSet = Set<String>.from(widget.selectedFiles);
    if (value == true) {
      newSet.add(relativePath);
    } else {
      newSet.remove(relativePath);
    }
    widget.onSelectionChanged(newSet);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(left: 16.0),
        child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_children == null) return const SizedBox.shrink();

    final repo = ref.read(projectRepositoryProvider)!;

    // Filter list to only show Directories and Supported Files (.tmx, .tpacker)
    final visibleChildren = _children!.where((f) {
      if (f.isDirectory) return true;
      final ext = f.name.split('.').last.toLowerCase();
      return ext == 'tmx' || ext == 'tpacker';
    }).toList();

    if (visibleChildren.isEmpty && !widget.isRoot) return const SizedBox.shrink();

    final List<Widget> nodes = visibleChildren.map((file) {
      final relativePath = repo.fileHandler.getPathForDisplay(file.uri, relativeTo: widget.projectRoot);

      if (file.isDirectory) {
        return _FolderNode(
          uri: file.uri,
          projectRoot: widget.projectRoot,
          selectedFiles: widget.selectedFiles,
          onSelectionChanged: widget.onSelectionChanged,
        );
      } else {
        final isSelected = widget.selectedFiles.contains(relativePath);
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 16),
          leading: Checkbox(
            value: isSelected,
            onChanged: (val) => _toggleSelection(relativePath, val),
          ),
          title: Text(file.name),
          onTap: () => _toggleSelection(relativePath, !isSelected),
        );
      }
    }).toList();

    if (widget.isRoot) {
      return ListView(children: nodes);
    }

    // Get folder name from URI relative to root or parent
    final folderName = widget.uri.split('/').lastWhere((element) => element.isNotEmpty);

    return ExpansionTile(
      title: Text(folderName, style: const TextStyle(fontWeight: FontWeight.bold)),
      leading: const Icon(Icons.folder_open, size: 20),
      initiallyExpanded: _isExpanded,
      childrenPadding: const EdgeInsets.only(left: 16),
      onExpansionChanged: (val) => setState(() => _isExpanded = val),
      children: nodes,
    );
  }
}